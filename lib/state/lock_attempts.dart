import 'dart:developer' as developer;

import '../data/app_db.dart';
import '../data/password_lock.dart';

class LockVerifyResult {
  const LockVerifyResult({required this.ok, this.cooldownMs = 0});

  final bool ok;
  final int cooldownMs;
}

class LockAttempts {
  LockAttempts(this.db);

  final AppDb db;

  Future<int> cooldownRemainingMs() async {
    final until =
        int.tryParse(await db.getSetting(AppDb.lockCooldownUntilKey) ?? '') ??
            0;
    final remaining = until - db.clock();
    return remaining > 0 ? remaining : 0;
  }

  Future<LockVerifyResult> verify(PasswordLock lock, String password) async {
    final cooling = await cooldownRemainingMs();
    if (cooling > 0) {
      developer.log('skip, 密码错误次数触发冷却中, cooldownMs: $cooling');
      return LockVerifyResult(ok: false, cooldownMs: cooling);
    }
    if (lock.verify(password)) {
      await succeed();
      return const LockVerifyResult(ok: true);
    }
    final cooldown = await fail();
    return LockVerifyResult(ok: false, cooldownMs: cooldown);
  }

  Future<void> succeed() async {
    await db.setSetting(AppDb.lockFailCountKey, '0');
    developer.log('done, 密码校验通过');
  }

  Future<int> fail() async {
    final fails = (int.tryParse(
            await db.getSetting(AppDb.lockFailCountKey) ?? '') ??
        0) +
        1;
    if (fails >= AppDb.lockFailMax) {
      await db.setSetting(AppDb.lockCooldownUntilKey,
          '${db.clock() + AppDb.lockCooldownMs}');
      await db.setSetting(AppDb.lockFailCountKey, '0');
      developer.log(
          'hit, 密码连错触发冷却, fails: $fails, max: ${AppDb.lockFailMax}, cooldownMs: ${AppDb.lockCooldownMs}');
      return AppDb.lockCooldownMs;
    }
    await db.setSetting(AppDb.lockFailCountKey, '$fails');
    developer.log(
        'skip, 密码错误, fails: $fails, max: ${AppDb.lockFailMax}');
    return 0;
  }
}