import 'dart:io';

// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/markdown_view.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppState, Note)> seed(WidgetTester tester, String content) async {
    NativeTransport.debugOverride = NativeTransport.testing()
      ..invokeHandler = (call) async {
        if (call.method == 'initialize') {
          return {'view': (call.arguments as Map)['view']};
        }
        return null;
      };
    addTearDown(() => NativeTransport.debugOverride = null);
    final supportDir =
        Directory.systemTemp.createTempSync('onenote_scroll_test');
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
    return (state, note);
  }

  Widget app(AppState state, Note note) => MaterialApp(
        theme: buildInkTheme(Brightness.dark),
        home: Scaffold(
          body: NoteView(
            state: state,
            noteId: note.id,
            showBack: false,
            onBack: () {},
          ),
        ),
      );

  SingleChildScrollView renderScroll(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView).first);

  testWidgets('entering edit near the top keeps caret at the first visible line',
      (tester) async {
    final content = List.generate(150, (i) => 'line $i').join('\n\n');
    final (state, note) = await seed(tester, content);
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();

    final scroll = renderScroll(tester);
    final maxExtent = scroll.controller!.position.maxScrollExtent;
    expect(maxExtent, greaterThan(0));
    scroll.controller!.jumpTo(24);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final caret = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.expands)
        .controller!
        .selection
        .baseOffset;
    expect(caret, content.indexOf('line 0'));

    final editPosition = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .firstWhere((e) => e.maxLines == null)
        .scrollController!
        .position;
    expect(editPosition.pixels, lessThan(editPosition.maxScrollExtent * 0.5));
    expect(editPosition.pixels, lessThan(editPosition.maxScrollExtent * 0.95));
  });

  testWidgets('entering edit anchors caret to the visible heading, not a fraction',
      (tester) async {
    final content = '${List.generate(30, (i) => '# head $i').join('\n\n')}\n\n'
        '${List.generate(10, (i) => 'line $i').join('\n\n')}\n\n'
        '## buffer tail\n\n'
        '${List.generate(10, (i) => 'tail $i').join('\n\n')}';
    final (state, note) = await seed(tester, content);
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();

    final scroll = renderScroll(tester);
    final heading = find.descendant(
        of: find.byType(MarkdownView), matching: find.text('buffer tail'));
    expect(heading, findsOneWidget);
    final viewportTop =
        tester.getTopLeft(find.byType(SingleChildScrollView).first).dy;
    final headingTop = tester.getTopLeft(heading).dy;
    scroll.controller!.jumpTo(
        scroll.controller!.position.pixels + headingTop - viewportTop);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final caret = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.expands)
        .controller!
        .selection
        .baseOffset;
    expect(caret, content.indexOf('buffer tail'));

    final editPosition = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .firstWhere((e) => e.maxLines == null)
        .scrollController!
        .position;
    expect(editPosition.pixels, greaterThan(0));
    expect(editPosition.pixels, lessThan(editPosition.maxScrollExtent));
  });

  testWidgets('scroll-top button appears after scrolling and animates back to top',
      (tester) async {
    final content = List.generate(150, (i) => 'line $i').join('\n\n');
    final (state, note) = await seed(tester, content);
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);

    final controller = renderScroll(tester).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.position.pixels, greaterThan(0));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, 0);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
  });

  testWidgets('edit actions sit on the meta row at the edit button position',
      (tester) async {
    final (state, note) = await seed(tester, 'hello');
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();

    final editRight = tester.getTopRight(find.byType(OutlinedButton)).dx;
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.widgetWithIcon(FilledButton, Icons.check), findsOneWidget);
    final done = find.byType(FilledButton);
    expect(tester.getTopRight(done).dx, moreOrLessEquals(editRight, epsilon: 1));
    final headerY = tester.getTopLeft(find.byType(TextField).first).dy;
    expect(tester.getTopLeft(done).dy, greaterThan(headerY));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
  });

  testWidgets('scroll-top button aligns with the edit button right edge',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final content = List.generate(150, (i) => 'line $i').join('\n\n');
    final (state, note) = await seed(tester, content);
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();

    final editRight = tester.getTopRight(find.byType(OutlinedButton)).dx;
    final controller = renderScroll(tester).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final up = find.bySemanticsLabel('回到顶部');
    expect(up, findsOneWidget);
    final viewportWidth = tester.getSize(find.byType(NoteView)).width;
    final upRight = tester.getTopRight(up).dx;
    expect(upRight, moreOrLessEquals(editRight, epsilon: 1));
    expect(upRight, lessThan(viewportWidth - spaceLg));
  });

  testWidgets('edit button stays visible and usable after scrolling down',
      (tester) async {
    final content = List.generate(150, (i) => 'line $i').join('\n\n');
    final (state, note) = await seed(tester, content);
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();

    final controller = renderScroll(tester).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final edit = find.byIcon(Icons.edit_outlined);
    expect(edit, findsOneWidget);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.widgetWithIcon(FilledButton, Icons.check), findsOneWidget);
  });

  testWidgets('edit page accents follow notebook tint and done is icon-only',
      (tester) async {
    final (state, note) = await seed(tester, 'hello');
    const orange = Color(0xFFE8890C);
    await tester.runAsync(() async {
      await state.setNotebookColor(note.notebookId, orange.toARGB32());
    });
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('完成'), findsNothing);
    final t = InkTokens.dark;
    final fill = readableOn(orange, t.paper, ratio: 3);
    final done = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(done.style!.backgroundColor!.resolve({}), fill);
    expect(done.style!.foregroundColor!.resolve({}),
        readableOn(t.onAccent, fill));
    final content = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .firstWhere((e) => e.maxLines == null);
    expect(content.cursorColor, readableOn(orange, t.paper));
    expect(content.selectionColor, fill.withValues(alpha: 0.4));
  });
}