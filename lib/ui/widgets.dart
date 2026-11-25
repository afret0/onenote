import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_db.dart';
import 'theme.dart';

String noteDisplayTitle(Note note) =>
    note.title.trim().isEmpty ? '无标题' : note.title.trim();

String formatDateTime(int ms) =>
    DateFormat('yyyy-MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));

String formatRelative(int ms) {
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60000) {
    return '刚刚';
  }
  if (diff < 3600000) {
    return '${diff ~/ 60000} 分钟前';
  }
  if (diff < 86400000) {
    return '${diff ~/ 3600000} 小时前';
  }
  if (diff < 7 * 86400000) {
    return '${diff ~/ 86400000} 天前';
  }
  return DateFormat('yyyy-MM-dd')
      .format(DateTime.fromMillisecondsSinceEpoch(ms));
}

String notePreview(String content) {
  final lines = content
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*[#>*\-\d.]+\s*'), '').trim())
      .where((l) => l.isNotEmpty);
  return lines.take(3).join(' ');
}

Color notebookTint(BuildContext context, Color color, double level) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final alpha = dark ? 0.16 + 0.10 * level : 0.10 + 0.08 * level;
  return Color.alphaBlend(
      color.withValues(alpha: alpha), inkOf(context).surface);
}

Color notebookTintBorder(BuildContext context, Color color, double level) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return color.withValues(alpha: (dark ? 0.45 : 0.40) + 0.25 * level);
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/images/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class ScopeTile extends StatelessWidget {
  const ScopeTile({
    super.key,
    this.icon,
    this.dotColor,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onContext,
  });

  final IconData? icon;
  final Color? dotColor;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onContext;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final base = dotColor == null
        ? null
        : notebookTint(context, dotColor!, selected ? 2 : 0);
    return AnimatedContainer(
      duration: motionFast,
      curve: motionCurve,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: base ?? (selected ? t.accentSoft : Colors.transparent),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: GestureDetector(
        onLongPressStart: onContext == null
            ? null
            : (details) => onContext!(details.globalPosition),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radiusMd),
            overlayColor: dotColor == null
                ? null
                : WidgetStatePropertyAll(
                    dotColor!.withValues(alpha: 0.10)),
            onTap: onTap,
            onSecondaryTapUp: onContext == null
                ? null
                : (details) => onContext!(details.globalPosition),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  if (dotColor != null)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: 18,
                      color: selected ? t.accent : t.inkMuted,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? t.ink : t.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.onContext,
    this.tintColor,
    this.highlight,
    this.selected = false,
    this.dense = false,
  });

  final Note note;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onContext;
  final Color? tintColor;
  final String? highlight;
  final bool selected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final title = note.title.trim().isEmpty ? '无标题' : note.title.trim();
    final tint = tintColor == null
        ? null
        : notebookTint(context, tintColor!, selected ? 2 : 0);
    return GestureDetector(
      onLongPressStart: onContext == null
          ? null
          : (details) => onContext!(details.globalPosition),
      child: Material(
        color: tint ?? (selected ? t.accentSoft : t.surface),
        borderRadius: BorderRadius.circular(radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusMd),
          overlayColor: tintColor == null
              ? null
              : WidgetStatePropertyAll(
                  tintColor!.withValues(alpha: 0.10)),
          onTap: onTap,
          onSecondaryTapUp: onContext == null
              ? null
              : (details) => onContext!(details.globalPosition),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radiusMd),
              border: Border.all(
                color: tintColor != null
                    ? notebookTintBorder(context, tintColor!, selected ? 1 : 0)
                    : selected
                        ? t.accent
                        : t.hairline,
              ),
            ),
            padding: dense
                ? const EdgeInsets.fromLTRB(spaceMd, spaceSm, spaceMd, spaceSm)
                : const EdgeInsets.all(spaceMd),
            child: HighlightText(
              text: title,
              needle: highlight,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(letterSpacing: -0.1),
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class HighlightText extends StatelessWidget {
  const HighlightText({
    super.key,
    required this.text,
    required this.style,
    required this.maxLines,
    this.needle,
  });

  final String text;
  final String? needle;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final query = needle?.toLowerCase() ?? '';
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    var start = 0;
    while (true) {
      final index = lower.indexOf(query, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            color: t.accentText,
            fontWeight: FontWeight.w700,
            backgroundColor: t.accentSoft,
          ),
        ),
      );
      start = index + query.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.searching,
    required this.isTrash,
    required this.onNew,
  });

  final bool searching;
  final bool isTrash;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final message = searching
        ? '没有匹配的笔记'
        : isTrash
        ? '回收站是空的'
        : '还没有笔记，写下第一条吧';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.9,
            child: Image.asset(
              'assets/images/logo.png',
              width: 72,
              height: 72,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(height: spaceMd),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: t.inkMuted),
          ),
          if (!searching && !isTrash) ...[
            const SizedBox(height: spaceMd),
            FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('新建笔记'),
            ),
          ],
        ],
      ),
    );
  }
}
