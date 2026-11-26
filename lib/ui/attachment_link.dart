import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../data/attachment_refs.dart';
import '../data/attachment_store.dart';

class AttachmentLinkBuilder extends MarkdownElementBuilder {
  AttachmentLinkBuilder({
    required this.onTap,
    required this.onContext,
    this.refCounter,
  });

  final void Function(String id, int ordinal) onTap;
  final void Function(String id, int ordinal, Offset position) onContext;
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
    return _PdfAttachmentLink(
      id: id,
      text: text,
      ordinal: refCounter?.next(id) ?? 0,
      style: parentStyle?.merge(preferredStyle) ?? preferredStyle,
      onTap: onTap,
      onContext: onContext,
    );
  }
}

class _PdfAttachmentLink extends StatefulWidget {
  const _PdfAttachmentLink({
    required this.id,
    required this.text,
    required this.ordinal,
    required this.style,
    required this.onTap,
    required this.onContext,
  });

  final String id;
  final String text;
  final int ordinal;
  final TextStyle? style;
  final void Function(String id, int ordinal) onTap;
  final void Function(String id, int ordinal, Offset position) onContext;

  @override
  State<_PdfAttachmentLink> createState() => _PdfAttachmentLinkState();
}

class _PdfAttachmentLinkState extends State<_PdfAttachmentLink> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(widget.id, widget.ordinal),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onSecondaryTapUp: (d) =>
            widget.onContext(widget.id, widget.ordinal, d.globalPosition),
        onLongPressStart: (d) =>
            widget.onContext(widget.id, widget.ordinal, d.globalPosition),
        child: Opacity(
          opacity: _pressed ? 0.7 : (_hover ? 0.85 : 1),
          child: Text(widget.text, style: widget.style),
        ),
      ),
    );
  }
}