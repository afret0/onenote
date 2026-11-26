import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../data/attachment_refs.dart';
import '../data/attachment_store.dart';
import 'pdf_inline.dart';

class AttachmentLinkBuilder extends MarkdownElementBuilder {
  AttachmentLinkBuilder({
    required this.store,
    this.refCounter,
  });

  final AttachmentStore store;
  final AttachmentRefCounter? refCounter;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'] ?? '';
    final match = AttachmentStore.refPattern.firstMatch(href);
    if (match == null) {
      return null;
    }
    final text = element.textContent;
    if (!isPdfLinkText(text)) {
      return null;
    }
    final id = match.group(1)!;
    final ordinal = refCounter?.next(id) ?? 0;
    final style = parentStyle?.merge(preferredStyle) ?? preferredStyle;
    return Text.rich(
      MarkdownLinkSpan(
        href: href,
        refOrdinal: ordinal,
        children: [
          TextSpan(text: text, style: style),
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: PdfInline(
              store: store,
              id: id,
              ordinal: ordinal,
            ),
          ),
        ],
      ),
    );
  }
}