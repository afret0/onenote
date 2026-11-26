import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/ui/markdown_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  Widget wrap(String content, {double gutter = 24, double width = 448,
      void Function(int)? onToggleTask}) {
    return MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: MarkdownView(
              content: content,
              gutter: gutter,
              onToggleTask: onToggleTask,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> dragSelect(WidgetTester tester, Offset from, Offset to) async {
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveTo(to);
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await tester.pumpAndSettle();
  }

  TextSelection? activeSelection(WidgetTester tester) {
    final states =
        tester.stateList<EditableTextState>(find.byType(EditableText));
    for (final s in states) {
      if (!s.textEditingValue.selection.isCollapsed) {
        return s.textEditingValue.selection;
      }
    }
    return null;
  }

  testWidgets('drag from right slack selects to word start',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap('# onenote'));
    await tester.pumpAndSettle();
    final st = find.byType(SelectableText).first;
    final tl = tester.getTopLeft(st);
    final sz = tester.getSize(st);
    final midY = tl.dy + sz.height / 2;
    await dragSelect(tester, Offset(tl.dx + sz.width + 10, midY),
        Offset(tl.dx + 5, midY));
    final sel = activeSelection(tester);
    expect(sel, isNotNull);
    expect(sel!.start, 0);
    expect(sel.end, 7);
  });

  testWidgets('drag from left gutter selects from first char',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap('# onenote'));
    await tester.pumpAndSettle();
    final st = find.byType(SelectableText).first;
    final tl = tester.getTopLeft(st);
    final sz = tester.getSize(st);
    final midY = tl.dy + sz.height / 2;
    await dragSelect(tester, Offset(tl.dx - 10, midY),
        Offset(tl.dx + sz.width - 5, midY));
    final sel = activeSelection(tester);
    expect(sel, isNotNull);
    expect(sel!.start, 0);
    expect(sel.end, 7);
  });

  testWidgets('paragraph gutter-to-slack drag selects whole text',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap('hello world'));
    await tester.pumpAndSettle();
    final st = find.byType(SelectableText).first;
    final tl = tester.getTopLeft(st);
    final sz = tester.getSize(st);
    final midY = tl.dy + sz.height / 2;
    await dragSelect(tester, Offset(tl.dx - 10, midY),
        Offset(tl.dx + sz.width + 20, midY));
    final sel = activeSelection(tester);
    expect(sel, isNotNull);
    expect(sel!.start, 0);
    expect(sel.end, 11);
  });

  testWidgets('double click inside word still selects word',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap('# onenote'));
    await tester.pumpAndSettle();
    final st = find.byType(SelectableText).first;
    final tl = tester.getTopLeft(st);
    final sz = tester.getSize(st);
    final midY = tl.dy + sz.height / 2;
    await tester.tapAt(Offset(tl.dx + 5, midY));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(tl.dx + 5, midY));
    await tester.pumpAndSettle();
    final sel = activeSelection(tester);
    expect(sel, isNotNull);
    expect(sel!.start, 0);
    expect(sel.end, 7);
  });

  testWidgets('gutter keeps text inset identical to old padding',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap('hello world', gutter: 24, width: 448));
    await tester.pumpAndSettle();
    final tl = tester.getTopLeft(find.byType(SelectableText).first);
    expect(tl.dx, 24);
    expect(tester.getSize(find.byType(SelectableText).first).width,
        lessThanOrEqualTo(400));
    await tester.pumpWidget(wrap('hello world', gutter: 0, width: 400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(SelectableText).first).dx, 0);
  });

  testWidgets('list gutter click does not toggle checkbox',
      (WidgetTester tester) async {
    final toggled = <int>[];
    await tester.pumpWidget(wrap('- [ ] task one\n- [x] task two',
        onToggleTask: toggled.add));
    await tester.pumpAndSettle();
    final st = find.byType(SelectableText).first;
    final tl = tester.getTopLeft(st);
    final sz = tester.getSize(st);
    final midY = tl.dy + sz.height / 2;
    await dragSelect(tester, Offset(4, midY), Offset(tl.dx + 5, midY));
    await tester.pumpAndSettle();
    expect(toggled, isEmpty);
  });

  testWidgets('list gutter click does not steal checkbox direct tap',
      (WidgetTester tester) async {
    final toggled = <int>[];
    await tester.pumpWidget(wrap('- [ ] task one\n- [x] task two',
        onToggleTask: toggled.add));
    await tester.pumpAndSettle();
    final box = find.byIcon(Icons.check_box_outline_blank);
    expect(box, findsOneWidget);
    await tester.tap(box);
    await tester.pumpAndSettle();
    expect(toggled, [0]);
  });

  testWidgets('pre block keeps horizontal scroll layout with gutter',
      (WidgetTester tester) async {
    final code = 'x' * 200;
    await tester.pumpWidget(wrap('```\n$code\n```'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scrollables = find.byType(SingleChildScrollView);
    expect(scrollables, findsOneWidget);
  });

  testWidgets('table keeps fixed column layout with gutter',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap('| a | b |\n| - | - |\n| 1 | 2 |'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final st = find.byType(SelectableText);
    expect(st, findsWidgets);
    for (final e in st.evaluate()) {
      final box = e.renderObject;
      expect(box, isNotNull);
    }
  });

  testWidgets('no gutter keeps legacy hit behavior of plain body',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap('hello world', gutter: 0, width: 400));
    await tester.pumpAndSettle();
    final st = find.byType(SelectableText).first;
    final tl = tester.getTopLeft(st);
    final sz = tester.getSize(st);
    final midY = tl.dy + sz.height / 2;
    await dragSelect(tester, Offset(tl.dx + sz.width + 10, midY),
        Offset(tl.dx + 20, midY));
    final sel = activeSelection(tester);
    expect(sel, isNotNull);
  });
}
