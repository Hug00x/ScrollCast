import 'dart:typed_data';
//Interface abstrata para serviço de PDF
abstract class PdfService {

  //Retorna o número de páginas do PDF no caminho dado
  Future<int> getPageCount(String path);
  
  //Renderiza uma página do PDF como imagem
  Future<Uint8List> renderPageAsImage(
    String path,
    int pageIndex, {
    int targetWidth = 1600,
  });
}
