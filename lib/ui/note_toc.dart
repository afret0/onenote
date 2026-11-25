import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart'
    show MarkdownTocEntry;

import 'theme.dart';

const noteTocWidth = 240.0;
const noteTocMaxLevel = 3;
const noteTocRevealOffset = 96.0;
const _rowMinHeight = 40.0;

List<MarkdownTocEntry> noteTocVisibleEntries(List<MarkdownTocEntry> entries) =>
    entries.where((e) => e.level <= noteTocMaxLevel).toList();

class NoteTocPanel extends StatefulWidget {
  const NoteTocPanel({
    super.key,
    required this.entries,
    required this.activeIndex,
    required this.onTap,
    this.tint,
  });

  final List<MarkdownTocEntry> entries;
  final int activeIndex;
  final void Function(MarkdownTocEntry entry) onTap;
  final Color? tint;

  @override
  State<NoteTocPanel> createState() => _NoteTocPanelState();
}

class _NoteTocPanelState extends State<NoteTocPanel> {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _rowKeys = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _revealActive(animated: false));
  }

  @override
  void didUpdateWidget(NoteTocPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _rowKey(int index) {
    while (_rowKeys.length <= index) {
      _rowKeys.add(GlobalKey());
    }
    return _rowKeys[index];
  }

  void _revealActive({bool animated = true}) {
    if (!mounted || !_scroll.hasClients) return;
    final index = widget.activeIndex;
    if (index < 0 || index >= _rowKeys.length) return;
    final rowContext = _rowKeys[index].currentContext;
    if (rowContext == null) return;
    final box = rowContext.findRenderObject();
    if (box == null || !box.attached) return;
    final position = _scroll.position;
    final viewport = RenderAbstractViewport.of(box);
    final revealTop = viewport.getOffsetToReveal(box, 0.0).offset;
    final revealBottom = viewport.getOffsetToReveal(box, 1.0).offset;
    var target = position.pixels;
    if (revealTop < position.pixels) {
      target = revealTop;
    } else if (revealBottom > position.pixels) {
      target = revealBottom;
    }
    target =
        target.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    if (target == position.pixels) return;
    if (animated) {
      position.animateTo(target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    } else {
      position.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(spaceMd, spaceMd, spaceMd, spaceSm),
          child: Text('目录',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: t.inkMuted,
                    fontWeight: FontWeight.w600,
                  )),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(spaceSm, 0, spaceSm, spaceMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.entries.length; i++)
                  KeyedSubtree(
                    key: _rowKey(i),
                    child: NoteTocRow(
                      entry: widget.entries[i],
                      active: i == widget.activeIndex,
                      tint: widget.tint,
                      onTap: () => widget.onTap(widget.entries[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class NoteTocRow extends StatelessWidget {
  const NoteTocRow({
    super.key,
    required this.entry,
    required this.active,
    required this.onTap,
    this.tint,
  });

  final MarkdownTocEntry entry;
  final bool active;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final level = entry.level.clamp(1, noteTocMaxLevel);
    final fontSize = (level == 1 ? 14.0 : 13.0) * t.fontScale;
    final activeText = tint == null
        ? t.accentText
        : readableOn(tint!, t.surfaceAlt);
    final activeBar = tint == null
        ? t.accent
        : readableOn(tint!, t.surfaceAlt, ratio: 3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active ? t.surfaceAlt : Colors.transparent,
        borderRadius: BorderRadius.circular(radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusSm),
          overlayColor:
              WidgetStatePropertyAll(t.ink.withValues(alpha: 0.05)),
          onTap: onTap,
          child: Stack(
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: _rowMinHeight),
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.fromLTRB(12.0 + (level - 1) * 14.0, 6, 12, 6),
                child: Text(
                  entry.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.sans,
                    fontFamilyFallback: cjkSansFallback,
                    fontSize: fontSize,
                    height: 1.5,
                    color: active
                        ? activeText
                        : (level == 1 ? t.ink : t.inkMuted),
                    fontWeight: active
                        ? FontWeight.w600
                        : (level == 1 ? FontWeight.w500 : FontWeight.w400),
                  ),
                ),
              ),
              if (active)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 3,
                      height: 20,
                      decoration: BoxDecoration(
                        color: activeBar,
                        borderRadius: BorderRadius.circular(2),
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

Future<void> showNoteTocSheet(
  BuildContext context, {
  required List<MarkdownTocEntry> entries,
  required int activeIndex,
  required void Function(MarkdownTocEntry entry) onSelect,
  Color? tint,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: inkOf(context).surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6),
        child: NoteTocPanel(
          entries: entries,
          activeIndex: activeIndex,
          tint: tint,
          onTap: (entry) {
            Navigator.of(sheetContext).pop();
            onSelect(entry);
          },
        ),
      ),
    ),
  );
}