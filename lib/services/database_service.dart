import '../models/pdf_document_model.dart';
import '../models/annotations.dart';
import '../models/notebook_model.dart';

abstract class DatabaseService {
  Future<void> upsertPdf(PdfDocumentModel doc);
  Future<PdfDocumentModel?> getPdfById(String id);
  Future<List<PdfDocumentModel>> listPdfs({String? query});
  Future<void> deletePdf(String id);

  Future<void> savePageAnnotations(PageAnnotations page);
  Future<PageAnnotations?> getPageAnnotations(String pdfId, int pageIndex);
  Future<List<PageAnnotations>> getAllAnnotations(String pdfId);
  Future<void> deleteAnnotations(String pdfId, {int? pageIndex});

  // Notebooks
  Future<void> upsertNotebook(NotebookModel nb);
  Future<NotebookModel?> getNotebookById(String id);
  Future<List<NotebookModel>> listNotebooks({String? folder});
  Future<List<String>> listNotebookFolders(); // todas as pastas usadas
  Future<void> deleteNotebook(String id);

  Future<void> saveNotebookPage({
    required String notebookId,
    required int pageIndex,
    required PageAnnotations page,     // reutiliza PageAnnotations
  });
  Future<PageAnnotations?> getNotebookPage(String notebookId, int pageIndex);
  Future<List<PageAnnotations>> getAllNotebookPages(String notebookId);
  Future<void> deleteNotebookPages(String notebookId, {int? pageIndex});
}