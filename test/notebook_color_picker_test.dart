import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
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

  testWidgets('preset board holds the palette and every swatch is reachable',
      (tester) async {
    await openPicker(tester);
    expect(notebookPalette.length, greaterThan(8));
    for (final value in notebookPalette) {
      expect(swatchOf(value), findsOneWidget,
          reason: 'missing swatch ${value.toRadixString(16)}');
    }
    await tester.tap(swatchOf(0xFFFDFAE9));
    await tester.pumpAndSettle();
    expect(find.text('FDFAE9'), findsOneWidget);
  });

  testWidgets('dialog accents follow the selected color', (tester) async {
    for (final brightness in Brightness.values) {
      final completer = Completer<int?>();
      await tester.pumpWidget(MaterialApp(
        theme: buildInkTheme(brightness),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  completer.complete(
                      await pickNotebookColor(context, initial: 0xFF9333EA));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final t = inkOf(tester.element(find.text('自定义背景色')));

      Color fillOf(int value) =>
          readableOn(Color(value), t.surface, ratio: 3);

      for (final value in [0xFF018C89, 0xFFFDFAE9, 0xFF2A2B3D]) {
        await tester.tap(swatchOf(value));
        await tester.pumpAndSettle();
        final fill = fillOf(value);
        final sliderTheme =
            tester.widget<SliderTheme>(find.byType(SliderTheme)).data;
        expect(sliderTheme.activeTrackColor, fill);
        expect(sliderTheme.thumbColor, fill);
        expect(sliderTheme.valueIndicatorColor, fill);
        final confirm = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, '确定'));
        expect(confirm.style!.backgroundColor!.resolve({}), fill);
        final onFill = confirm.style!.foregroundColor!.resolve({})!;
        expect(contrastRatio(onFill, fill), greaterThanOrEqualTo(4.5),
            reason: 'brightness: $brightness, value: $value');
        final cancel = tester.widget<TextButton>(
            find.widgetWithText(TextButton, '取消'));
        final cancelInk = cancel.style!.foregroundColor!.resolve({})!;
        expect(contrastRatio(cancelInk, t.surface), greaterThanOrEqualTo(4.5));
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.cursorColor, readableOn(Color(value), t.surface));
        expect(field.decoration!.floatingLabelStyle!.color,
            readableOn(Color(value), t.surface));
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await completer.future, isNull);
    }
  });

  testWidgets('selected swatch check keeps contrast on light presets',
      (tester) async {
    await openPicker(tester);
    for (final value in [0xFFFDFAE9, 0xFFF8D6A1, 0xFF2A2B3D, 0xFFCA8A04]) {
      await tester.tap(swatchOf(value));
      await tester.pumpAndSettle();
      final check = tester.widget<Icon>(find.descendant(
          of: swatchOf(value), matching: find.byIcon(Icons.check)));
      expect(contrastRatio(check.color!, Color(value)),
          greaterThanOrEqualTo(4.5),
          reason: 'value: ${value.toRadixString(16)}');
    }
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