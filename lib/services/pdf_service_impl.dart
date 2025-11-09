import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

import 'pdf_service.dart';

class PdfServiceImpl implements PdfService {
  @override
  Future<int> getPageCount(String path) async {
    final doc = await PdfDocument.openFile(path);
    final count = doc.pagesCount;
    await doc.close();
    return count;
  }

  @override
  Future<Uint8List> renderPageAsImage(
    String path,
    int pageIndex, {
    int targetWidth = 1600,
  }) async {
    final doc = await PdfDocument.openFile(path);
    final page = await doc.getPage(pageIndex + 1); // 1-based

    final aspect = page.height / page.width;
    final double w = targetWidth.toDouble();
    final double h = w * aspect;

    final rendered = await page.render(
      width: w,
      height: h,
      format: PdfPageImageFormat.png,
      backgroundColor: '#FFFFFFFF',
    );

    final bytes = rendered!.bytes;
    await page.close();
    await doc.close();
    return bytes;
  }
}