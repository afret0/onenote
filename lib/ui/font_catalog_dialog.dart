import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../data/font_catalog.dart';
import '../state/app_state.dart';
import 'theme.dart';

class FontCatalogDialog extends StatefulWidget {
  const FontCatalogDialog({super.key, required this.state});

  final AppState state;

  @override
  State<FontCatalogDialog> createState() => _FontCatalogDialogState();
}

class _FontCatalogDialogState extends State<FontCatalogDialog> {
  final Map<String, int> _percent = {};
  final Set<String> _busy = {};

  bool _installed(FontCatalogEntry entry) =>
      widget.state.fonts?.fonts.any((f) => f.catalogId == entry.id) == true;

  Future<void> _download(FontCatalogEntry entry) async {
    setState(() {
      _busy.add(entry.id);
      _percent[entry.id] = 0;
    });
    try {
      await widget.state.downloadCatalogFont(entry,
          onProgress: (received, total) {
        if (!mounted || total <= 0) {
          return;
        }
        final percent = (received * 100 ~/ total).clamp(0, 100);
        if (_percent[entry.id] != percent) {
          setState(() => _percent[entry.id] = percent);
        }
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已安装 ${entry.name}，可在界面字体中选择')));
    } catch (err) {
      developer.log('fail, 在线字体下载失败, catalog: ${entry.id}, err: $err');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('下载失败：$err')));
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(entry.id);
          _percent.remove(entry.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return SimpleDialog(
      title: const Text('在线字体'),
      children: [
        for (final entry in fontCatalog)
          SimpleDialogOption(
            onPressed: _busy.contains(entry.id) || _installed(entry)
                ? null
                : () => _download(entry),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name,
                          style: Theme.of(context).textTheme.bodyMedium),
                      Text(entry.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: t.inkMuted)),
                      Text(
                          '下载约 ${(entry.downloadBytes / 1048576).toStringAsFixed(1)}MB'
                          ' · 安装后 ${(entry.installedBytes / 1048576).toStringAsFixed(1)}MB'
                          ' · ${entry.licenseName}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: t.inkMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: spaceSm),
                if (_installed(entry))
                  Icon(Icons.check, size: 18, color: t.accentText)
                else if (_busy.contains(entry.id))
                  Text('${_percent[entry.id] ?? 0}%',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.inkMuted))
                else
                  Text('下载',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: t.accentText)),
              ],
            ),
          ),
      ],
    );
  }
}