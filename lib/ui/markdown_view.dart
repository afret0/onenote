import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../data/attachment_store.dart';
import 'attachment_image.dart';
import 'theme.dart';

class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.content,
    this.attachments,
    this.onAttachmentLink,
  });

  final String content;
  final AttachmentStore? attachments;
  final void Function(String id)? onAttachmentLink;

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
    final body = TextStyle(
      fontFamily: sansFamily,
      fontFamilyFallback: cjkSansFallback,
      fontSize: 16,
      height: 1.8,
      color: t.ink,
    );
    final mono = TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: cjkMonoFallback,
      fontSize: 13.5,
      height: 1.6,
      color: t.ink,
    );
    final store = attachments;
    return MarkdownBody(
      data: content,
      selectable: true,
      builders: store == null
          ? const {}
          : {'img': AttachmentImageBuilder(store)},
      styleSheet: MarkdownStyleSheet(
        p: body,
        h1: headingSerif.copyWith(fontSize: 30, height: 1.3),
        h2: headingSerif.copyWith(fontSize: 24, height: 1.35),
        h3: headingSerif.copyWith(fontSize: 20, height: 1.4),
        h4: headingSerif.copyWith(fontSize: 17, height: 1.4),
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
            backgroundColor: t.surfaceAlt, fontSize: 13),
        codeblockDecoration: BoxDecoration(
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(color: t.hairline),
        ),
        codeblockPadding: const EdgeInsets.all(spaceMd),
        codeblockAlign: WrapAlignment.start,
        listBullet: body.copyWith(color: t.accent),
        listIndent: 24,
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