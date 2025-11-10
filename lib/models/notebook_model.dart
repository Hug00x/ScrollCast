import 'dart:convert';

/*
  NotebookModel

  Propósito geral:
  - Representa um caderno (notebook) dentro da aplicação.
  - Guarda metadados essenciais: id, nome, pasta (opcional), número de
  páginas, última abertura, última página visualizada e histórico de cores
  recentes usado nas anotações.
  - Fornece métodos para cópia imutável (`copyWith`) e para serialização
  / desserialização (toMap/fromMap/toJson/fromJson).

  Organizzação do ficheiro:
  - `folder` é opcional e pode ser usado para organizar cadernos em pastas.
  - `recentColors` segue o mesmo formato do `PdfDocumentModel` para uniformidade na UI.
*/

class NotebookModel {
  // Identificador único do caderno.
  final String id;

  // Nome exibido ao utilizador.
  final String name;

  // Pasta (opcional) onde o caderno está organizado; pode ser null.
  final String? folder;

  // Contagem de páginas do caderno.
  final int pageCount;

  // Data/hora da última abertura do caderno.
  final DateTime lastOpened;

  // Última página visualizada dentro do caderno.
  final int lastPage;

  // Histórico de cores recentes para a barra de ferramentas.
  final List<int> recentColors;

  const NotebookModel({
    required this.id,
    required this.name,
    required this.pageCount,
    required this.lastOpened,
    this.folder,
    this.lastPage = 0,
    this.recentColors = const [],
  });

  // copyWith: permite criar uma nova instância com alguns campos modificados, preservando os restantes.
  NotebookModel copyWith({
    String? id,
    String? name,
    String? folder,
    int? pageCount,
    DateTime? lastOpened,
    int? lastPage,
    List<int>? recentColors,
  }) {
    return NotebookModel(
      id: id ?? this.id,
      name: name ?? this.name,
      folder: folder ?? this.folder,
      pageCount: pageCount ?? this.pageCount,
      lastOpened: lastOpened ?? this.lastOpened,
      lastPage: lastPage ?? this.lastPage,
      recentColors: recentColors ?? this.recentColors,
    );
  }

  // Serialização para Map: útil para persistência em base de dados local ou para backup remoto.
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'folder': folder,
        'pageCount': pageCount,
        'lastOpened': lastOpened.millisecondsSinceEpoch,
        'lastPage': lastPage,
        'recentColors': recentColors,
      };

  // Desserialização a partir de Map: trata valores opcionais e defaults.
  factory NotebookModel.fromMap(Map<String, dynamic> map) => NotebookModel(
        id: map['id'] as String,
        name: map['name'] as String,
        folder: map['folder'] as String?,
        pageCount: map['pageCount'] as int,
        lastOpened: DateTime.fromMillisecondsSinceEpoch(map['lastOpened'] as int),
        lastPage: (map['lastPage'] as int?) ?? 0,
        recentColors: (map['recentColors'] as List?)?.map((e) => (e as int)).toList() ?? const [],
      );

  // Helpers JSON para transporte ou persistência simples.
  String toJson() => json.encode(toMap());
  factory NotebookModel.fromJson(String source) =>
      NotebookModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
