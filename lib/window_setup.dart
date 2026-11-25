import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:nativeapi/nativeapi.dart' as na;
import 'package:window_manager/window_manager.dart';

import 'data/app_db.dart';
import 'window_metrics.dart';

const windowResizeSaveDelay = Duration(milliseconds: 800);

bool get isDesktopWindow =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

class WindowSizeController {
  WindowSizeController(this.db);

  final AppDb db;
  Window? _window;
  ListenerId? _listenerId;
  Timer? _saveTimer;
  Size? _lastKnownSize;

  Future<void> init() async {
    final all = WindowManager.instance.getAll();
    final window = WindowManager.instance.getCurrent() ??
        (all.isEmpty ? null : all.first);
    final display = na.DisplayManager.instance.getPrimary();
    if (window == null || display == null) {
      developer.log(
          'fail, 取不到窗口或主显示器, windowCount: ${all.length}, hasDisplay: ${display != null}');
      for (final candidate in all) {
        candidate.show();
        candidate.dispose();
      }
      return;
    }
    _window = window;
    final workArea = display.workArea;
    display.dispose();
    final screen = Size(workArea.width, workArea.height);
    final saved = parseWindowSize(await db.getSetting(windowSizeSettingKey));
    final target = saved == null
        ? scaledDefaultWindowSize(screen)
        : fitWindowSize(saved, screen);
    final originX = workArea.x + (workArea.width - target.width) / 2;
    final originY = workArea.y + (workArea.height - target.height) / 2;
    developer.log(
        'hit, 启动窗口尺寸, screen: $screen, saved: $saved, target: $target, originX: $originX, originY: $originY');
    window.bounds = na.Rectangle(
        x: originX, y: originY, width: target.width, height: target.height);
    window.show();
    window.focus();
    _lastKnownSize = target;
    _listenerId = window.addListener(_onWindowEvent);
  }

  void dispose() {
    _saveTimer?.cancel();
    final window = _window;
    final listenerId = _listenerId;
    if (window != null && listenerId != null) {
      window.removeListener(listenerId);
    }
    window?.dispose();
  }

  void _onWindowEvent(WindowEvent event) {
    if (event is WindowResizedEvent ||
        event is WindowRestoredEvent ||
        event is WindowExitedFullScreenEvent) {
      _scheduleSave();
    } else if (event is WindowMaximizedEvent ||
        event is WindowMinimizedEvent ||
        event is WindowEnteredFullScreenEvent) {
      _saveTimer?.cancel();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(windowResizeSaveDelay, _saveSize);
  }

  Future<void> _saveSize() async {
    final window = _window;
    if (window == null) return;
    final maximized = window.isMaximized;
    final minimized = window.isMinimized;
    final fullScreen = window.isFullScreen;
    if (maximized || minimized || fullScreen) {
      developer.log(
          'skip, 特殊窗口状态不记尺寸, maximized: $maximized, minimized: $minimized, fullScreen: $fullScreen');
      return;
    }
    final size = window.size.toSize();
    if (size == _lastKnownSize) {
      developer.log('skip, 窗口尺寸未变化不落库, size: $size');
      return;
    }
    _lastKnownSize = size;
    await db.setSetting(windowSizeSettingKey, formatWindowSize(size));
    developer.log('done, 记录窗口尺寸, size: $size');
  }
}
