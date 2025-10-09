import '../models/pdf_document_model.dart';
import '../models/annotations.dart';
import '../models/notebook_model.dart';

abstract class DatabaseService {
  // ===== PDFs =====
  Future<void> upsertPdf(PdfDocumentModel doc);
  Future<PdfDocumentModel?> getPdfById(String id);
  Future<List<PdfDocumentModel>> listPdfs({String? query});
  Future<void> deletePdf(String id);

  // Anotações (PDF)
  Future<void> savePageAnnotations(PageAnnotations page);
  Future<PageAnnotations?> getPageAnnotations(String pdfId, int pageIndex);
  Future<List<PageAnnotations>> getAllAnnotations(String pdfId);
  Future<void> deleteAnnotations(String pdfId, {int? pageIndex});

  // ===== Favoritos =====
  Future<void> setFavorite(String pdfId, bool isFav);
  Future<bool> isFavorite(String pdfId);
  Future<List<PdfDocumentModel>> listFavorites({String? query});

  /// 🔔 Emite um evento sempre que a lista de favoritos muda
  Stream<void> favoritesEvents();

  // ===== Cadernos (Notebooks) =====
  Future<void> upsertNotebook(NotebookModel nb);
  Future<NotebookModel?> getNotebookById(String id);
  Future<List<NotebookModel>> listNotebooks({String? folder});
  Future<List<String>> listNotebookFolders();
  Future<void> deleteNotebook(String id);

  // Páginas do caderno
  Future<void> saveNotebookPage({
    required String notebookId,
    required int pageIndex,
    required PageAnnotations page,
  });
  Future<PageAnnotations?> getNotebookPage(String notebookId, int pageIndex);
  Future<List<PageAnnotations>> getAllNotebookPages(String notebookId);
  Future<void> deleteNotebookPages(String notebookId, {int? pageIndex});
}
