// lib/models/folder_model.dart
import 'dart:convert';

class FolderModel {
  final String id;
  final String name;
  final DateTime createdAt;

  const FolderModel({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  FolderModel copyWith({String? id, String? name, DateTime? createdAt}) {
    return FolderModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory FolderModel.fromMap(Map<String, dynamic> map) => FolderModel(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      );

  String toJson() => json.encode(toMap());
  factory FolderModel.fromJson(String source) =>
      FolderModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
