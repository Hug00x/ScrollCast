import 'dart:convert';

class NotebookModel {
  final String id;
  final String name;
  final String? folder;       // pasta (null = “raiz”)
  final int pageCount;
  final DateTime lastOpened;
  final int lastPage;
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

  NotebookModel copyWith({
    String? id,
    String? name,
    String? folder,
    int? pageCount,
    DateTime? lastOpened,
    int? lastPage,
    List<int>? lastColors,
  }) {
    return NotebookModel(
      id: id ?? this.id,
      name: name ?? this.name,
      folder: folder ?? this.folder,
      pageCount: pageCount ?? this.pageCount,
      lastOpened: lastOpened ?? this.lastOpened,
      lastPage: lastPage ?? this.lastPage,
      recentColors: lastColors ?? this.recentColors,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'folder': folder,
    'pageCount': pageCount,
    'lastOpened': lastOpened.millisecondsSinceEpoch,
    'lastPage': lastPage,
    'recentColors': recentColors,
  };

  factory NotebookModel.fromMap(Map<String, dynamic> map) => NotebookModel(
    id: map['id'] as String,
    name: map['name'] as String,
    folder: map['folder'] as String?,
    pageCount: map['pageCount'] as int,
    lastOpened: DateTime.fromMillisecondsSinceEpoch(map['lastOpened'] as int),
    lastPage: (map['lastPage'] as int?) ?? 0,
    recentColors: (map['recentColors'] as List?)?.map((e) => (e as int)).toList() ?? const [],
  );

  String toJson() => json.encode(toMap());
  factory NotebookModel.fromJson(String source) =>
      NotebookModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
