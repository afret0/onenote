import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_db.dart';
import 'theme.dart';

String noteDisplayTitle(Note note) =>
    note.title.trim().isEmpty ? '无标题' : note.title.trim();

String formatDateTime(int ms) =>
    DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));

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
  return DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(ms));
}

String notePreview(String content) {
  final lines = content
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*[#>*\-\d.]+\s*'), '').trim())
      .where((l) => l.isNotEmpty);
  return lines.take(3).join(' ');
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset('assets/images/logo.png',
          width: size, height: size, filterQuality: FilterQuality.medium),
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
    this.trailing,
  });

  final IconData? icon;
  final Color? dotColor;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return AnimatedContainer(
      duration: motionFast,
      curve: motionCurve,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: selected ? t.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                if (dotColor != null)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                        color: dotColor, shape: BoxShape.circle),
                  )
                else
                  Icon(icon,
                      size: 18,
                      color: selected ? t.accent : t.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? t.ink : t.inkMuted,
                        ),
                  ),
                ),
                ?trailing,
              ],
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
    required this.notebookName,
    required this.notebookColor,
    required this.onTap,
    this.highlight,
    this.selected = false,
    this.dense = false,
  });

  final Note note;
  final String notebookName;
  final Color notebookColor;
  final VoidCallback onTap;
  final String? highlight;
  final bool selected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final title = note.title.trim().isEmpty ? '无标题' : note.title.trim();
    final preview = notePreview(note.content);
    return Material(
      color: selected ? t.accentSoft : t.surface,
      borderRadius: BorderRadius.circular(radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusMd),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radiusMd),
            border: Border.all(color: selected ? t.accent : t.hairline),
          ),
          padding: dense
              ? const EdgeInsets.fromLTRB(spaceMd, spaceSm, spaceMd, spaceSm)
              : const EdgeInsets.all(spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HighlightText(
                text: title,
                needle: highlight,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(letterSpacing: -0.1),
                maxLines: 1,
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: spaceXs),
                _HighlightText(
                  text: preview,
                  needle: highlight,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.inkMuted),
                  maxLines: dense ? 1 : 2,
                ),
              ],
              SizedBox(height: dense ? 6 : 10),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: notebookColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(notebookName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                  const Spacer(),
                  Text(formatRelative(note.updateAt),
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightText extends StatelessWidget {
  const _HighlightText({
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
      return Text(text,
          maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
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
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
            color: t.accentText,
            fontWeight: FontWeight.w700,
            backgroundColor: t.accentSoft),
      ));
      start = index + query.length;
    }
    return Text.rich(TextSpan(children: spans),
        maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
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
            child: Image.asset('assets/images/logo.png',
                width: 72, height: 72, filterQuality: FilterQuality.medium),
          ),
          const SizedBox(height: spaceMd),
          Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: t.inkMuted)),
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