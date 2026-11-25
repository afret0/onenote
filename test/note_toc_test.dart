import 'dart:io';

// ignore: implementation_imports
import 'package:desktop_drop/src/native_transport.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/note_toc.dart';
import 'package:onenote/ui/note_view.dart';
import 'package:onenote/ui/theme.dart';

String filler(int count) =>
    List.generate(count, (i) => '段落 $i').join('\n\n');

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
        Directory.systemTemp.createTempSync('onenote_toc_test');
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

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  SingleChildScrollView renderScroll(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView).first);

  String sections() => '# 章节一\n\n${filler(40)}\n\n## 小节\n\n'
      '${filler(40)}\n\n### 细节\n\n${filler(40)}\n\n#### 深层标题\n\nend';

  testWidgets('controller records headings in order, reuses keys, notifies on change',
      (tester) async {
    final toc = MarkdownTocController();
    addTearDown(toc.dispose);
    var notifications = 0;
    toc.addListener(() => notifications++);
    Widget body(String data) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownBody(data: data, tocController: toc),
            ),
          ),
        );
    await tester.pumpWidget(body('# A\n\n## B\n\ntext\n\n### C\n\n#### D'));
    expect(toc.entries.map((e) => e.level).toList(), [1, 2, 3, 4]);
    expect(toc.entries.map((e) => e.text).toList(), ['A', 'B', 'C', 'D']);
    expect(notifications, 1);
    final keys = toc.entries.map((e) => e.key).toList();

    await tester.pumpWidget(body('# A\n\n## B\n\ntext\n\n### C\n\n#### D'));
    expect(notifications, 1);
    for (var i = 0; i < keys.length; i++) {
      expect(identical(toc.entries[i].key, keys[i]), isTrue);
    }

    await tester.pumpWidget(body('# X'));
    expect(notifications, 2);
    expect(toc.entries.single.text, 'X');
    expect(identical(toc.entries.single.key, keys.first), isTrue);
  });

  testWidgets('wide shows toc column with h1-h3 only, click scrolls and tracks active',
      (tester) async {
    wide(tester);
    final (state, note) = await seed(tester, sections());
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTocPanel), findsOneWidget);
    expect(find.widgetWithText(NoteTocRow, '章节一'), findsOneWidget);
    expect(find.widgetWithText(NoteTocRow, '小节'), findsOneWidget);
    expect(find.widgetWithText(NoteTocRow, '细节'), findsOneWidget);
    expect(find.widgetWithText(NoteTocRow, '深层标题'), findsNothing);

    final controller = renderScroll(tester).controller!;
    expect(controller.position.pixels, 0);
    await tester.tap(find.widgetWithText(NoteTocRow, '小节'));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, greaterThan(0));
    expect(
        tester
            .widget<NoteTocRow>(find.widgetWithText(NoteTocRow, '小节'))
            .active,
        isTrue);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<NoteTocRow>(find.widgetWithText(NoteTocRow, '细节'))
            .active,
        isTrue);
  });

  testWidgets('note title menu toggles toc and persists the choice',
      (tester) async {
    wide(tester);
    final (state, note) = await seed(tester, sections());
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsOneWidget);

    final title = find.descendant(
        of: find.byType(NoteView), matching: find.text('t'));
    await tester.longPress(title);
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏目录'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsNothing);
    expect(await state.db.getSetting('tocVisible'), '0');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsNothing);

    await tester.longPress(title);
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示目录'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsOneWidget);
    expect(await state.db.getSetting('tocVisible'), '1');
  });

  testWidgets('narrow shows floating button opening a sheet that jumps',
      (tester) async {
    final (state, note) = await seed(tester, sections());
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTocPanel), findsNothing);
    final button = find.bySemanticsLabel('目录');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsOneWidget);

    final controller = renderScroll(tester).controller!;
    await tester.tap(find.widgetWithText(NoteTocRow, '小节'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsNothing);
    expect(controller.position.pixels, greaterThan(0));
  });

  testWidgets('wide window with narrow pane falls back to floating button',
      (tester) async {
    wide(tester);
    final (state, note) = await seed(tester, sections());
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            child: NoteView(
              state: state,
              noteId: note.id,
              showBack: false,
              onBack: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsNothing);
    expect(find.bySemanticsLabel('目录'), findsOneWidget);
  });

  testWidgets('editing hides toc column and restoring brings it back',
      (tester) async {
    wide(tester);
    final (state, note) = await seed(tester, sections());
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsNothing);

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.check));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsOneWidget);
  });

  testWidgets('notes without headings show neither column nor button',
      (tester) async {
    wide(tester);
    final (state, note) = await seed(tester, filler(10));
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTocPanel), findsNothing);
    expect(find.bySemanticsLabel('目录'), findsNothing);
  });

  testWidgets('readableOn keeps palette and arbitrary colors readable',
      (tester) async {
    for (final brightness in Brightness.values) {
      late InkTokens t;
      await tester.pumpWidget(MaterialApp(
        theme: buildInkTheme(brightness),
        home: Builder(builder: (context) {
          t = inkOf(context);
          return const SizedBox();
        }),
      ));
      final values = [
        ...notebookPalette,
        0xFF808080,
        0xFF000000,
        0xFFFFFFFF,
      ];
      for (final value in values) {
        final color = Color(value);
        final text = readableOn(color, t.surfaceAlt);
        expect(contrastRatio(text, t.surfaceAlt), greaterThanOrEqualTo(4.5),
            reason: 'brightness: $brightness, color: $color');
        final bar = readableOn(color, t.surfaceAlt, ratio: 3);
        expect(contrastRatio(bar, t.surfaceAlt), greaterThanOrEqualTo(3),
            reason: 'brightness: $brightness, color: $color');
        if (contrastRatio(color, t.surfaceAlt) >= 4.5) {
          expect(identical(text, color), isTrue);
        }
      }
    }
  });

  testWidgets('toc row active colors use tint variants, default stays accent',
      (tester) async {
    const green = Color(0xFF16A34A);
    late InkTokens t;
    Widget host(Widget child) => MaterialApp(
          theme: buildInkTheme(Brightness.dark),
          home: Scaffold(body: Builder(builder: (context) {
            t = inkOf(context);
            return child;
          })),
        );
    final entries = [MarkdownTocEntry(GlobalKey(), 1, 'A')];
    await tester.pumpWidget(host(NoteTocPanel(
        entries: entries, activeIndex: 0, tint: green, onTap: (_) {})));
    Text rowText() => tester.widget<Text>(find.descendant(
        of: find.byType(NoteTocRow), matching: find.text('A')));
    Container bar() => tester.widget<Container>(find
        .descendant(of: find.byType(NoteTocRow), matching: find.byType(Container))
        .last);
    expect(rowText().style!.color, readableOn(green, t.surfaceAlt));
    expect((bar().decoration! as BoxDecoration).color,
        readableOn(green, t.surfaceAlt, ratio: 3));

    await tester.pumpWidget(host(NoteTocPanel(
        entries: entries, activeIndex: 0, onTap: (_) {})));
    expect(rowText().style!.color, t.accentText);
    expect((bar().decoration! as BoxDecoration).color, t.accent);
  });

  testWidgets('toc tint follows notebook color changes', (tester) async {
    wide(tester);
    final (state, note) = await seed(tester, sections());
    await tester.runAsync(
        () => state.setNotebookColor(note.notebookId, 0xFF16A34A));
    await tester.pumpWidget(app(state, note));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NoteTocRow, '章节一'));
    await tester.pumpAndSettle();
    final t = inkOf(tester.element(find.byType(NoteTocPanel)));
    final text = tester.widget<Text>(find.descendant(
        of: find.widgetWithText(NoteTocRow, '章节一'),
        matching: find.text('章节一')));
    expect(text.style!.color, readableOn(const Color(0xFF16A34A), t.surfaceAlt));
  });
}