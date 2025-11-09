import 'dart:convert';

class PdfDocumentModel {
  final String id;
  final String name;
  final String originalPath;
  final String? annotatedPath;
  final int pageCount;
  final DateTime lastOpened;
  final int lastPage;
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

  String toJson() => json.encode(toMap());
  factory PdfDocumentModel.fromJson(String source) =>
      PdfDocumentModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
