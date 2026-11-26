import 'dart:developer' as developer;

class BackgroundLock {
  BackgroundLock._();

  static BackgroundLock install(
      void Function() onBackground, void Function() onBlur) {
    developer.log('skip, 当前平台无后台锁定实现');
    return BackgroundLock._();
  }

  void dispose() {}
}