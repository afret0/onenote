import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

class AppFocus {
  static bool? debugForeground;
  static final List<void Function()> _debugWaiters = [];

  static void debugReturnToForeground() {
    debugForeground = true;
    final waiters = List<void Function()>.of(_debugWaiters);
    _debugWaiters.clear();
    for (final waiter in waiters) {
      waiter();
    }
  }

  static bool get _desktop =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static bool get _testMode =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static bool get _lifecycleForeground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
  }

  static bool get inForeground {
    final override = debugForeground;
    if (override != null) {
      return override;
    }
    if (kIsWeb) {
      return true;
    }
    if (_testMode) {
      return _lifecycleForeground;
    }
    if (_desktop) {
      try {
        final window = WindowManager.instance.getCurrent();
        if (window != null) {
          return window.isFocused;
        }
      } catch (err) {
        developer.log('skip, 读窗口焦点失败视为前台, err: $err');
      }
      return true;
    }
    return _lifecycleForeground;
  }

  static ForegroundWait waitUntilForeground() {
    final completer = Completer<void>();
    if (inForeground) {
      completer.complete();
      return ForegroundWait._(null, completer);
    }
    if (debugForeground != null) {
      void waiter() {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      _debugWaiters.add(waiter);
      developer.log('done, 已挂起等待应用回到前台(测试缝)');
      return ForegroundWait._(() => _debugWaiters.remove(waiter), completer);
    }
    final waiter = _FocusWaiter(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }, desktop: _desktop);
    if (!waiter.armed || inForeground) {
      waiter.dispose();
      if (!completer.isCompleted) {
        completer.complete();
      }
      return ForegroundWait._(null, completer);
    }
    developer.log('done, 已挂起等待应用回到前台');
    return ForegroundWait._(waiter.dispose, completer);
  }
}

class ForegroundWait {
  ForegroundWait._(this._cancel, this._completer);

  final void Function()? _cancel;
  final Completer<void> _completer;

  Future<void> get done => _completer.future;

  void cancel() {
    _cancel?.call();
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

class _FocusWaiter with WidgetsBindingObserver {
  _FocusWaiter(this._onForeground, {required bool desktop}) {
    if (desktop) {
      Window? window;
      try {
        window = WindowManager.instance.getCurrent();
      } catch (err) {
        developer.log('skip, 取窗口句柄失败无法等焦点, err: $err');
      }
      _window = window;
      final w = window;
      if (w != null) {
        _listenerId = w.addListener(_onWindowEvent);
      }
    } else {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  final void Function() _onForeground;
  Window? _window;
  ListenerId? _listenerId;
  bool _observing = false;
  bool _fired = false;

  bool get armed => _window != null || _observing;

  void _onWindowEvent(WindowEvent event) {
    if (event is WindowFocusedEvent) {
      _fire();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fire();
    }
  }

  void _fire() {
    if (_fired) {
      return;
    }
    _fired = true;
    developer.log('hit, 应用回到前台');
    dispose();
    _onForeground();
  }

  void dispose() {
    final w = _window;
    final id = _listenerId;
    if (w != null && id != null) {
      w.removeListener(id);
      _listenerId = null;
    }
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }
}