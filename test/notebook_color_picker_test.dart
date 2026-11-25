import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/ui/notebook_color_picker.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  Future<Future<int?>> openPicker(WidgetTester tester,
      {int initial = 0xFF9333EA}) async {
    final completer = Completer<int?>();
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                completer
                    .complete(await pickNotebookColor(context, initial: initial));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return completer.future;
  }

  Finder swatchOf(int color) => find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).color == Color(color) &&
      w.constraints?.maxWidth == 32);

  testWidgets('palette swatch selection returns the chosen color',
      (tester) async {
    final result = await openPicker(tester);
    expect(find.text('自定义背景色'), findsOneWidget);
    await tester.tap(swatchOf(0xFF16A34A));
    await tester.pumpAndSettle();
    expect(find.text('16A34A'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(await result, 0xFF16A34A);
  });

  testWidgets('hex input drives color and invalid hex blocks confirm',
      (tester) async {
    final result = await openPicker(tester);
    await tester.enterText(find.byType(TextField), '00ff00');
    await tester.pumpAndSettle();
    expect(find.text('6 位十六进制颜色'), findsNothing);
    var confirm = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(confirm.onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), 'zz');
    await tester.pumpAndSettle();
    expect(find.text('6 位十六进制颜色'), findsOneWidget);
    confirm = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(confirm.onPressed, isNull);

    await tester.enterText(find.byType(TextField), '#2563EB');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(await result, 0xFF2563EB);
  });

  testWidgets('sliders rewrite hex and cancel returns null', (tester) async {
    final result = await openPicker(tester);
    final hueSlider = find.byType(Slider).first;
    await tester.tap(hueSlider);
    await tester.pumpAndSettle();
    final hexField = tester.widget<TextField>(find.byType(TextField));
    expect(hexField.controller!.text, isNot('9333EA'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('自定义背景色'), findsNothing);
    expect(await result, isNull);
  });

  testWidgets('neutral surfaces keep 4.5:1 text contrast in both themes',
      (tester) async {
    for (final brightness in Brightness.values) {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        theme: buildInkTheme(brightness),
        home: Builder(builder: (context) {
          captured = context;
          return const SizedBox();
        }),
      ));
      final t = inkOf(captured);
      for (final background in [t.paper, t.surface, t.surfaceAlt]) {
        final bg = background.computeLuminance();
        for (final text in [t.ink, t.inkMuted]) {
          final fg = text.computeLuminance();
          final ratio = (fg > bg ? fg + 0.05 : bg + 0.05) /
              (fg > bg ? bg + 0.05 : fg + 0.05);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason:
                  'brightness: $brightness, background: $background, text: $text');
        }
      }
    }
  });
}