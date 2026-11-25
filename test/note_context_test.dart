import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/theme.dart';
import 'package:onenote/ui/widgets.dart';

void main() {
  Future<(AppDb, AppState, Note)> seed(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_note_ctx_test');
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
    late Note first;
    await tester.runAsync(() async {
      final work = await db.createNotebook('工作');
      now += 1000;
      await db.createNote(work.id, title: 'buffer', content: 'buffer body');
      now += 1000;
      first = await db.createNote(work.id,
          title: '锅先生游记', content: 'old content');
      now += 1000;
      await db.saveNote(first.id, '锅先生游记', 'new content');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
    return (db, state, first);
  }

  testWidgets('note card opens history/trash menu on right-click and long-press',
      (WidgetTester tester) async {
    final (_, state, first) = await seed(tester);
    expect(state.openNoteId, first.id);

    final bufferCard = find.widgetWithText(NoteCard, 'buffer');
    await tester.tap(bufferCard, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('版本历史'), findsOneWidget);
    expect(find.text('移入回收站'), findsOneWidget);

    await tester.tapAt(const Offset(1200, 60));
    await tester.pumpAndSettle();
    expect(find.text('版本历史'), findsNothing);

    await tester.longPress(bufferCard);
    await tester.pumpAndSettle();
    expect(find.text('版本历史'), findsOneWidget);
    expect(find.text('移入回收站'), findsOneWidget);
  });

  testWidgets('history menu on an unopened note shows its versions',
      (WidgetTester tester) async {
    await seed(tester);

    await tester.tap(find.widgetWithText(NoteCard, 'buffer'),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('版本历史'));
    await tester.pumpAndSettle();

    expect(find.text('buffer body'), findsOneWidget);
    expect(find.text('恢复'), findsNothing);

    await tester.tapAt(const Offset(700, 40));
    await tester.pumpAndSettle();
    expect(find.text('buffer body'), findsNothing);
  });

  testWidgets('restoring a version from the list refreshes the open note',
      (WidgetTester tester) async {
    final (db, _, first) = await seed(tester);
    expect(
        find.descendant(
            of: find.byType(NoteView), matching: find.text('new content')),
        findsOneWidget);

    await tester.tap(find.widgetWithText(NoteCard, '锅先生游记'),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('版本历史'));
    await tester.pumpAndSettle();
    expect(find.text('old content'), findsOneWidget);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('恢复此版本'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();

    expect(find.text('恢复此版本'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(NoteView), matching: find.text('old content')),
        findsOneWidget);
    await tester.runAsync(() async {
      expect((await db.getNote(first.id)).content, 'old content');
    });
  });

  testWidgets('trash menu moves the note to trash after confirm',
      (WidgetTester tester) async {
    final (db, state, _) = await seed(tester);

    await tester.tap(find.widgetWithText(NoteCard, 'buffer'),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移入回收站'));
    await tester.pumpAndSettle();

    expect(find.text('「buffer」将保留 90 天，可随时恢复。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(NoteCard, 'buffer'), findsNothing);
    expect(state.notes.any((n) => n.title == 'buffer'), isFalse);
    await tester.runAsync(() async {
      expect((await db.listTrash()).length, 1);
    });
  });
}