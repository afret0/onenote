import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

class BackgroundLock with WidgetsBindingObserver {
  BackgroundLock._(this._onBackground, this._onBlur);

  final void Function() _onBackground;
  final void Function() _onBlur;
  Window? _window;
  ListenerId? _listenerId;

  static BackgroundLock install(
      void Function() onBackground, void Function() onBlur) {
    final lock = BackgroundLock._(onBackground, onBlur);
    WidgetsBinding.instance.addObserver(lock);
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final window = WindowManager.instance.getCurrent();
      if (window != null) {
        lock._window = window;
        lock._listenerId = window.addListener(lock._onWindowEvent);
        developer.log('done, 桌面失焦锁定监听已安装');
      } else {
        developer.log('skip, 取不到窗口句柄只装生命周期监听');
      }
    }
    return lock;
  }

  void _onWindowEvent(WindowEvent event) {
    if (event is WindowBlurredEvent) {
      developer.log('hit, 窗口失焦触发失焦锁定');
      _onBlur();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      developer.log('hit, 应用退后台触发锁定, state: ${state.name}');
      _onBackground();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final window = _window;
    final listenerId = _listenerId;
    if (window != null && listenerId != null) {
      window.removeListener(listenerId);
    }
  }
}