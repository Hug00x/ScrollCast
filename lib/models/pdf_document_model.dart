import 'dart:convert';

/*
  PdfDocumentModel

  Propósito geral:
  - Modelo simples que representa um documento PDF gerido pela aplicação.
  - Contém metadados essenciais como número de páginas, última abertura,
    última página visualizada e um histórico local de cores recentes usadas nas anotações.
  - Fornece métodos utilitários para cópia (`copyWith`) e
    serialização/deserialização (toMap/fromMap/toJson/fromJson).

  Organização do ficheiro:
  - `originalPath` aponta para a cópia do ficheiro dentro do diretório
    da aplicação.
  - `recentColors` armazena cores como inteiros, para uso rápido
    no UI (p. ex. histórico de cores na toolbar).
*/

class PdfDocumentModel {
  // Identificador único do documento.
  final String id;

  // Nome do ficheiro apresentado ao utilizador.
  final String name;

  // Caminho para o ficheiro PDF original guardado pela app.
  final String originalPath;

  // Caminho opcional para uma versão anotada do PDF.
  final String? annotatedPath;

  // Número de páginas do documento.
  final int pageCount;

  // Data/hora em que o documento foi aberto pela última vez.
  final DateTime lastOpened;

  // Última página visualizada.
  final int lastPage;

  // Histórico de cores recentes usado nas anotações (ints ARGB).
  final List<int> recentColors;

  PdfDocumentModel({
    required this.id,
    required this.name,
    required this.originalPath,
    required this.pageCount,
    required this.lastOpened,
    this.annotatedPath,
    this.lastPage = 0,
    this.recentColors = const [],
  });

  // copyWith: cria uma cópia imutável com campos substituídos quando
  // fornecidos — útil para atualizações parciais antes de persistir.
  PdfDocumentModel copyWith({
    String? id,
    String? name,
    String? originalPath,
    String? annotatedPath,
    int? pageCount,
    DateTime? lastOpened,
    int? lastPage,
    List<int>? recentColors,
  }) {
    return PdfDocumentModel(
      id: id ?? this.id,
      name: name ?? this.name,
      originalPath: originalPath ?? this.originalPath,
      annotatedPath: annotatedPath ?? this.annotatedPath,
      pageCount: pageCount ?? this.pageCount,
      lastOpened: lastOpened ?? this.lastOpened,
      lastPage: lastPage ?? this.lastPage,
      recentColors: recentColors ?? this.recentColors,
    );
  }

  // Serialização para Map — converte DateTime para msEpoch e mantém
  // `recentColors` como lista de inteiros para persistência simples.
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'originalPath': originalPath,
        'annotatedPath': annotatedPath,
        'pageCount': pageCount,
        'lastOpened': lastOpened.millisecondsSinceEpoch,
        'lastPage': lastPage,
        'recentColors': recentColors,
      };

  // Desserialização a partir de Map. Trata valores opcionais e fornece
  // defaults seguros (por exemplo `lastPage` e `recentColors`).
  factory PdfDocumentModel.fromMap(Map<String, dynamic> map) => PdfDocumentModel(
        id: map['id'] as String,
        name: map['name'] as String,
        originalPath: map['originalPath'] as String,
        annotatedPath: map['annotatedPath'] as String?,
        pageCount: map['pageCount'] as int,
        lastOpened: DateTime.fromMillisecondsSinceEpoch(map['lastOpened'] as int),
        lastPage: (map['lastPage'] as int?) ?? 0,
        recentColors: (map['recentColors'] as List?)?.map((e) => (e as int)).toList() ?? const [],
      );

  // Helpers JSON convenientes para transporte em rede ou persistência serializada.
  String toJson() => json.encode(toMap());
  factory PdfDocumentModel.fromJson(String source) =>
      PdfDocumentModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
