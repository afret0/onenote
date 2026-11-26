import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../data/attachment_refs.dart';
import '../data/attachment_store.dart';
import 'theme.dart';

class AttachmentImageBuilder extends MarkdownElementBuilder {
  AttachmentImageBuilder(this.store, {this.refCounter, this.onTap, this.onContext});

  final AttachmentStore store;
  final AttachmentRefCounter? refCounter;
  final void Function(String id, int ordinal, Uint8List bytes)? onTap;
  final void Function(String id, int ordinal, Offset position)? onContext;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final src = element.attributes['src'] ?? '';
    final match = AttachmentStore.refPattern.firstMatch(src);
    if (match == null) {
      return null;
    }
    final id = match.group(1)!;
    return _AttachmentImage(
      store: store,
      id: id,
      alt: element.textContent,
      ordinal: refCounter?.next(id) ?? 0,
      onTap: onTap,
      onContext: onContext,
    );
  }
}

class _AttachmentImage extends StatefulWidget {
  const _AttachmentImage({
    required this.store,
    required this.id,
    required this.alt,
    required this.ordinal,
    this.onTap,
    this.onContext,
  });

  final AttachmentStore store;
  final String id;
  final String alt;
  final int ordinal;
  final void Function(String id, int ordinal, Uint8List bytes)? onTap;
  final void Function(String id, int ordinal, Offset position)? onContext;

  @override
  State<_AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<_AttachmentImage> {
  Uint8List? _bytes;
  bool _missing = false;
  bool _hover = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await widget.store.read(widget.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _bytes = bytes;
      _missing = bytes == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    if (_missing) {
      return Container(
        padding: const EdgeInsets.all(spaceMd),
        decoration: BoxDecoration(
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(color: t.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 18, color: t.inkFaint),
            const SizedBox(width: spaceSm),
            Text('图片附件缺失',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: t.inkMuted)),
          ],
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const SizedBox(
        height: 48,
        child: Center(
            child: SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final interactive = widget.onTap != null || widget.onContext != null;
    Widget image = Padding(
      padding: const EdgeInsets.symmetric(vertical: spaceSm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ),
    );
    if (!interactive) {
      return image;
    }
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () => widget.onTap!(widget.id, widget.ordinal, bytes),
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onSecondaryTapUp: widget.onContext == null
            ? null
            : (d) => widget.onContext!(widget.id, widget.ordinal, d.globalPosition),
        onLongPressStart: widget.onContext == null
            ? null
            : (d) => widget.onContext!(widget.id, widget.ordinal, d.globalPosition),
        child: Opacity(
          opacity: _pressed ? 0.85 : (_hover ? 0.92 : 1),
          child: image,
        ),
      ),
    );
  }
}