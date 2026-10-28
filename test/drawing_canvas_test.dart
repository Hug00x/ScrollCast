import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollcast/models/annotations.dart';
import 'package:scrollcast/ui/widgets/drawing_canvas.dart';

Future<void> mountCanvas(
  WidgetTester tester, {
  required List<Stroke> strokes,
  bool stylusOnly = false,
  bool touchDrawingEnabled = true,
  ValueChanged<bool>? onStylusContact,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox.expand(
        child: DrawingCanvas(
          strokes: strokes,
          mode: StrokeMode.pen,
          strokeWidth: 4,
          strokeColor: 0xFF000000,
          stylusOnly: stylusOnly,
          touchDrawingEnabled: touchDrawingEnabled,
          onStylusContact: onStylusContact,
          onStrokeEnd: (stroke) async => strokes.add(stroke),
        ),
      ),
    ),
  );
}

void main() {
  for (final kind in [
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  ]) {
    testWidgets(
      '$kind cancellation releases contact and accepts the next stroke',
      (tester) async {
        final strokes = <Stroke>[];
        final contacts = <bool>[];
        await mountCanvas(
          tester,
          strokes: strokes,
          onStylusContact: contacts.add,
        );
        final pen = await tester.startGesture(
          const Offset(100, 100),
          kind: kind,
        );
        await pen.moveBy(const Offset(20, 20));
        await pen.cancel();
        await tester.pump();
        expect(contacts, [true, false]);
        expect(strokes, isEmpty);
        await pen.down(const Offset(200, 200));
        await pen.moveBy(const Offset(20, 20));
        await pen.up();
        await tester.pump();
        expect(contacts, [true, false, true, false]);
        expect(strokes.single.points.first, const Offset(200, 200));
      },
    );
  }

  testWidgets('hand mode ignores fingers and still accepts the pen', (
    tester,
  ) async {
    final strokes = <Stroke>[];
    await mountCanvas(tester, strokes: strokes, touchDrawingEnabled: false);
    final finger = await tester.startGesture(const Offset(50, 50));
    await finger.moveBy(const Offset(20, 20));
    await finger.up();
    expect(strokes, isEmpty);
    final pen = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveBy(const Offset(30, 30));
    await pen.up();
    expect(strokes, hasLength(1));
  });

  for (final cancelPalm in [false, true]) {
    testWidgets(
      'palm ${cancelPalm ? 'cancel' : 'up'} does not interrupt the pen',
      (tester) async {
        final strokes = <Stroke>[];
        await mountCanvas(tester, strokes: strokes, stylusOnly: true);
        final pen = await tester.startGesture(
          const Offset(100, 100),
          kind: PointerDeviceKind.stylus,
          pointer: 1,
        );
        await pen.moveBy(const Offset(20, 20));
        final palm = await tester.startGesture(
          const Offset(300, 300),
          pointer: 2,
        );
        await palm.moveBy(const Offset(10, 10));
        if (cancelPalm) {
          await palm.cancel();
        } else {
          await palm.up();
        }
        await pen.moveBy(const Offset(20, 20));
        await pen.up();
        expect(strokes.single.points, [
          const Offset(100, 100),
          const Offset(120, 120),
          const Offset(140, 140),
        ]);
      },
    );
  }

  testWidgets('pen takes over from fingers already touching the canvas', (
    tester,
  ) async {
    final strokes = <Stroke>[];
    await mountCanvas(tester, strokes: strokes);
    final finger = await tester.startGesture(
      const Offset(300, 300),
      pointer: 1,
    );
    final secondFinger = await tester.startGesture(
      const Offset(350, 350),
      pointer: 2,
    );
    final pen = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.stylus,
      pointer: 3,
    );
    await pen.moveBy(const Offset(20, 20));
    await finger.cancel();
    await secondFinger.up();
    await pen.moveBy(const Offset(20, 20));
    await pen.up();
    expect(strokes.single.points, [
      const Offset(100, 100),
      const Offset(120, 120),
      const Offset(140, 140),
    ]);
  });

  testWidgets('pen preview repaints while the stroke is still in progress', (
    tester,
  ) async {
    await mountCanvas(tester, strokes: []);
    final pen = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    final paint = find.descendant(
      of: find.byType(DrawingCanvas),
      matching: find.byType(CustomPaint),
    );
    final before = tester.widget<CustomPaint>(paint).painter!;
    await pen.moveBy(const Offset(20, 20));
    await tester.pump();
    final after = tester.widget<CustomPaint>(paint).painter!;
    expect(after.shouldRepaint(before), isTrue);
    await pen.up();
  });
}
