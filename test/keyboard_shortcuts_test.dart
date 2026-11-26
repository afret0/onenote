import 'dart:io';

// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/theme.dart';
import 'package:onenote/ui/widgets.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppState, AppDb, Note)> seed(WidgetTester tester,
      {String content = 'alpha'}) async {
    NativeTransport.debugOverride = NativeTransport.testing()
      ..invokeHandler = (call) async {
        if (call.method == 'initialize') {
          return {'view': (call.arguments as Map)['view']};
        }
        return null;
      };
    addTearDown(() => NativeTransport.debugOverride = null);
    final supportDir =
        Directory.systemTemp.createTempSync('onenote_shortcut_test');
    addTearDown(() => supportDir.deleteSync(recursive: true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
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
      now += 1000;
      final notebook = await db.createNotebook('work');
      now += 1000;
      note = await db.createNote(notebook.id, title: 't', content: content);
      await state.init();
    });
    return (state, db, note);
  }

  Widget app(AppState state) => MaterialApp(
        theme: buildInkTheme(Brightness.dark),
        home: HomePage(state: state),
      );

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  void narrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key,
      {bool meta = false, bool control = false}) async {
    final mod = meta
        ? LogicalKeyboardKey.metaLeft
        : control
            ? LogicalKeyboardKey.controlLeft
            : null;
    if (mod != null) {
      await tester.sendKeyDownEvent(mod);
    }
    await tester.sendKeyEvent(key);
    if (mod != null) {
      await tester.sendKeyUpEvent(mod);
    }
    await tester.pumpAndSettle();
  }

  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  Finder contentField() =>
      find.byWidgetPredicate((w) => w is TextField && w.expands == true);

  Finder hintField(String hint) => find.byWidgetPredicate((w) =>
      w is TextField &&
      w.decoration is InputDecoration &&
      (w.decoration as InputDecoration).hintText == hint);

  TextEditingController contentController(WidgetTester tester) =>
      tester.widget<TextField>(contentField()).controller!;

  Finder replacePanel() => find.byKey(const ValueKey('replacePanel'));

  List<MethodCall> captureSystemExits() {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') {
          calls.add(call);
        }
        return null;
      },
    );
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return calls;
  }

  testWidgets('cmd+f focuses global search on wide layout', (tester) async {
    wide(tester);
    final (state, _, _) = await seed(tester);
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.keyF, meta: true);
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('ctrl+f focuses global search on wide layout', (tester) async {
    wide(tester);
    final (state, _, _) = await seed(tester);
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.keyF, control: true);
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('cmd+f schedules a frame so focus lands while idle',
      (tester) async {
    wide(tester);
    final (state, _, _) = await seed(tester);
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('cmd+f works right after startup before any click',
      (tester) async {
    wide(tester);
    NativeTransport.debugOverride = NativeTransport.testing()
      ..invokeHandler = (call) async {
        if (call.method == 'initialize') {
          return {'view': (call.arguments as Map)['view']};
        }
        return null;
      };
    addTearDown(() => NativeTransport.debugOverride = null);
    final supportDir =
        Directory.systemTemp.createTempSync('onenote_startup_focus');
    addTearDown(() => supportDir.deleteSync(recursive: true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      now += 1000;
      final notebook = await db.createNotebook('work');
      now += 1000;
      final note =
          await db.createNote(notebook.id, title: 't', content: 'alpha');
      await db.setSetting(AppDb.lastViewScopeKey, 'all');
      await db.setSetting(AppDb.lastViewNoteKey, note.id);
    });
    await tester.pumpWidget(
        ListenableBuilder(listenable: state, builder: (_, _) => app(state)));
    await tester.pump();
    await tester.runAsync(() async {
      await state.init();
    });
    await tester.pumpAndSettle();
    expect(state.openNoteId, isNotNull);

    await press(tester, LogicalKeyboardKey.keyF, meta: true);
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('cmd+f still works after leaving edit mode', (tester) async {
    wide(tester);
    final (state, _, _) = await seed(tester);
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.check));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.keyF, meta: true);
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('cmd+f on narrow flushes pending edits then closes note',
      (tester) async {
    narrow(tester);
    final (state, db, note) = await seed(tester);
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NoteCard, 't'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(contentField(), 'pending edit');

    await press(tester, LogicalKeyboardKey.keyF, meta: true);

    expect(state.openNoteId, isNull);
    expect(find.byType(NoteView), findsNothing);
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
    final fresh = await db.findNote(note.id);
    expect(fresh!.content, 'pending edit');
  });

  testWidgets('system back on narrow closes drawer, then note, then exits',
      (tester) async {
    narrow(tester);
    final (state, _, _) = await seed(tester);
    final exits = captureSystemExits();
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NoteCard, 't'));
    await tester.pumpAndSettle();
    expect(state.openNoteId, isNotNull);

    await tester.dragFrom(const Offset(2, 300), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ScopeTile, 'work'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ScopeTile, 'work'), findsNothing);
    expect(state.openNoteId, isNotNull);
    expect(exits, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(state.openNoteId, isNull);
    expect(find.byType(NoteView), findsNothing);
    expect(find.widgetWithText(NoteCard, 't'), findsOneWidget);
    expect(exits, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exits, hasLength(1));
  });

  testWidgets('system back on narrow flushes pending edits then closes note',
      (tester) async {
    narrow(tester);
    final (state, db, note) = await seed(tester);
    captureSystemExits();
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NoteCard, 't'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(contentField(), 'pending edit');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(state.openNoteId, isNull);
    expect(find.byType(NoteView), findsNothing);
    final fresh = await db.findNote(note.id);
    expect(fresh!.content, 'pending edit');
  });

  testWidgets('system back on wide keeps default exit behavior',
      (tester) async {
    wide(tester);
    final (state, _, _) = await seed(tester);
    final exits = captureSystemExits();
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();
    expect(state.openNoteId, isNotNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exits, hasLength(1));
  });

  testWidgets('cmd+comma opens settings page', (tester) async {
    wide(tester);
    final (state, _, _) = await seed(tester);
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.comma, meta: true);
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('cmd+r replace panel is edit-only and case-sensitive',
      (tester) async {
    wide(tester);
    final (state, db, note) =
        await seed(tester, content: 'Foo foo\nfoo bar');
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.keyR, meta: true);
    expect(replacePanel(), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyR, meta: true);
    expect(replacePanel(), findsOneWidget);

    await tester.enterText(hintField('查找（区分大小写）'), 'foo');
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(contentController(tester).selection,
        const TextSelection(baseOffset: 4, extentOffset: 7));

    await tester.tap(find.byTooltip('下一处'));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(contentController(tester).selection,
        const TextSelection(baseOffset: 8, extentOffset: 11));

    await tester.enterText(hintField('替换为'), 'baz');
    await tester.tap(find.text('替换'));
    await tester.pumpAndSettle();
    expect(contentController(tester).text, 'Foo foo\nbaz bar');
    expect(find.text('1/1'), findsOneWidget);

    await tester.tap(find.text('全部替换'));
    await tester.pumpAndSettle();
    expect(contentController(tester).text, 'Foo baz\nbaz bar');
    expect(find.text('已替换 1 处'), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.check));
    await tester.pumpAndSettle();
    expect(replacePanel(), findsNothing);
    final fresh = await db.findNote(note.id);
    expect(fresh!.content, 'Foo baz\nbaz bar');

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyR, meta: true);
    expect(replacePanel(), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(replacePanel(), findsNothing);
    expect(tester.widget<TextField>(contentField()).focusNode!.hasFocus, isTrue);
  });
}
