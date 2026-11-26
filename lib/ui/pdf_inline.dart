import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../data/attachment_store.dart';
import 'theme.dart';

class PdfInline extends StatefulWidget {
  const PdfInline({
    super.key,
    required this.store,
    required this.id,
    required this.ordinal,
  });

  final AttachmentStore store;
  final String id;
  final int ordinal;

  @override
  State<PdfInline> createState() => _PdfInlineState();
}

class _PdfInlineState extends State<PdfInline> {
  List<Uint8List> _pages = const [];
  bool _failed = false;
  double _renderedWidth = 0;
  int _loadSeq = 0;

  @override
  void dispose() {
    _loadSeq++;
    super.dispose();
  }

  Future<void> _load(double width) async {
    if (width <= 0 || (_renderedWidth == width && !_failed)) {
      return;
    }
    final seq = ++_loadSeq;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    try {
      final bytes = await widget.store.read(widget.id);
      if (bytes == null || !mounted || seq != _loadSeq) {
        return;
      }
      final doc = await PdfDocument.openData(bytes);
      if (!mounted || seq != _loadSeq) {
        await doc.close();
        return;
      }
      final images = <Uint8List>[];
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        final targetWidth = width * dpr;
        final targetHeight = targetWidth * page.height / page.width;
        final rendered = await page.render(
          width: targetWidth,
          height: targetHeight,
          backgroundColor: '#FFFFFF',
          format: PdfPageImageFormat.png,
        );
        await page.close();
        if (!mounted || seq != _loadSeq) {
          await doc.close();
          return;
        }
        if (rendered != null) {
          images.add(rendered.bytes);
        }
      }
      await doc.close();
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _pages = images;
        _renderedWidth = width;
        _failed = images.isEmpty;
      });
    } catch (_) {
      if (mounted && seq == _loadSeq) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (!_failed && _pages.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _load(width));
      } else if (!_failed && _renderedWidth != width) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _load(width));
      }
      if (_failed) {
        return const SizedBox.shrink();
      }
      if (_pages.isEmpty) {
        return Container(
          height: 160,
          decoration: BoxDecoration(
            color: t.surfaceAlt,
            borderRadius: BorderRadius.circular(radiusMd),
            border: Border.all(color: t.hairline),
          ),
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final bytes in _pages)
            Padding(
              padding: const EdgeInsets.only(bottom: spaceSm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radiusSm),
                child: Image.memory(bytes,
                    fit: BoxFit.fitWidth, gaplessPlayback: true),
              ),
            ),
        ],
      );
    });
  }
}