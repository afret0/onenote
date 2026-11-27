import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../app_version.dart';
import '../data/app_db.dart';
import '../update/update_checker.dart';
import '../update/update_download.dart';
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

  static Future<String> Function(String path)? installOverride;

  final AppDb db;
  final UpdateRelease release;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  String _current = '';
  bool _downloading = false;
  bool _cancelled = false;
  bool _installing = false;
  int _received = 0;
  int _total = 0;
  String? _error;

  SilentUpdateDownload get _silent => SilentUpdateDownload.instance;

  bool get _hasSilent => _silent.matches(widget.release) && _silent.asset != null;

  UpdateAsset? get _asset => widget.release.assetFor(updatePlatform);

  @override
  void initState() {
    super.initState();
    _total = _asset?.size ?? 0;
    _silent.addListener(_onSilent);
    loadAppVersion().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  @override
  void dispose() {
    _silent.removeListener(_onSilent);
    super.dispose();
  }

  void _onSilent() {
    if (mounted && _silent.matches(widget.release)) setState(() {});
  }

  String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  Future<void> _install(String path) async {
    final install = UpdateDialog.installOverride ?? installUpdate;
    final result = await install(path);
    if (!mounted) return;
    if (result == 'need_permission') {
      setState(() {
        _downloading = false;
        _installing = false;
        _error = '已打开系统设置，请允许「安装未知应用」后重试';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _start() async {
    final asset = _asset;
    if (asset == null || _installing) return;
    setState(() {
      _error = null;
      _installing = true;
    });
    try {
      if (_hasSilent) {
        if (_silent.error != null) _silent.restart();
        final path = await _silent.waitReady();
        if (!mounted) return;
        await _install(path);
        if (mounted) setState(() => _installing = false);
        return;
      }
      setState(() {
        _downloading = true;
        _cancelled = false;
        _received = 0;
      });
      final path = await downloadUpdate(asset.url, asset.name,
          onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          if (total > 0) _total = total;
        });
      }, isCancelled: () => _cancelled);
      if (!mounted) return;
      await _install(path);
      if (mounted) setState(() => _installing = false);
    } catch (err) {
      developer.log('fail, 下载或安装更新失败, err: $err');
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = false;
        _error = _cancelled ? null : '更新失败，可稍后重试或打开下载页';
      });
    }
  }

  Future<void> _skip() async {
    await widget.db
        .setSetting(updateSkippedVersionKey, widget.release.version);
    if (_hasSilent) _silent.cancel();
    developer.log('done, 已跳过版本, version: ${widget.release.version}');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final release = widget.release;
    final asset = _asset;
    final silent = _hasSilent;
    final downloading = silent ? _silent.downloading : _downloading;
    final received = silent ? _silent.received : _received;
    final total = silent && _silent.total > 0 ? _silent.total : _total;
    return AlertDialog(
      title: Text('发现新版本 v${release.version}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本 $_current'),
            if (total > 0) Text('更新包大小 ${_mb(total)} MB'),
            if (downloading) ...[
              const SizedBox(height: spaceMd),
              LinearProgressIndicator(
                  value: total > 0 ? received / total : null),
              const SizedBox(height: spaceSm),
              Text('${_mb(received)} / ${_mb(total)} MB',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.inkMuted)),
            ],
            if (silent && _silent.ready) ...[
              const SizedBox(height: spaceMd),
              Text('更新包已下载完成，点击立即更新直接安装',
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
        if (!silent && _downloading)
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
            FilledButton(
                onPressed: _installing ? null : _start,
                child: const Text('立即更新'))
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