import 'dart:typed_data';

abstract class PdfService {
  Future<int> getPageCount(String path);

  Future<Uint8List> renderPageAsImage(
    String path,
    int pageIndex, {
    int targetWidth = 1600,
  });
}
