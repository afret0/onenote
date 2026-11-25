import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/main.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/theme.dart';
import 'package:onenote/ui/widgets.dart';

Finder noteContent(String text) =>
    find.descendant(of: find.byType(NoteView), matching: find.text(text));

void main() {
  testWidgets('empty state shows brand and create entry',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = AppDb(NativeDatabase.memory());
    await tester.pumpWidget(OneNoteApp(db: db));
    await tester.pumpAndSettle();

    expect(find.text('onenote'), findsOneWidget);
    expect(find.text('还没有笔记，写下第一条吧'), findsOneWidget);
    expect(find.text('全部'), findsWidgets);
    expect(find.text('回收站'), findsOneWidget);
  });

  testWidgets('wide layout shows three panes and notebook restores memory',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_widget_test');
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
    late Note second;
    await tester.runAsync(() async {
      final work = await db.createNotebook('工作');
      final first = await db.createNote(work.id,
          title: 'first', content: 'alpha content');
      now += 1000;
      await db.saveNote(first.id, 'first', 'alpha content v2');
      now += 1000;
      second = await db.createNote(work.id,
          title: 'second', content: 'second body');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    expect(noteContent(second.content), findsOneWidget);
    expect(find.widgetWithText(NoteCard, 'first'), findsOneWidget);

    await tester.tap(find.widgetWithText(ScopeTile, '工作'));
    await tester.pumpAndSettle();
    expect(noteContent(second.content), findsOneWidget);

    await tester.tap(find.widgetWithText(NoteCard, 'first'));
    await tester.pumpAndSettle();
    expect(noteContent('alpha content v2'), findsOneWidget);

    await tester.tap(find.widgetWithText(ScopeTile, '全部'));
    await tester.pumpAndSettle();
    expect(noteContent(second.content), findsOneWidget);

    await tester.tap(find.widgetWithText(ScopeTile, '工作'));
    await tester.pumpAndSettle();
    expect(noteContent('alpha content v2'), findsOneWidget);
    expect(find.widgetWithText(NoteCard, 'second'), findsOneWidget);
  });

  testWidgets('note scroll position is kept when switching notes',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_widget_test');
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
    late Note long;
    await tester.runAsync(() async {
      final work = await db.createNotebook('work');
      await db.createNote(work.id, title: 'para-000', content: 'alpha content');
      now += 1000;
      long = await db.createNote(work.id,
          title: 'long note',
          content: List.generate(200, (i) => '段落 $i 的内容行。').join('\n\n'));
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    final scrollFinder = find
        .descendant(
          of: find.byKey(PageStorageKey<String>('noteScroll:${long.id}')),
          matching: find.byType(Scrollable),
        )
        .first;
    ScrollableState scrollState() =>
        tester.state<ScrollableState>(scrollFinder);
    expect(scrollState().position.pixels, 0);
    await tester.drag(scrollFinder, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(scrollState().position.pixels, greaterThan(0));
    final scrolled = scrollState().position.pixels;

    await tester.tap(find.widgetWithText(NoteCard, 'para-000'));
    await tester.pumpAndSettle();
    expect(noteContent('alpha content'), findsOneWidget);

    await tester.tap(find.widgetWithText(NoteCard, 'long note'));
    await tester.pumpAndSettle();
    expect(scrollState().position.pixels, scrolled);
  });

  testWidgets('narrow layout never auto-opens and keeps drawer list flow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_widget_test');
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
      await db.createNote(work.id, title: 'first', content: 'alpha content');
      now += 1000;
      await db.createNote(work.id, title: 'second', content: 'second body');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NoteView), findsNothing);
    expect(find.widgetWithText(NoteCard, 'second'), findsOneWidget);

    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ScopeTile, '工作'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteView), findsNothing);
    expect(state.openNoteId, isNull);
    expect(find.widgetWithText(NoteCard, 'second'), findsOneWidget);

    await tester.tap(find.widgetWithText(NoteCard, 'first'));
    await tester.pumpAndSettle();
    expect(noteContent('alpha content'), findsOneWidget);
  });

  testWidgets('dragging pane dividers resizes columns and persists widths',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_widget_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    final db = AppDb(NativeDatabase.memory());
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    await tester.drag(
        find.byKey(const Key('paneDivider:sidebar')), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(state.sidebarWidth, greaterThan(AppState.sidebarDefaultWidth));
    expect(state.sidebarWidth,
        lessThanOrEqualTo(AppState.sidebarDefaultWidth + 60));

    await tester.drag(
        find.byKey(const Key('paneDivider:list')), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(state.listWidth, AppState.listMinWidth);

    await tester.runAsync(() async {
      expect(await db.getSetting(AppDb.paneWidthSidebarKey),
          state.sidebarWidth.round().toString());
      expect(await db.getSetting(AppDb.paneWidthListKey),
          AppState.listMinWidth.round().toString());
    });
  });

  testWidgets('shrinking window keeps content minimum then restores widths',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_widget_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    final db = AppDb(NativeDatabase.memory());
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      await state.init();
    });
    state.updateSidebarWidth(400);
    state.updateListWidth(480);
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    final sidebarDivider = find.byKey(const Key('paneDivider:sidebar'));
    final listDivider = find.byKey(const Key('paneDivider:list'));
    expect(tester.getTopLeft(sidebarDivider).dx, 400);
    expect(tester.getTopLeft(listDivider).dx - 400 - 8, 480);

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();
    final sidebarWidth = tester.getTopLeft(sidebarDivider).dx;
    final listWidth = tester.getTopLeft(listDivider).dx - sidebarWidth - 8;
    expect(sidebarWidth, 284);
    expect(listWidth, AppState.listMinWidth);
    expect(state.sidebarWidth, 400);
    expect(state.listWidth, 480);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sidebarDivider).dx, 400);
    expect(tester.getTopLeft(listDivider).dx - 400 - 8, 480);
  });
}