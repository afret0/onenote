import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/markdown_view.dart';
import 'package:onenote/ui/theme.dart';
import 'package:onenote/ui/widgets.dart';

bool _hasClickCursor(InlineSpan span) {
  if (span is TextSpan) {
    if (span.mouseCursor == SystemMouseCursors.click) {
      return true;
    }
    return (span.children ?? const <InlineSpan>[]).any(_hasClickCursor);
  }
  return false;
}

void main() {
  testWidgets('highlight records every match and keeps text selectable',
      (WidgetTester tester) async {
    final controller = MarkdownHighlightController();
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: MarkdownView(
          content: 'buffer one buffer two `buffer`',
          highlightQuery: 'buffer',
          highlightController: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.matches.length, 3);
    expect(find.byType(SelectableText), findsWidgets);
    final offsets = controller.matches.map((m) => m.offset).toList();
    expect(offsets, orderedEquals(offsets.toList()..sort()));
  });

  testWidgets('markdown link span uses click cursor',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: const Scaffold(body: MarkdownView(content: '[t](https://e.com)')),
    ));
    await tester.pumpAndSettle();
    final texts = tester.widgetList<SelectableText>(find.byType(SelectableText));
    expect(texts.any((w) => _hasClickCursor(w.textSpan!)), isTrue);
  });

  testWidgets('search results group by notebook in creation order',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_search_group');
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
    late String aId;
    late String bId;
    await tester.runAsync(() async {
      final a = await db.createNotebook('甲');
      aId = a.id;
      now += 1000;
      final b = await db.createNotebook('乙');
      bId = b.id;
      now += 1000;
      await db.createNote(a.id, title: 'a1', content: 'buffer x');
      now += 1000;
      await db.createNote(a.id, title: 'a2', content: 'buffer y');
      now += 1000;
      await db.createNote(b.id, title: 'b1', content: 'buffer z');
      now += 1000;
      await db.createNote(b.id, title: 'miss', content: 'nothing');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'buffer');
    await tester.pumpAndSettle();

    final aHeader = find.byKey(ValueKey('searchGroup:$aId'));
    final bHeader = find.byKey(ValueKey('searchGroup:$bId'));
    expect(aHeader, findsOneWidget);
    expect(bHeader, findsOneWidget);
    expect(find.descendant(of: aHeader, matching: find.text('2')),
        findsOneWidget);
    expect(find.descendant(of: bHeader, matching: find.text('1')),
        findsOneWidget);
    expect(tester.getTopLeft(aHeader).dy < tester.getTopLeft(bHeader).dy,
        isTrue);
    expect(find.widgetWithText(NoteCard, 'miss'), findsNothing);
  });

  testWidgets('empty search box has no chinese hint and centers the magnifier',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_search_box');
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
      final nb = await db.createNotebook('甲');
      now += 1000;
      await db.createNote(nb.id, title: 't', content: 'x');
      now += 1000;
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
    expect(find.text('搜索标题与正文'), findsNothing);
    final field = tester.getRect(find.byType(TextField).first);
    final icon = tester.getRect(find.byIcon(Icons.search));
    expect((icon.center.dx - field.center.dx).abs() < 1, isTrue);
    expect((icon.center.dy - field.center.dy).abs() < 1, isTrue);
  });

  testWidgets('opened search hit shows match nav and jumps between matches',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_match_nav');
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
      final nb = await db.createNotebook('甲');
      now += 1000;
      await db.createNote(nb.id,
          title: 't', content: 'buffer one buffer two buffer three');
      now += 1000;
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'buffer');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NoteCard).first);
    await tester.pumpAndSettle();

    final nav = find.byKey(const ValueKey('matchNav'));
    expect(nav, findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('1/3')), findsOneWidget);
    await tester.tap(
        find.descendant(of: nav, matching: find.byIcon(Icons.keyboard_arrow_down)));
    await tester.pumpAndSettle();
    expect(find.descendant(of: nav, matching: find.text('2/3')), findsOneWidget);
    await tester.tap(
        find.descendant(of: nav, matching: find.byIcon(Icons.keyboard_arrow_up)));
    await tester.pumpAndSettle();
    expect(find.descendant(of: nav, matching: find.text('1/3')), findsOneWidget);
  });
}