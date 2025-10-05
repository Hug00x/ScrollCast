import 'dart:convert';
import 'package:hive/hive.dart';

import '../models/pdf_document_model.dart';
import '../models/annotations.dart';
import 'database_service.dart';
import '../main.dart'; // para ServiceLocator

class DatabaseServiceImpl implements DatabaseService {
  String get _uid => ServiceLocator.instance.auth.currentUid ?? '_anon';

  String get _pdfsBoxName => 'pdfs_$_uid';
  String get _annBoxName  => 'annotations_$_uid';

  Future<Box> _open(String name) async => Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);

  @override
  Future<void> upsertPdf(PdfDocumentModel doc) async {
    final box = await _open(_pdfsBoxName);
    await box.put(doc.id, doc.toMap());
  }

  @override
  Future<PdfDocumentModel?> getPdfById(String id) async {
    final box = await _open(_pdfsBoxName);
    final map = box.get(id);
    if (map == null) return null;
    return PdfDocumentModel.fromMap(Map<String, dynamic>.from(map));
  }

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

  @override
  Future<void> deletePdf(String id) async {
    final box = await _open(_pdfsBoxName);
    await box.delete(id);
    final ann = await _open(_annBoxName);
    final keys = ann.keys.whereType<String>().where((k) => k.startsWith('$id:')).toList();
    await ann.deleteAll(keys);
  }

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
  Future<void> deleteAnnotations(String pdfId, {int? pageIndex}) async {
    final box = await _open(_annBoxName);
    if (pageIndex == null) {
      final keys = box.keys.whereType<String>().where((k) => k.startsWith('$pdfId:')).toList();
      await box.deleteAll(keys);
    } else {
      await box.delete('$pdfId:$pageIndex');
    }
  }
}
