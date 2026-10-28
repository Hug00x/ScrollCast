import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollcast/main.dart';
import 'package:scrollcast/models/annotations.dart';
import 'package:scrollcast/models/notebook_model.dart';
import 'package:scrollcast/services/database_service.dart';
import 'package:scrollcast/ui/screens/notebook_viewer_screen.dart';
import 'package:scrollcast/ui/widgets/drawing_canvas.dart';
import 'package:scrollcast/ui/widgets/notebook_paper.dart';

class _NotebookDatabase implements DatabaseService {
  final pages = <int, PageAnnotations>{};
  Completer<PageAnnotations?>? pendingPage;
  NotebookModel? notebook;

  @override
  Future<List<PageAnnotations>> getAllAnnotations(String pdfId) async =>
      pages.values.toList();

  @override
  Future<PageAnnotations?> getPageAnnotations(String pdfId, int pageIndex) =>
      pendingPage?.future ?? Future.value(pages[pageIndex]);

  @override
  Future<void> savePageAnnotations(PageAnnotations page) async {
    pages[page.pageIndex] = page;
  }

  @override
  Future<NotebookModel?> getNotebookById(String id) async => notebook;

  @override
  Future<void> upsertNotebook(NotebookModel nb) async {
    notebook = nb;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });

  Future<GlobalKey<NavigatorState>> mountNotebookApp(
    WidgetTester tester,
    _NotebookDatabase db,
  ) async {
    ServiceLocator.instance.db = db;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotebookViewerScreen(
                        args: NotebookViewerArgs(
                          notebookId: 'test',
                          name: 'Caderno',
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir caderno'),
                ),
              ),
            );
          },
        ),
      ),
    );
    return navigator;
  }

  for (final style in NotebookPaperStyle.values) {
    testWidgets('$style remains on new pages and after reopening', (
      tester,
    ) async {
      final db = _NotebookDatabase()
        ..notebook = NotebookModel.fromJson(
          NotebookModel(
            id: 'test',
            name: 'Caderno',
            pageCount: 1,
            lastOpened: DateTime(2026, 10, 28),
            paperStyle: style,
          ).toJson(),
        );
      final navigator = await mountNotebookApp(tester, db);
      await tester.tap(find.text('Abrir caderno'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NotebookPaper>(find.byType(NotebookPaper)).style,
        style,
      );
      await tester.tap(find.byTooltip('Adicionar página'));
      await tester.pumpAndSettle();
      expect(find.text('Caderno (2/2)'), findsOneWidget);
      expect(
        tester.widget<NotebookPaper>(find.byType(NotebookPaper)).style,
        style,
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir caderno'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NotebookPaper>(find.byType(NotebookPaper)).style,
        style,
      );
      expect(db.notebook!.paperStyle, style);
    });
  }

  testWidgets('same stylus can write and navigate after reopening a notebook', (
    tester,
  ) async {
    final db = _NotebookDatabase();
    await mountNotebookApp(tester, db);
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(
      location: tester.getCenter(find.text('Abrir caderno')),
    );

    for (var visit = 0; visit < 3; visit++) {
      await pen.down(tester.getCenter(find.text('Abrir caderno')));
      await pen.up();
      await tester.pumpAndSettle();

      // The first pen contact must still reach the canvas in hand mode.
      if (visit == 1) {
        await tester.tap(find.byIcon(Icons.brush));
        await tester.pump();
      }
      final point = tester.getCenter(find.byType(DrawingCanvas));
      await pen.down(point);
      await pen.moveBy(const Offset(30, 20));
      await pen.up();
      await tester.pumpAndSettle();
      expect(db.pages[0]!.strokes, hasLength(visit + 1));

      // Buttons must also remain usable with the same pen device.
      await pen.down(tester.getCenter(find.byType(BackButton)));
      await pen.up();
      await tester.pumpAndSettle();
      expect(find.text('Abrir caderno'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await pen.removePointer();
  });

  testWidgets(
    'cancelled pen contact restores panning and accepts another stroke',
    (tester) async {
      final db = _NotebookDatabase();
      await mountNotebookApp(tester, db);
      await tester.tap(find.text('Abrir caderno'));
      await tester.pumpAndSettle();
      final point = tester.getCenter(find.byType(DrawingCanvas));
      final pen = await tester.startGesture(
        point,
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .panEnabled,
        isFalse,
      );
      await pen.cancel();
      await tester.pump();
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .panEnabled,
        isTrue,
      );
      await pen.down(point);
      await pen.moveBy(const Offset(30, 20));
      await pen.up();
      await tester.pumpAndSettle();
      expect(db.pages[0]!.strokes, hasLength(1));
    },
  );

  testWidgets('lifting the pen after leaving does not call the old canvas', (
    tester,
  ) async {
    final db = _NotebookDatabase();
    final navigator = await mountNotebookApp(tester, db);
    await tester.tap(find.text('Abrir caderno'));
    await tester.pumpAndSettle();
    final pen = await tester.startGesture(
      tester.getCenter(find.byType(DrawingCanvas)),
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveBy(const Offset(30, 20));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await pen.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Abrir caderno'), findsOneWidget);
    expect(db.pages, isEmpty);
  });

  testWidgets(
    'leaving while annotations load does not update a disposed screen',
    (tester) async {
      final db = _NotebookDatabase()
        ..pendingPage = Completer<PageAnnotations?>();
      final navigator = await mountNotebookApp(tester, db);
      await tester.tap(find.text('Abrir caderno'));
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      db.pendingPage!.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Abrir caderno'), findsOneWidget);
    },
  );
}
