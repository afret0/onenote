import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/ui/markdown_view.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  testWidgets('rendered selection color follows the notebook tint',
      (WidgetTester tester) async {
    const tint = Color(0xFFC14C50);
    final t = InkTokens.dark;
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: MarkdownView(
          content: 'hello `code` world',
          tint: tint,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final editable =
        tester.widget<EditableText>(find.byType(EditableText).first);
    final expected =
        readableOn(tint, t.paper, ratio: 3).withValues(alpha: 0.4);
    expect(editable.selectionColor, expected);
    expect(editable.selectionColor, isNot(t.accent.withValues(alpha: 0.4)));
  });

  testWidgets('rendered selection color falls back to accent without tint',
      (WidgetTester tester) async {
    final t = InkTokens.dark;
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: const Scaffold(
        body: MarkdownView(content: 'hello world'),
      ),
    ));
    await tester.pumpAndSettle();
    final editable =
        tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.selectionColor, t.accent.withValues(alpha: 0.4));
  });

  testWidgets('inline code chip keeps its background translucent',
      (WidgetTester tester) async {
    final t = InkTokens.dark;
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: const Scaffold(
        body: MarkdownView(content: 'hello `code` world'),
      ),
    ));
    await tester.pumpAndSettle();
    final rich = tester.widget<SelectableText>(find.byType(SelectableText).first);
    Color? chip;
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == 'code') {
          chip = span.style?.backgroundColor;
        }
        span.children?.forEach(visit);
      }
    }

    visit(rich.textSpan!);
    expect(chip, t.surfaceAlt.withValues(alpha: 0.6));
    expect(chip!.a, lessThan(1.0));
  });
}