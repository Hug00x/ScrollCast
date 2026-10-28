import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollcast/models/notebook_model.dart';
import 'package:scrollcast/ui/widgets/new_notebook_dialog.dart';
import 'package:scrollcast/ui/widgets/notebook_paper.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester,
    ValueChanged<NotebookDraft?> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await showDialog<NotebookDraft>(
                    context: context,
                    builder: (_) =>
                        const NewNotebookDialog(initialFolder: 'Aulas'),
                  );
                  onResult(result);
                },
                child: const Text('Novo'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Novo'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'creation previews all paper types and returns the selected one',
    (tester) async {
      NotebookDraft? draft;
      await openDialog(tester, (value) => draft = value);
      expect(
        tester
            .widgetList<NotebookPaper>(find.byType(NotebookPaper))
            .map((paper) => paper.style),
        NotebookPaperStyle.values,
      );
      await tester.enterText(find.byType(TextField).first, '  Matemática  ');
      await tester.tap(find.text('Com linhas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quadriculado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();
      expect(draft!.name, 'Matemática');
      expect(draft!.folder, 'Aulas');
      expect(draft!.paperStyle, NotebookPaperStyle.grid);
    },
  );

  testWidgets('cancel discards the selected paper', (tester) async {
    var completed = false;
    NotebookDraft? draft;
    await openDialog(tester, (value) {
      completed = true;
      draft = value;
    });
    await tester.tap(find.text('Com linhas'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(draft, isNull);
  });

  testWidgets('small screen with keyboard can scroll to the paper choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    NotebookDraft? draft;
    await openDialog(tester, (value) => draft = value);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Com linhas'));
    await tester.tap(find.text('Com linhas'));
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();
    expect(draft!.paperStyle, NotebookPaperStyle.lined);
    expect(draft!.name, 'Caderno');
    expect(tester.takeException(), isNull);
  });
}
