import 'dart:io';

// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
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

  testWidgets('entering edit keeps render scroll fraction instead of jumping to end',
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
    final fraction = scroll.controller!.position.pixels / maxExtent;

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final caret = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.expands)
        .controller!
        .selection
        .baseOffset;
    expect(caret, (fraction * content.length).round());
    expect(caret, lessThan(content.length));

    final editPosition = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .firstWhere((e) => e.maxLines == null)
        .scrollController!
        .position;
    expect(editPosition.pixels, lessThan(editPosition.maxScrollExtent * 0.5));
    expect(editPosition.pixels, lessThan(editPosition.maxScrollExtent * 0.95));
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
}