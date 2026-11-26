import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../app_version.dart';
import '../data/app_db.dart';
import '../update/update_checker.dart';
import '../update/update_installer.dart';
import 'theme.dart';

Future<void> showUpdateDialog(BuildContext context,
    {required AppDb db, required UpdateRelease release}) {
  return showDialog<void>(
    context: context,
    builder: (_) => UpdateDialog(db: db, release: release),
  );
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.db, required this.release});

  final AppDb db;
  final UpdateRelease release;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  String _current = '';
  bool _downloading = false;
  bool _cancelled = false;
  int _received = 0;
  int _total = 0;
  String? _error;

  UpdateAsset? get _asset => widget.release.assetFor(updatePlatform);

  @override
  void initState() {
    super.initState();
    _total = _asset?.size ?? 0;
    loadAppVersion().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  Future<void> _start() async {
    final asset = _asset;
    if (asset == null) return;
    setState(() {
      _downloading = true;
      _cancelled = false;
      _error = null;
      _received = 0;
    });
    try {
      final path = await downloadUpdate(asset.url, asset.name,
          onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          if (total > 0) _total = total;
        });
      }, isCancelled: () => _cancelled);
      if (!mounted) return;
      final result = await installUpdate(path);
      if (!mounted) return;
      if (result == 'need_permission') {
        setState(() {
          _downloading = false;
          _error = '已打开系统设置，请允许「安装未知应用」后重试';
        });
        return;
      }
      Navigator.of(context).pop();
    } catch (err) {
      developer.log('fail, 下载或安装更新失败, err: $err');
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = _cancelled ? null : '更新失败，可稍后重试或打开下载页';
      });
    }
  }

  Future<void> _skip() async {
    await widget.db
        .setSetting(updateSkippedVersionKey, widget.release.version);
    developer.log('done, 已跳过版本, version: ${widget.release.version}');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final release = widget.release;
    final asset = _asset;
    return AlertDialog(
      title: Text('发现新版本 v${release.version}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本 $_current'),
            if (_total > 0) Text('更新包大小 ${_mb(_total)} MB'),
            if (_downloading) ...[
              const SizedBox(height: spaceMd),
              LinearProgressIndicator(
                  value: _total > 0 ? _received / _total : null),
              const SizedBox(height: spaceSm),
              Text('${_mb(_received)} / ${_mb(_total)} MB',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.inkMuted)),
            ],
            if (_error != null) ...[
              const SizedBox(height: spaceMd),
              Text(_error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.danger)),
            ],
          ],
        ),
      ),
      actions: [
        if (_downloading)
          TextButton(
            onPressed: () {
              _cancelled = true;
              Navigator.of(context).pop();
            },
            child: const Text('取消下载'),
          )
        else ...[
          TextButton(onPressed: _skip, child: const Text('跳过此版本')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('以后再说'),
          ),
          if (asset != null)
            FilledButton(onPressed: _start, child: const Text('立即更新'))
          else
            FilledButton(
              onPressed: () {
                openExternalUrl(release.pageUrl);
                Navigator.of(context).pop();
              },
              child: const Text('打开下载页'),
            ),
        ],
      ],
    );
  }
}