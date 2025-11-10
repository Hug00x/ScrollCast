import 'dart:async';
import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/pdf_document_model.dart';
import '../models/annotations.dart';
import 'database_service.dart';
import '../main.dart';
import '../models/notebook_model.dart';

// database_service_impl.dart
//
// Propósito geral:
// - Implementação de `DatabaseService` usando Hive para persistência local.
// - Gira em torno de várias boxes dependentes do UID do utilizador para
//   armazenar PDFs, anotações por página, favoritos, cadernos (notebooks)
//   e páginas de notebooks.
// - Fornece métodos CRUD para objetos de domínio (PdfDocumentModel,
//   PageAnnotations, NotebookModel), bem como streams/notifications para
//   eventos relevantes.
//
// Notas de implementação:
// - Cada box é nomeada com o UID para isolar dados entre utilizadores.
// - Há lógica para fechar boxes do UID anterior quando o utilizador muda de
//   conta (ver `onAccountSwitched`).
// - Anotações de páginas são serializadas como JSON dentro da box `annotations`.

class DatabaseServiceImpl implements DatabaseService {
  // Mantém o último UID usado para conseguirmos fechar as boxes antigas
  String? _lastUid;

  // Getter que devolve o uid atual com fallback para '_anon'. Também
  // inicializa _lastUid na primeira chamada.
  String get _uid {
    final u = ServiceLocator.instance.auth.currentUid ?? '_anon';
    _lastUid ??= u;
    return u;
  }

  // ===== Nomes das boxes dependentes do UID =====
  String get _pdfsBoxName   => 'pdfs_$_uid';
  String get _annBoxName    => 'annotations_$_uid';
  String get _favBoxName    => 'favorites_$_uid';
  String get _nbBoxName     => 'notebooks_$_uid';
  String get _nbPagesName   => 'notebook_pages_$_uid';

  // Abre uma box Hive se ainda não estiver aberta (reutiliza se já aberta).
  Future<Box> _open(String name) async =>
      Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);

  // ===== Stream de favoritos =====
  // Usamos um StreamController broadcast para notificar listeners quando os
  // favoritos mudam (setFavorite/delete). A stream exposta é `favoritesEvents()`.
  final _favEventsCtrl = StreamController<void>.broadcast();
  @override
  Stream<void> favoritesEvents() => _favEventsCtrl.stream;
  void _emitFav() {
    if (!_favEventsCtrl.isClosed) _favEventsCtrl.add(null);
  }

  // ===== PDFs =====
  // upsertPdf: insere ou atualiza o PdfDocumentModel na box de PDFs.
  @override
  Future<void> upsertPdf(PdfDocumentModel doc) async {
    final box = await _open(_pdfsBoxName);
    await box.put(doc.id, doc.toMap());
  }

  // getPdfById: recupera um PDF por id e desserializa para PdfDocumentModel.
  @override
  Future<PdfDocumentModel?> getPdfById(String id) async {
    final box = await _open(_pdfsBoxName);
    final map = box.get(id);
    if (map == null) return null;
    return PdfDocumentModel.fromMap(Map<String, dynamic>.from(map));
  }

  // listPdfs: lista todos os PDFs, com opção de filtrar por query no nome.
  @override
  Future<List<PdfDocumentModel>> listPdfs({String? query}) async {
    final box = await _open(_pdfsBoxName);
    final items = box.values
        .cast<Map>()
        .map((m) => PdfDocumentModel.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    if (query == null || query.isEmpty) return items;
    final q = query.toLowerCase();
    return items.where((d) => d.name.toLowerCase().contains(q)).toList();
  }

  // deletePdf: remove o PDF, as anotações associadas e também o remove dos
  // favoritos.
  @override
  Future<void> deletePdf(String id) async {
    final box = await _open(_pdfsBoxName);
    await box.delete(id);

    // apaga anotações do PDF
    final ann = await _open(_annBoxName);
    final keys = ann.keys.whereType<String>().where((k) => k.startsWith('$id:')).toList();
    await ann.deleteAll(keys);

    // remove dos favoritos + notifica
    final fav = await _open(_favBoxName);
    await fav.delete(id);
    _emitFav();
  }

  // ===== Anotações do PDF =====
  // As anotações por página são guardadas na box `annotations` usando a chave
  // 'pdfId:pageIndex' e com o conteúdo serializado em JSON.
  @override
  Future<void> savePageAnnotations(PageAnnotations page) async {
    final box = await _open(_annBoxName);
    final key = '${page.pdfId}:${page.pageIndex}';
    await box.put(key, json.encode(page.toMap()));
  }

  @override
  Future<PageAnnotations?> getPageAnnotations(String pdfId, int pageIndex) async {
    final box = await _open(_annBoxName);
    final raw = box.get('$pdfId:$pageIndex');
    if (raw == null) return null;
    return PageAnnotations.fromMap(json.decode(raw) as Map<String, dynamic>);
  }

  @override
  //Obtém todas as anotações de um PDF
  Future<List<PageAnnotations>> getAllAnnotations(String pdfId) async {
    final box = await _open(_annBoxName);
    final prefix = '$pdfId:';
    final list = <PageAnnotations>[];
    for (final k in box.keys.whereType<String>()) {
      if (k.startsWith(prefix)) {
        final raw = box.get(k);
        list.add(PageAnnotations.fromMap(json.decode(raw) as Map<String, dynamic>));
      }
    }
    list.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return list;
  }

  @override
  //Apaga anotações
  Future<void> deleteAnnotations(String pdfId, {int? pageIndex}) async {
    final box = await _open(_annBoxName);
    if (pageIndex == null) {
      final keys = box.keys.whereType<String>().where((k) => k.startsWith('$pdfId:')).toList();
      await box.deleteAll(keys);
    } else {
      await box.delete('$pdfId:$pageIndex');
    }
  }

  // ===== Favoritos =====
  // setFavorite / isFavorite / listFavorites gerem a box de favoritos e
  // permitem à UI marcar/desmarcar e listar favoritos (mantendo ordenação por
  // lastOpened quando necessário).
  @override
  Future<void> setFavorite(String pdfId, bool isFav) async {
    final fav = await _open(_favBoxName);
    if (isFav) {
      await fav.put(pdfId, true);
    } else {
      await fav.delete(pdfId);
    }
    _emitFav(); // 🔔 notifica ouvintes
  }
  
  @override
  // Verifica se um pdf é favorito
  Future<bool> isFavorite(String pdfId) async {
    final fav = await _open(_favBoxName);
    return fav.get(pdfId, defaultValue: false) == true;
  }

  @override
  Future<List<PdfDocumentModel>> listFavorites({String? query}) async {
    final fav = await _open(_favBoxName);
    final ids = fav.keys.whereType<String>().toSet();
    if (ids.isEmpty) return <PdfDocumentModel>[];

    final all = await listPdfs(query: query);
    return all.where((d) => ids.contains(d.id)).toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
  }

  // ===== Notebooks =====
  @override
  Future<void> upsertNotebook(NotebookModel nb) async {
    final box = await _open(_nbBoxName);
    await box.put(nb.id, nb.toMap());
  }

  @override
  // Recupera um notebook por id e desserializa para NotebookModel
  Future<NotebookModel?> getNotebookById(String id) async {
    final box = await _open(_nbBoxName);
    final map = box.get(id);
    if (map == null) return null;
    return NotebookModel.fromMap(Map<String, dynamic>.from(map));
  }

  @override
  //Lista todos os notebooks, com opção de filtrar por pasta
  Future<List<NotebookModel>> listNotebooks({String? folder}) async {
    final box = await _open(_nbBoxName);
    final items = box.values
        .cast<Map>()
        .map((m) => NotebookModel.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    if (folder == null) return items;
    return items.where((n) => n.folder == folder).toList();
  }

  @override
  //Lista todas as pastas de notebooks
  Future<List<String>> listNotebookFolders() async {
    final box = await _open(_nbBoxName);
    final items = box.values
        .cast<Map>()
        .map((m) => NotebookModel.fromMap(Map<String, dynamic>.from(m)));
    final set = <String>{};
    for (final n in items) {
      if (n.folder != null && n.folder!.isNotEmpty) set.add(n.folder!);
    }
    return set.toList()..sort();
  }

  @override
  //Apaga um notebook e as suas páginas associadas
  Future<void> deleteNotebook(String id) async {
    final box = await _open(_nbBoxName);
    await box.delete(id);
    // apaga páginas associadas
    final pages = await _open(_nbPagesName);
    final keys = pages.keys.whereType<String>().where((k) => k.startsWith('$id:')).toList();
    await pages.deleteAll(keys);
  }

  // ===== Páginas de notebook =====
  // Guardamos as PageAnnotations na box `notebook_pages` usando a chave
  // 'notebookId:pageIndex' com valor JSON.
  @override
  Future<void> saveNotebookPage({
    required String notebookId,
    required int pageIndex,
    required PageAnnotations page,
  }) async {
    final box = await _open(_nbPagesName);
    final key = '$notebookId:$pageIndex';
    await box.put(key, json.encode(page.toMap()));
  }

  @override
  //Obtém uma página específica de um notebook
  Future<PageAnnotations?> getNotebookPage(String notebookId, int pageIndex) async {
    final box = await _open(_nbPagesName);
    final raw = box.get('$notebookId:$pageIndex');
    if (raw == null) return null;
    return PageAnnotations.fromMap(json.decode(raw) as Map<String, dynamic>);
  }

  @override
  //Obtém todas as páginas de um notebook
  Future<List<PageAnnotations>> getAllNotebookPages(String notebookId) async {
    final box = await _open(_nbPagesName);
    final prefix = '$notebookId:';
    final list = <PageAnnotations>[];
    for (final k in box.keys.whereType<String>()) {
      if (k.startsWith(prefix)) {
        final raw = box.get(k);
        list.add(PageAnnotations.fromMap(json.decode(raw) as Map<String, dynamic>));
      }
    }
    list.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return list;
  }

  @override
  //Apaga páginas de notebook
  Future<void> deleteNotebookPages(String notebookId, {int? pageIndex}) async {
    final box = await _open(_nbPagesName);
    if (pageIndex == null) {
      final keys = box.keys.whereType<String>().where((k) => k.startsWith('$notebookId:')).toList();
      await box.deleteAll(keys);
    } else {
      await box.delete('$notebookId:$pageIndex');
    }
  }

  // ===== Troca de conta (fecha boxes do UID anterior) =====
  // Fecha boxes correspondentes ao UID antigo para evitar elevar uso de
  // recursos e a mistura de dados entre utilizadores.
  Future<void> _closeIfOpen(String name) async {
    if (Hive.isBoxOpen(name)) {
      await Hive.box(name).close();
    }
  }

  @override
  Future<void> onAccountSwitched() async {
    final newUid = ServiceLocator.instance.auth.currentUid ?? '_anon';
    if (_lastUid == null || _lastUid == newUid) {
      _lastUid = newUid; // inicializa na primeira chamada
      return;
    }

    // fecha boxes do UID antigo
    await _closeIfOpen('pdfs_${_lastUid!}');
    await _closeIfOpen('annotations_${_lastUid!}');
    await _closeIfOpen('favorites_${_lastUid!}');
    await _closeIfOpen('notebooks_${_lastUid!}');
    await _closeIfOpen('notebook_pages_${_lastUid!}');

    // passa a trackear o novo UID
    _lastUid = newUid;
  }
}
