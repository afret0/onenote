import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../data/attachment_store.dart';
import 'theme.dart';

class AttachmentImageBuilder extends MarkdownElementBuilder {
  AttachmentImageBuilder(this.store);

  final AttachmentStore store;

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
    return _AttachmentImage(
      store: store,
      id: match.group(1)!,
      alt: element.textContent,
    );
  }
}

class _AttachmentImage extends StatefulWidget {
  const _AttachmentImage({
    required this.store,
    required this.id,
    required this.alt,
  });

  final AttachmentStore store;
  final String id;
  final String alt;

  @override
  State<_AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<_AttachmentImage> {
  Uint8List? _bytes;
  bool _missing = false;

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: spaceSm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ),
    );
  }
}