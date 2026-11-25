import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/theme.dart';
import 'package:onenote/ui/widgets.dart';

void main() {
  testWidgets('notebook row opens rename/delete menu on right-click and long-press',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_ctx_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      await db.createNotebook('工作');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('笔记本操作'), findsNothing);

    await tester.tap(find.widgetWithText(ScopeTile, '工作'),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('自定义背景色'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tapAt(const Offset(1200, 850));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsNothing);

    await tester.longPress(find.widgetWithText(ScopeTile, '工作'));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);

    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    expect(find.text('重命名笔记本'), findsOneWidget);
  });

  testWidgets('custom color menu applies palette choice to row and note card',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_color_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      final work = await db.createNotebook('工作');
      now += 1000;
      await db.createNote(work.id, title: 'first', content: 'alpha');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ScopeTile, '工作'),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义背景色'));
    await tester.pumpAndSettle();
    expect(find.text('笔记本预览'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == const Color(0xFF16A34A) &&
        w.constraints?.maxWidth == 32));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(state.notebookColor(state.notebooks.single.id), 0xFF16A34A);
    final cards = tester.widgetList<NoteCard>(find.byType(NoteCard));
    expect(cards.single.tintColor, const Color(0xFF16A34A));
    final dot = find.descendant(
      of: find.widgetWithText(ScopeTile, '工作'),
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == const Color(0xFF16A34A) &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle),
    );
    expect(dot, findsOneWidget);

    await tester.tap(find.widgetWithText(ScopeTile, '工作'));
    await tester.pumpAndSettle();
    final card = tester.widget<NoteCard>(find.byType(NoteCard));
    expect(card.tintColor, const Color(0xFF16A34A));
    expect(card.tinted, isFalse);
    final pane = find.byWidgetPredicate((w) =>
        w is ColoredBox &&
        w.color ==
            Color.alphaBlend(const Color(0xFF16A34A).withValues(alpha: 0.06),
                const Color(0xFF111113)));
    expect(pane, findsOneWidget);
  });

  testWidgets('bottom new-note button is icon-only with click cursor',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_ctx_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      final work = await db.createNotebook('工作');
      await db.createNote(work.id, title: 'first', content: 'alpha');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    final button = find.ancestor(
      of: find.byIcon(Icons.add),
      matching: find.byType(OutlinedButton),
    );
    expect(button, findsOneWidget);
    expect(
        find.descendant(of: button, matching: find.text('笔记')), findsNothing);
    final regions = tester.widgetList<MouseRegion>(
        find.descendant(of: button, matching: find.byType(MouseRegion)));
    expect(regions.any((r) => r.cursor == SystemMouseCursors.click), isTrue);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(state.notes.length, 2);
  });
}