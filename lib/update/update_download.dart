import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'update_checker.dart';
import 'update_installer.dart';

typedef UpdateDownloader = Future<String> Function(String url, String fileName,
    {required void Function(int received, int total) onProgress,
    required bool Function() isCancelled});

typedef ExistingDownloadCheck = Future<String?> Function(
    String fileName, int expectedSize);

class SilentUpdateDownload extends ChangeNotifier {
  SilentUpdateDownload({
    UpdateDownloader? downloader,
    ExistingDownloadCheck? existingCheck,
    bool? installSupported,
  })  : _downloader = downloader ?? downloadUpdate,
        _existingCheck = existingCheck ?? existingDownloadPath,
        _installSupported = installSupported ?? canInstallInApp;

  static SilentUpdateDownload instance = SilentUpdateDownload();

  final UpdateDownloader _downloader;
  final ExistingDownloadCheck _existingCheck;
  final bool _installSupported;

  String? version;
  UpdateAsset? asset;
  int received = 0;
  int total = 0;
  String? readyPath;
  Object? error;
  bool _cancelled = false;
  bool _running = false;
  int _generation = 0;
  Future<void>? _future;

  bool matches(UpdateRelease release) => version == release.version;

  bool get ready => readyPath != null;

  bool get downloading => _running && !ready && error == null;

  void ensureStarted(UpdateRelease release) {
    if (!_installSupported) return;
    if (matches(release) && (ready || downloading || _running)) return;
    final a = release.assetFor(updatePlatform);
    if (a == null) return;
    version = release.version;
    asset = a;
    received = 0;
    total = a.size;
    readyPath = null;
    error = null;
    _cancelled = false;
    developer.log('hit, 开始静默下载更新包, version: ${release.version}');
    _launch(a);
  }

  void _launch(UpdateAsset a) {
    final gen = ++_generation;
    _running = true;
    _future = () async {
      try {
        final existing = await _existingCheck(a.name, a.size);
        if (_generation != gen) return;
        if (existing != null) {
          readyPath = existing;
          received = a.size;
          developer.log('hit, 复用已下载更新包, path: $existing');
          return;
        }
        final path = await _downloader(a.url, a.name,
            onProgress: (r, t) {
          if (_generation != gen) return;
          received = r;
          if (t > 0) total = t;
          notifyListeners();
        }, isCancelled: () => _cancelled || _generation != gen);
        if (_generation != gen) return;
        readyPath = path;
        developer.log('done, 更新包静默下载完成, version: $version');
      } catch (err) {
        if (_generation != gen) return;
        error = err;
        developer.log('fail, 更新包静默下载失败, version: $version, err: $err');
      } finally {
        if (_generation == gen) {
          _running = false;
          notifyListeners();
        }
      }
    }();
    notifyListeners();
  }

  void restart() {
    final a = asset;
    if (a == null || _running) return;
    received = 0;
    readyPath = null;
    error = null;
    _cancelled = false;
    _launch(a);
  }

  void cancel() {
    if (version == null) return;
    _cancelled = true;
    _generation++;
    _running = false;
    version = null;
    asset = null;
    readyPath = null;
    error = null;
    received = 0;
    total = 0;
    developer.log('done, 已取消静默下载并清空任务');
    notifyListeners();
  }

  Future<String> waitReady() async {
    await _future;
    final path = readyPath;
    if (path != null) return path;
    throw error ?? StateError('更新包尚未开始下载');
  }
}