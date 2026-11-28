import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

class _TallLinkBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    if (element.tag != 'a') {
      return null;
    }
    return Text.rich(TextSpan(children: [
      TextSpan(text: element.textContent),
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: Container(height: 900, color: Colors.red),
      ),
    ]));
  }
}

void main() {
  testWidgets('placeholder height joins note scroll extent', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: MarkdownBody(
            data: '[pdf](x.pdf)\n\ntail text here',
            selectable: true,
            fitContent: false,
            gutter: 24,
            builders: {'a': _TallLinkBuilder()},
            styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 16, height: 1.8)),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.getSize(find.byType(MarkdownBody)).height, greaterThan(900));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    tester.binding.handlePointerEvent(pointer.hover(const Offset(400, 300)));
    await tester.pump();
    tester.binding.handlePointerEvent(pointer.scroll(const Offset(0, 120)));
    await tester.pump();
    expect(controller.offset, 120);
    tester.binding.handlePointerEvent(pointer.removePointer());
  });
}