import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/richtext_note_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  Future<(AppDb, AppState, Note, Note)> seed(WidgetTester tester) async {
    NativeTransport.debugOverride = NativeTransport.testing()
      ..invokeHandler = (call) async {
        if (call.method == 'initialize') {
          return {'view': (call.arguments as Map)['view']};
        }
        return null;
      };
    addTearDown(() => NativeTransport.debugOverride = null);
    final dir = Directory.systemTemp.createTempSync('onenote_richtext_view_test');
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
    late Note markdown;
    late Note richtext;
    await tester.runAsync(() async {
      final work = await db.createNotebook('工作');
      now += 1000;
      markdown = await db.createNote(work.id, title: 'md', content: '# H\n\ntext\n');
      now += 1000;
      richtext = await db.createNote(work.id,
          title: 'rt', content: '# H\n\ntext\n', format: AppDb.noteFormatRichtext);
      await state.init();
    });
    return (db, state, markdown, richtext);
  }

  Future<void> pumpNote(WidgetTester tester, AppState state, String id) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: NoteView(
          state: state,
          noteId: id,
          showBack: false,
          onBack: () {},
        ),
      ),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('富文本笔记直接进入所见即所得编辑', (WidgetTester tester) async {
    final (_, state, _, richtext) = await seed(tester);
    await pumpNote(tester, state, richtext.id);
    expect(find.byType(RichTextNoteView), findsOneWidget);
    expect(find.byType(AppFlowyEditor), findsOneWidget);
  });

  testWidgets('Markdown 笔记仍走渲染路径不受富文本影响', (WidgetTester tester) async {
    final (_, state, markdown, _) = await seed(tester);
    await pumpNote(tester, state, markdown.id);
    expect(find.byType(RichTextNoteView), findsNothing);
    expect(find.byType(AppFlowyEditor), findsNothing);
  });
}