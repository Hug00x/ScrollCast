import 'dart:convert';

class NotebookModel {
  final String id;
  final String name;
  final String? folder;       // pasta (null = “raiz”)
  final int pageCount;
  final DateTime lastOpened;

  const NotebookModel({
    required this.id,
    required this.name,
    required this.pageCount,
    required this.lastOpened,
    this.folder,
  });

  NotebookModel copyWith({
    String? id,
    String? name,
    String? folder,
    int? pageCount,
    DateTime? lastOpened,
  }) {
    return NotebookModel(
      id: id ?? this.id,
      name: name ?? this.name,
      folder: folder ?? this.folder,
      pageCount: pageCount ?? this.pageCount,
      lastOpened: lastOpened ?? this.lastOpened,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'folder': folder,
    'pageCount': pageCount,
    'lastOpened': lastOpened.millisecondsSinceEpoch,
  };

  factory NotebookModel.fromMap(Map<String, dynamic> map) => NotebookModel(
    id: map['id'] as String,
    name: map['name'] as String,
    folder: map['folder'] as String?,
    pageCount: map['pageCount'] as int,
    lastOpened: DateTime.fromMillisecondsSinceEpoch(map['lastOpened'] as int),
  );

  String toJson() => json.encode(toMap());
  factory NotebookModel.fromJson(String source) =>
      NotebookModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
