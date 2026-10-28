import 'package:flutter_test/flutter_test.dart';
import 'package:scrollcast/models/notebook_model.dart';

void main() {
  final notebook = NotebookModel(
    id: 'test',
    name: 'Apontamentos',
    pageCount: 3,
    lastOpened: DateTime(2026, 10, 28),
  );

  test('legacy and unknown paper styles open as plain paper', () {
    final legacy = notebook.toMap()..remove('paperStyle');
    expect(NotebookModel.fromMap(legacy).paperStyle, NotebookPaperStyle.plain);
    legacy['paperStyle'] = 'unknown';
    expect(NotebookModel.fromMap(legacy).paperStyle, NotebookPaperStyle.plain);
  });

  test('paper choice survives storage and later metadata updates', () {
    for (final style in NotebookPaperStyle.values) {
      final saved = NotebookModel.fromJson(
        notebook.copyWith(paperStyle: style).toJson(),
      );
      expect(saved.paperStyle, style);
      final updated = NotebookModel.fromJson(
        saved.copyWith(lastPage: 2, recentColors: [0xFF000000]).toJson(),
      );
      expect(updated.paperStyle, style);
      expect(updated.lastPage, 2);
    }
  });
}
