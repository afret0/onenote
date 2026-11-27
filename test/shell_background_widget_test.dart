import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/bg_theme.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/shell_background.dart';
import 'package:onenote/ui/theme.dart';
import 'package:onenote/ui/widgets.dart';

void main() {
  Future<AppState> seed(WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync('onenote_bg_widget');
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
      now += 1000;
      await db.createNote(work.id, title: 'second', content: 'beta');
      await state.init();
    });
    return state;
  }

  Future<void> pumpHome(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
  }

  Finder paintedBackground() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ShellBgPainter);

  Finder paperFill() => find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == InkTokens.dark.paper);

  testWidgets('缺省渲染背景且点击穿透', (tester) async {
    final state = await seed(tester);
    await pumpHome(tester, state);

    expect(paintedBackground(), findsOneWidget);
    expect(
        find.ancestor(
            of: paintedBackground(),
            matching: find.byWidgetPredicate(
                (w) => w is IgnorePointer && w.ignoring)),
        findsOneWidget);

    await tester.tap(find.widgetWithText(NoteCard, 'first'));
    await tester.pumpAndSettle();
    expect(state.openNoteId, isNotNull);
    expect(
        find.descendant(
            of: find.byType(NoteView), matching: find.text('alpha')),
        findsOneWidget);
  });

  testWidgets('三档范围控制实色纸底包裹', (tester) async {
    final state = await seed(tester);
    await pumpHome(tester, state);
    expect(find.byType(NoteView), findsOneWidget);
    expect(paperFill(), findsOneWidget);

    await tester.runAsync(() => state.setBgScope(AppState.bgScopeEmpty));
    await tester.pumpAndSettle();
    expect(paperFill(), findsNWidgets(3));

    await tester.runAsync(() => state.setBgScope(AppState.bgScopeFull));
    await tester.pumpAndSettle();
    expect(paperFill(), findsNothing);
  });

  testWidgets('不使用主题时不画图案', (tester) async {
    final state = await seed(tester);
    await pumpHome(tester, state);
    expect(paintedBackground(), findsOneWidget);

    await tester.runAsync(() => state.setBgTheme(shellBgNone));
    await tester.pumpAndSettle();
    expect(paintedBackground(), findsNothing);
  });
}