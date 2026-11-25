import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/main.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/sync/sync_engine.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/markdown_view.dart';
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

    await tester.tap(find.byIcon(Icons.menu));
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

  testWidgets('narrow restart restores last note by default',
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
    await tester.tap(find.widgetWithText(NoteCard, 'first'));
    await tester.pumpAndSettle();
    expect(noteContent('alpha content'), findsOneWidget);

    final restarted = AppState(db);
    addTearDown(restarted.dispose);
    await tester.runAsync(() async {
      await restarted.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: restarted),
    ));
    await tester.pumpAndSettle();
    expect(noteContent('alpha content'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(NoteView), findsNothing);
    expect(find.widgetWithText(NoteCard, 'second'), findsOneWidget);
  });

  testWidgets('narrow restart with list setting stays on list',
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
      await state.setNarrowStartup(AppState.narrowStartupList);
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NoteCard, 'first'));
    await tester.pumpAndSettle();
    expect(noteContent('alpha content'), findsOneWidget);

    final restarted = AppState(db);
    addTearDown(restarted.dispose);
    await tester.runAsync(() async {
      await restarted.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: restarted),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(NoteView), findsNothing);
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

  testWidgets('task list renders checkboxes and taps report post-order ordinals',
      (WidgetTester tester) async {
    final ordinals = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: MarkdownView(
          content: '- [ ] parent\n  - [x] child\n\n- [ ] second',
          onToggleTask: ordinals.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('•'), findsNothing);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNWidgets(2));

    final iconRect =
        tester.getRect(find.byIcon(Icons.check_box_outline_blank).at(0));
    final textRect = tester.getRect(find.text('parent'));
    expect((iconRect.center.dy - textRect.center.dy).abs(), lessThan(1.5));
    final region = tester.widget<MouseRegion>(find
        .ancestor(
            of: find.byIcon(Icons.check_box_outline_blank).at(0),
            matching: find.byType(MouseRegion))
        .first);
    expect(region.cursor, SystemMouseCursors.click);

    await tester.tap(find.byIcon(Icons.check_box_outline_blank).at(0));
    await tester.tap(find.byIcon(Icons.check_box_outline_blank).at(1));
    await tester.tap(find.byIcon(Icons.check_box));
    expect(ordinals, [1, 2, 0]);

    await tester.tapAt(Offset(iconRect.left - 2, iconRect.center.dy));
    expect(ordinals.last, 1);
  });

  testWidgets('tapping a rendered todo toggles the source and autosaves',
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
    late Note note;
    await tester.runAsync(() async {
      final book = await db.createNotebook('work');
      note = await db.createNote(book.id,
          title: 'todos', content: '- [ ] todo a\n\n- [ ] todo b');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_box_outline_blank), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.check_box_outline_blank).at(0));
    await tester.pump();
    expect(find.byIcon(Icons.check_box), findsOneWidget);

    now += 1000;
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final saved = await db.getNote(note.id);
      expect(saved.content, '- [x] todo a\n\n- [ ] todo b');
    });

    await tester.tap(find.byIcon(Icons.check_box));
    await tester.pump();
    now += 1000;
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final saved = await db.getNote(note.id);
      expect(saved.content, '- [ ] todo a\n\n- [ ] todo b');
    });
  });

  test('syncResultMessage 区分零增量与有变化', () {
    expect(syncResultMessage(const SyncOutcome(ran: false), 0),
        '未配置同步，去设置页开启');
    expect(
        syncResultMessage(const SyncOutcome(ran: true, uploadedNotes: 2), 5),
        '同步完成 · 上传 2 · 下载 0');
    expect(syncResultMessage(const SyncOutcome(ran: true), 30),
        '同步完成 · 无增量变化 · 远端 30 篇笔记与本地一致');
    expect(
        syncResultMessage(const SyncOutcome(ran: true, downloadedAssets: 1), 30),
        '同步完成 · 上传 0 · 下载 0');
    expect(
        syncResultMessage(const SyncOutcome(ran: true, conflicts: 2), 30),
        '同步完成 · 无增量变化 · 远端 30 篇笔记与本地一致 · 2 处冲突待裁决');
  });

  testWidgets('侧栏展示上次同步时间', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_sync_caption');
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
    final at = DateTime.now().subtract(const Duration(minutes: 5));
    state.sync.lastSyncAt = at.millisecondsSinceEpoch;
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
    final hm =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    expect(find.text('上次同步 $hm'), findsOneWidget);
  });
}
