import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

import 'pdf_service.dart';

// pdf_service_impl.dart
//
// Ideia geral / propósito:
// - Implementação concreta de `PdfService` usando a biblioteca `pdfx`.
// - Fornece utilitários para obter o número de páginas de um ficheiro PDF
//   e para renderizar uma página do PDF como imagem (PNG) com um tamanho
//   alvo específico.
//
// Notas de implementação:
// - Os métodos abrem o documento com `PdfDocument.openFile`, realizam a
//   operação necessária e fecham o documento (e a página) para soltar
//   recursos nativos.
// - A função `renderPageAsImage` calcula a dimensão da imagem com base na
//   largura alvo e mantém a proporção original da página.

class PdfServiceImpl implements PdfService {
  /// Devolve a contagem de páginas de um PDF localizado em `path`.
  ///
  /// Fluxo:
  /// 1. Abre o documento com `PdfDocument.openFile`.
  /// 2. Lê `pagesCount`.
  /// 3. Fecha o documento.
  /// 4. Retorna o número de páginas.
  @override
  Future<int> getPageCount(String path) async {
    final doc = await PdfDocument.openFile(path);
    final count = doc.pagesCount;
    await doc.close();
    return count;
  }

  /// Renderiza a página `pageIndex` do PDF em `path` como PNG e devolve os
  /// bytes da imagem (`Uint8List`).
  ///
  /// Parâmetros:
  /// - `path`: caminho para o ficheiro PDF.
  /// - `pageIndex`: índice zero-based da página a renderizar.
  /// - `targetWidth`: largura alvo em pixels para a imagem resultante (mantém
  ///    a proporção da página ao calcular a altura).
  ///
  /// Fluxo:
  /// 1. Abre o documento.
  /// 2. Obtém a página.
  /// 3. Calcula a altura mantendo a proporção original da página.
  /// 4. Renderiza a página como PNG com as dimensões calculadas.
  /// 5. Fecha a página e o documento e devolve os bytes da imagem.
  @override
  Future<Uint8List> renderPageAsImage(
    String path,
    int pageIndex, {
    int targetWidth = 1600,
  }) async {
    final doc = await PdfDocument.openFile(path);
    final page = await doc.getPage(pageIndex + 1);

    // Calcular largura/altura mantendo a proporção da página.
    final aspect = page.height / page.width;
    final double w = targetWidth.toDouble();
    final double h = w * aspect;

    // Renderizar como PNG com background.
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