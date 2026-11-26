import 'dart:developer' as developer;
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class BackgroundLock {
  BackgroundLock._(this._onBackground);

  final void Function() _onBackground;
  JSFunction? _listener;

  static BackgroundLock install(
      void Function() onBackground, void Function() onBlur) {
    final lock = BackgroundLock._(onBackground);
    lock._listener = ((web.Event event) {
      if (web.document.visibilityState == 'hidden') {
        developer.log('hit, 标签页切走触发锁定');
        lock._onBackground();
      }
    }).toJS;
    web.document.addEventListener('visibilitychange', lock._listener);
    developer.log('done, web 标签页可见性锁定监听已安装');
    return lock;
  }

  void dispose() {
    final listener = _listener;
    if (listener != null) {
      web.document.removeEventListener('visibilitychange', listener);
    }
  }
}