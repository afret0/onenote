import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class Biometrics {
  static final LocalAuthentication _auth = LocalAuthentication();

  static bool get supported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isAndroid ||
          Platform.isIOS);

  static Future<bool> available() async {
    if (!supported) {
      return false;
    }
    try {
      final can = await _auth.canCheckBiometrics;
      final device = await _auth.isDeviceSupported();
      developer.log(
          'done, 生物识别可用性, canCheck: $can, deviceSupported: $device');
      return can || device;
    } catch (err) {
      developer.log('skip, 生物识别探测失败视为不可用, err: $err');
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    if (!supported) {
      developer.log('skip, 当前平台无生物识别实现');
      return false;
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
      );
      developer.log('done, 生物识别结果, ok: $ok');
      return ok;
    } catch (err) {
      developer.log('skip, 生物识别调用失败回退密码, err: $err');
      return false;
    }
  }
}