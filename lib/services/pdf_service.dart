import 'dart:typed_data';
import '../models/annotations.dart';

abstract class PdfService {
  Future<int> getPageCount(String path);

  Future<Uint8List> renderPageAsImage(
    String path,
    int pageIndex, {
    int targetWidth = 1600,
  });

  Future<void> exportFlattened({
    required String originalPath,
    required List<PageAnnotations> annotationsByPage,
    required String outPath,
    int targetWidth = 2000,
  });
}
