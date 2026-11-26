import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/password_lock.dart';

void main() {
  test('create 存密码长度且 JSON roundtrip 保留', () {
    final lock = PasswordLock.create('pw-12345', 1000);
    expect(lock.len, 'pw-12345'.length);
    final back = PasswordLock.fromJson(
        jsonDecode(lock.encode()) as Map<String, dynamic>);
    expect(back.len, lock.len);
    expect(back.verify('pw-12345'), isTrue);
    expect(back.verify('pw-12346'), isFalse);
  });

  test('中文密码长度按输入框口径计', () {
    const password = '密码一二三';
    final lock = PasswordLock.create(password, 1000);
    expect(lock.len, password.length);
    expect(lock.verify(password), isTrue);
  });

  test('旧锁无 len 读作 0 且序列化不带 len', () {
    final lock = PasswordLock.create('pw', 1000);
    final legacy = jsonDecode(lock.encode()) as Map<String, dynamic>
      ..remove('len');
    final back = PasswordLock.fromJson(legacy);
    expect(back.len, 0);
    expect(back.verify('pw'), isTrue);
    expect(back.toJson().containsKey('len'), isFalse);
  });

  test('隐私空间注册表内嵌锁携带 len', () {
    final ref = PrivacySpaceRef(
        id: 'space-1',
        lock: PasswordLock.create('secret-pass', 2000),
        createAt: 2000);
    final back = PrivacySpaceRef.parse(ref.encode())!;
    expect(back.lock.len, 'secret-pass'.length);
    expect(back.lock.verify('secret-pass'), isTrue);
  });
}