import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../data/password_lock.dart';

const silentVerifyDebounce = Duration(milliseconds: 350);

Future<bool> silentVerify(PasswordLock lock, String value) {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
    return Future.value(lock.verify(value));
  }
  return Isolate.run(() => lock.verify(value));
}