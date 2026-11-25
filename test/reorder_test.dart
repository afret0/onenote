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
  Future<(AppDb, AppState)> seed(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_reorder_test');
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
      await db.createNotebook('生活');
      now += 1000;
      await db.createNote(work.id, title: 'buffer', content: 'buffer body');
      now += 1000;
      await db.createNote(work.id, title: '游记', content: '游记 body');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
    return (db, state);
  }

  bool menuEnabled(WidgetTester tester, String label) =>
      tester
          .widget<PopupMenuItem<String>>(
              find.widgetWithText(PopupMenuItem<String>, label))
          .enabled;

  testWidgets('notebook right-click move down swaps sidebar order',
      (WidgetTester tester) async {
    final (_, state) = await seed(tester);
    expect(state.notebooks.map((n) => n.name), ['工作', '生活']);

    await tester.tap(find.widgetWithText(ScopeTile, '工作'),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(menuEnabled(tester, '上移'), isFalse);
    expect(menuEnabled(tester, '下移'), isTrue);
    await tester.tap(find.text('下移'));
    await tester.pumpAndSettle();
    expect(state.notebooks.map((n) => n.name), ['生活', '工作']);

    await tester.longPress(find.widgetWithText(ScopeTile, '工作'));
    await tester.pumpAndSettle();
    expect(menuEnabled(tester, '上移'), isTrue);
    expect(menuEnabled(tester, '下移'), isFalse);
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();
    expect(state.notebooks.map((n) => n.name), ['工作', '生活']);
  });

  testWidgets('note card move up in notebook scope reorders the list',
      (WidgetTester tester) async {
    final (_, state) = await seed(tester);
    await tester.tap(find.widgetWithText(ScopeTile, '工作'));
    await tester.pumpAndSettle();
    expect(state.notes.map((n) => n.title), ['游记', 'buffer']);

    await tester.tap(find.widgetWithText(NoteCard, 'buffer'),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(menuEnabled(tester, '上移'), isTrue);
    expect(menuEnabled(tester, '下移'), isFalse);
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();
    expect(state.notes.map((n) => n.title), ['buffer', '游记']);
    expect(
        tester
            .getTopLeft(find.widgetWithText(NoteCard, 'buffer'))
            .dy
            .compareTo(
                tester.getTopLeft(find.widgetWithText(NoteCard, '游记')).dy),
        lessThan(0));
  });

  testWidgets('move items are disabled in all-notes scope and search results',
      (WidgetTester tester) async {
    final (_, state) = await seed(tester);
    expect(state.scope.kind, NoteScopeKind.all);

    await tester.tap(find.widgetWithText(NoteCard, 'buffer'),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(menuEnabled(tester, '上移'), isFalse);
    expect(menuEnabled(tester, '下移'), isFalse);
    await tester.tapAt(const Offset(1200, 60));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'body');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NoteCard, 'buffer').last,
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(menuEnabled(tester, '上移'), isFalse);
    expect(menuEnabled(tester, '下移'), isFalse);
  });
}