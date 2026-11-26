import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

const double _imageMinScale = 0.5;
const double _imageMaxScale = 8;

typedef AttachmentViewerAction = Future<String?> Function(String action);

Future<void> showImageViewer(
  BuildContext context, {
  required Uint8List bytes,
  required String name,
  required AttachmentViewerAction onAction,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ViewerShell(
      name: name,
      onAction: onAction,
      child: _ZoomImage(bytes: bytes),
    ),
  );
}

Future<void> showPdfViewer(
  BuildContext context, {
  required Uint8List bytes,
  required String name,
  required AttachmentViewerAction onAction,
  required VoidCallback onOpenExternal,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ViewerShell(
      name: name,
      onAction: onAction,
      child: _PdfPages(bytes: bytes, onOpenExternal: onOpenExternal),
    ),
  );
}

class _ViewerShell extends StatefulWidget {
  const _ViewerShell({
    required this.name,
    required this.onAction,
    required this.child,
  });

  final String name;
  final AttachmentViewerAction onAction;
  final Widget child;

  @override
  State<_ViewerShell> createState() => _ViewerShellState();
}

class _ViewerShellState extends State<_ViewerShell> {
  String? _toast;
  Timer? _toastTimer;
  bool _busy = false;

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _toast = null);
      }
    });
  }

  Future<void> _run(String action) async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      final message = await widget.onAction(action);
      if (!mounted || message == null) {
        return;
      }
      if (action == 'delete' && message == '已删除') {
        Navigator.of(context).pop();
        return;
      }
      _showToast(message);
    } finally {
      _busy = false;
    }
  }

  Future<void> _menu(Offset position) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(value: 'save', child: Text('另存为')),
        PopupMenuItem(value: 'copy', child: Text('复制')),
        PopupMenuItem(
            value: 'delete',
            child: Text('删除', style: TextStyle(color: Color(0xFFE57373)))),
      ],
    );
    if (value != null && mounted) {
      await _run(value);
    }
  }

  Widget _button(IconData icon, String label, VoidCallback onPressed,
      {Color color = Colors.white}) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onPressed,
        iconSize: 22,
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(color),
          backgroundColor:
              WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.08)),
          mouseCursor:
              const WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
        icon: Icon(icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onSecondaryTapUp: (d) => _menu(d.globalPosition),
                  onLongPressStart: (d) => _menu(d.globalPosition),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                    child: widget.child,
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 24,
                right: 24,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                    ),
                    _button(Icons.download_outlined, '另存为',
                        () => _run('save')),
                    const SizedBox(width: 8),
                    _button(Icons.copy_outlined, '复制', () => _run('copy')),
                    const SizedBox(width: 8),
                    _button(Icons.delete_outline, '删除',
                        () => _run('delete'),
                        color: const Color(0xFFE57373)),
                    const SizedBox(width: 8),
                    _button(Icons.close, '关闭',
                        () => Navigator.of(context).maybePop()),
                  ],
                ),
              ),
              if (_toast != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 40,
                  child: Center(
                    child: Material(
                      color: const Color(0xE6303034),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Text(_toast!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomImage extends StatefulWidget {
  const _ZoomImage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200));
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapFocus = Offset.zero;

  @override
  void initState() {
    super.initState();
    _zoomAnim.addListener(() {
      final tween = _zoomTween;
      if (tween != null) {
        _transform.value = tween.value;
      }
    });
  }

  @override
  void dispose() {
    _zoomAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _scaleAround(Offset focal, double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next =
        (current * factor).clamp(_imageMinScale, _imageMaxScale).toDouble();
    if (next == current) {
      return;
    }
    final ratio = next / current;
    final matrix = _transform.value.clone()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    _transform.value = matrix;
  }

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
    _zoomAnim
      ..stop()
      ..reset()
      ..forward();
  }

  void _toggleZoom() {
    final current = _transform.value.getMaxScaleOnAxis();
    if (current > 1.01) {
      _animateTo(Matrix4.identity());
      return;
    }
    final focal = _doubleTapFocus;
    final target = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          _scaleAround(signal.localPosition, signal.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: (d) => _doubleTapFocus = d.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: _imageMinScale,
          maxScale: _imageMaxScale,
          child: Center(
            child: Image.memory(widget.bytes,
                fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
      ),
    );
  }
}

class _PdfPages extends StatefulWidget {
  const _PdfPages({required this.bytes, required this.onOpenExternal});

  final Uint8List bytes;
  final VoidCallback onOpenExternal;

  @override
  State<_PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends State<_PdfPages> {
  late final PdfControllerPinch _controller = PdfControllerPinch(
    document: PdfDocument.openData(widget.bytes),
  );
  int _page = 1;
  bool _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fallback() {
    if (_failed) {
      return;
    }
    _failed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      widget.onOpenExternal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = _controller.pagesCount ?? 0;
    return Stack(
      children: [
        Positioned.fill(
          child: PdfViewPinch(
            controller: _controller,
            onPageChanged: (page) => setState(() => _page = page),
            onDocumentError: (_) => _fallback(),
            builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              documentLoaderBuilder: (_) => const Center(
                  child: CircularProgressIndicator(color: Colors.white70)),
              errorBuilder: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        if (pages > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: Text('$_page/$pages',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ),
      ],
    );
  }
}