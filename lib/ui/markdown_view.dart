import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/attachment_store.dart';
import '../data/markdown_tasks.dart';
import 'attachment_image.dart';
import 'theme.dart';

class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.content,
    this.attachments,
    this.onAttachmentLink,
    this.onToggleTask,
    this.highlightQuery,
    this.highlightController,
  });

  final String content;
  final AttachmentStore? attachments;
  final void Function(String id)? onAttachmentLink;
  final void Function(int ordinal)? onToggleTask;
  final String? highlightQuery;
  final MarkdownHighlightController? highlightController;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    if (content.trim().isEmpty) {
      return Text('这篇笔记还没有内容，点「编辑」开始书写。',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: t.inkFaint));
    }
    final headingSerif = TextStyle(
      fontFamily: serifFamily,
      fontFamilyFallback: cjkSerifFallback,
      color: t.ink,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    );
    final contentScale = t.noteFontSize * t.fontScale / 16;
    final body = TextStyle(
      fontFamily: t.sans,
      fontFamilyFallback: cjkSansFallback,
      fontSize: 16 * contentScale,
      height: 1.8,
      color: t.ink,
    );
    final mono = TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: cjkMonoFallback,
      fontSize: 13.5 * contentScale,
      height: 1.6,
      color: t.ink,
    );
    final store = attachments;
    final toggle = onToggleTask;
    final taskCount = toggle == null ? 0 : markdownTaskStates(content).length;
    final lineHeight = body.fontSize! * body.height!;
    var checkboxCalls = 0;
    return MarkdownBody(
      data: content,
      selectable: true,
      highlightQuery: highlightQuery,
      highlightColor: highlightQuery == null ? null : t.accentSoft,
      highlightController: highlightController,
      blockSyntaxes: markdownTaskBlockSyntaxes,
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
      checkboxBuilder: (checked) {
        if (toggle == null || taskCount == 0) {
          return _TaskCheckbox(checked: checked, lineHeight: lineHeight);
        }
        final ordinal = checkboxCalls++ % taskCount;
        return _TaskCheckbox(
          checked: checked,
          lineHeight: lineHeight,
          onTap: () => toggle(ordinal),
        );
      },
      builders: store == null
          ? const {}
          : {'img': AttachmentImageBuilder(store)},
      styleSheet: MarkdownStyleSheet(
        p: body,
        h1: headingSerif.copyWith(fontSize: 30 * contentScale, height: 1.3),
        h2: headingSerif.copyWith(fontSize: 24 * contentScale, height: 1.35),
        h3: headingSerif.copyWith(fontSize: 20 * contentScale, height: 1.4),
        h4: headingSerif.copyWith(fontSize: 17 * contentScale, height: 1.4),
        h1Padding: const EdgeInsets.only(top: spaceSm, bottom: spaceMd),
        h2Padding: const EdgeInsets.only(top: spaceMd, bottom: spaceSm),
        h3Padding: const EdgeInsets.only(top: spaceMd, bottom: spaceSm),
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(
            color: t.accentText, decoration: TextDecoration.underline),
        blockquote: body.copyWith(color: t.inkMuted),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.accent, width: 3)),
          color: t.surfaceAlt.withValues(alpha: 0.5),
        ),
        blockquotePadding:
            const EdgeInsets.symmetric(horizontal: spaceMd, vertical: spaceSm),
        code: mono.copyWith(
            backgroundColor: t.surfaceAlt, fontSize: 13 * contentScale),
        codeblockDecoration: BoxDecoration(
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(color: t.hairline),
        ),
        codeblockPadding: const EdgeInsets.all(spaceMd),
        codeblockAlign: WrapAlignment.start,
        listBullet: body.copyWith(color: t.accent),
        listIndent: 28,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline, width: 1)),
        ),
        tableHead: body.copyWith(fontWeight: FontWeight.w700),
        tableBody: body,
        tableBorder: TableBorder.all(color: t.hairline, width: 1),
        tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: spaceSm + 4, vertical: spaceSm),
        tableCellsDecoration: BoxDecoration(color: t.surface),
        checkbox: body.copyWith(color: t.accent),
      ),
      onTapLink: (text, href, title) {
        if (href == null) {
          return;
        }
        final match = AttachmentStore.refPattern.firstMatch(href);
        if (match != null) {
          onAttachmentLink?.call(match.group(1)!);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(href)));
      },
    );
  }
}

class _TaskCheckbox extends StatefulWidget {
  const _TaskCheckbox({
    required this.checked,
    required this.lineHeight,
    this.onTap,
  });

  final bool checked;
  final double lineHeight;
  final VoidCallback? onTap;

  @override
  State<_TaskCheckbox> createState() => _TaskCheckboxState();
}

class _TaskCheckboxState extends State<_TaskCheckbox> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final interactive = widget.onTap != null;
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: SizedBox(
            width: 28,
            height: widget.lineHeight,
            child: Center(
              child: Opacity(
                opacity: _pressed ? 0.7 : 1,
                child: Icon(
                  widget.checked
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 20,
                  color: interactive && _hover ? t.accentText : t.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}