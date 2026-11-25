import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/note_toc.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  testWidgets('paragraph elements survive a stylesheet-triggered reparse',
      (WidgetTester tester) async {
    const data = 'first paragraph\n\nsecond paragraph\n\n- [ ] task line';
    Widget frame(double listIndent) => MaterialApp(
          theme: buildInkTheme(Brightness.dark),
          home: Scaffold(
            body: MarkdownBody(
              data: data,
              selectable: true,
              styleSheet: MarkdownStyleSheet(listIndent: listIndent),
            ),
          ),
        );
    await tester.pumpWidget(frame(28));
    final before = tester.elementList(find.byType(SelectableText)).toList();
    expect(before.length, 3);
    await tester.pumpWidget(frame(30));
    final after = tester.elementList(find.byType(SelectableText)).toList();
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(identical(before[i], after[i]), isTrue);
    }
  });

  testWidgets('theme rebuild and idle refresh keep note paragraph elements',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_stable_para');
    addTearDown(() => dir.deleteSync(recursive: true));
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    late String noteId;
    await tester.runAsync(() async {
      final nb = await db.createNotebook('甲');
      now += 1000;
      final note = await db.createNote(nb.id,
          title: '标题', content: '# 章节一\n\nalpha one\n\n## 章节二\n\nalpha two');
      noteId = note.id;
    });
    Widget frame() => MaterialApp(
          theme: buildInkTheme(Brightness.dark),
          home: Scaffold(
            body: NoteView(
              state: state,
              noteId: noteId,
              showBack: false,
              onBack: () {},
            ),
          ),
        );
    await tester.pumpWidget(frame());
    await tester.pumpAndSettle();
    final before = tester.elementList(find.byType(SelectableText)).toList();
    expect(before, isNotEmpty);
    await tester.runAsync(() => state.refresh());
    await tester.pumpWidget(frame());
    await tester.pumpAndSettle();
    final after = tester.elementList(find.byType(SelectableText)).toList();
    expect(after.length, before.length);
    for (var i = 0; i < before.length; i++) {
      expect(identical(before[i], after[i]), isTrue);
    }
  });

  testWidgets('search nav can be dragged over the toc column',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_nav_toc');
    addTearDown(() => dir.deleteSync(recursive: true));
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    late String noteId;
    await tester.runAsync(() async {
      final nb = await db.createNotebook('甲');
      now += 1000;
      final note = await db.createNote(nb.id,
          title: '标题', content: '# 章节一\n\nalpha one\n\n## 章节二\n\nalpha two');
      noteId = note.id;
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: NoteView(
          state: state,
          noteId: noteId,
          showBack: false,
          onBack: () {},
          highlightQuery: 'alpha',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final nav = find.byKey(const ValueKey('matchNav'));
    expect(nav, findsOneWidget);
    final contentWidth = 1400 - noteTocWidth;
    final start = tester.getTopLeft(nav);
    expect(start.dx + tester.getSize(nav).width, lessThanOrEqualTo(contentWidth));
    await tester.dragFrom(tester.getCenter(nav), const Offset(2000, 0));
    await tester.pumpAndSettle();
    final moved = tester.getTopLeft(nav);
    expect(moved.dx, greaterThan(contentWidth));
    expect(moved.dx + tester.getSize(nav).width, lessThanOrEqualTo(1400));
  });
}