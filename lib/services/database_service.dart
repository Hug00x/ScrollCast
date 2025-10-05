import '../models/pdf_document_model.dart';
import '../models/annotations.dart';

abstract class DatabaseService {
  Future<void> upsertPdf(PdfDocumentModel doc);
  Future<PdfDocumentModel?> getPdfById(String id);
  Future<List<PdfDocumentModel>> listPdfs({String? query});
  Future<void> deletePdf(String id);

  Future<void> savePageAnnotations(PageAnnotations page);
  Future<PageAnnotations?> getPageAnnotations(String pdfId, int pageIndex);
  Future<List<PageAnnotations>> getAllAnnotations(String pdfId);
  Future<void> deleteAnnotations(String pdfId, {int? pageIndex});
}
