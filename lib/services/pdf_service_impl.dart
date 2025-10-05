import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:pdfx/pdfx.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pwpdf;

import '../models/annotations.dart';
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

  @override
  Future<void> exportFlattened({
    required String originalPath,
    required List<PageAnnotations> annotationsByPage,
    required String outPath,
    int targetWidth = 2000,
  }) async {
    final src = await PdfDocument.openFile(originalPath);
    final pdf = pw.Document();

    for (int i = 0; i < src.pagesCount; i++) {
      final page = await src.getPage(i + 1);

      final aspect = page.height / page.width;
      final double w = targetWidth.toDouble();
      final double h = w * aspect;

      // Renderiza a página original em bitmap
      final base = await page.render(
        width: w,
        height: h,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFFFF',
      );
      await page.close();

      // Compoe as anotações por cima do bitmap base (dart:ui)
      final ann = annotationsByPage.firstWhere(
        (a) => a.pageIndex == i,
        orElse: () => PageAnnotations(pdfId: '', pageIndex: i),
      );
      final annotatedPng = await _composeAnnotatedPng(base!.bytes, ann);

      // Escreve a imagem final anotada como uma página do novo PDF
      pdf.addPage(
        pw.Page(
          pageFormat: pwpdf.PdfPageFormat(w, h, marginAll: 0),
          build: (ctx) => pw.Image(pw.MemoryImage(annotatedPng), fit: pw.BoxFit.cover),
        ),
      );
    }

    final file = File(outPath);
    await file.writeAsBytes(await pdf.save());
    await src.close();
  }

  /// Desenha strokes (e, se quiseres, ícones/pins) sobre a imagem base e devolve um PNG.
  Future<Uint8List> _composeAnnotatedPng(Uint8List basePng, PageAnnotations ann) async {
    // Decode da imagem base
    final codec = await ui.instantiateImageCodec(basePng);
    final frame = await codec.getNextFrame();
    final baseImage = frame.image;

    // Canvas para compor
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Fundo
    final bgPaint = ui.Paint();
    canvas.drawImage(baseImage, ui.Offset.zero, bgPaint);

    // Strokes
    for (final s in ann.strokes) {
      final paint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..strokeWidth = s.mode == StrokeMode.highlighter ? s.width * 1.6 : s.width
        ..color = ui.Color(s.color).withOpacity(s.mode == StrokeMode.highlighter ? 0.35 : 1.0);

      for (int j = 0; j < s.points.length - 1; j++) {
        canvas.drawLine(s.points[j], s.points[j + 1], paint);
      }
    }

    // (Opcional) pinos de áudio visíveis no export
    // final pinPaint = ui.Paint()..color = const ui.Color(0xFFFF3B30);
    // for (final n in ann.audioNotes) {
    //   canvas.drawCircle(n.position, 8, pinPaint);
    // }

    // Exporta para PNG
    final picture = recorder.endRecording();
    final annotated = await picture.toImage(baseImage.width, baseImage.height);
    final bytes = await annotated.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }
}