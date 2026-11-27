import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../data/password_lock.dart';
import '../lock/biometrics.dart';
import '../lock/silent_verify.dart';
import '../state/lock_attempts.dart';
import '../sync/sync_engine.dart';
import 'password_field.dart';
import 'theme.dart';

class LockGate extends StatefulWidget {
  const LockGate(
      {super.key,
      required this.globalDb,
      required this.onUnlocked,
      this.forcePassword = false});

  final AppDb globalDb;
  final void Function(AppDb db, String? spaceId) onUnlocked;
  final bool forcePassword;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  final _controller = MaskedPasswordController();
  final _focus = FocusNode();
  bool _preparing = true;
  bool _obscure = true;
  bool _busy = false;
  bool _bioAvailable = false;
  String? _error;
  int _cooldownMs = 0;
  List<PasswordLock> _autoLocks = [];
  Timer? _cooldownTimer;
  Timer? _autoTimer;
  late final LockAttempts _rootAttempts;

  @override
  void initState() {
    super.initState();
    _rootAttempts = LockAttempts(widget.globalDb);
    _prepare();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _autoTimer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final engine = SyncEngine(widget.globalDb);
    await engine.syncLockMarkers();
    engine.dispose();
    if (!mounted) {
      return;
    }
    final lock =
        PasswordLock.parse(await widget.globalDb.getSetting(AppDb.appLockKey));
    if (lock == null || !lock.active) {
      developer.log('hit, 未设置 App 密码直接进入');
      widget.onUnlocked(widget.globalDb, null);
      return;
    }
    if (!widget.forcePassword &&
        Biometrics.systemAppLockSupported &&
        await widget.globalDb.getSetting(AppDb.trustSystemLockKey) == '1') {
      await _enterTrustedSpace();
      return;
    }
    final bioEnabled =
        await widget.globalDb.getSetting(AppDb.lockBioKey) != '0';
    final bio = bioEnabled && await Biometrics.available();
    final autoBio =
        !widget.forcePassword && bio && await Biometrics.hasEnrolledBiometrics();
    final cooling = await _rootAttempts.cooldownRemainingMs();
    final autoLocks = await _collectAutoLocks();
    if (!mounted) {
      return;
    }
    setState(() {
      _preparing = false;
      _autoLocks = autoLocks;
      _bioAvailable = bio;
      if (cooling > 0) {
        _startCooldown(cooling);
      }
    });
    developer.log(
        'done, 锁屏就绪, bioAvailable: $bio, autoBio: $autoBio, cooldownMs: $cooling');
    if (autoBio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          developer.log('hit, 已录入生物识别自动弹出认证');
          _bioUnlock();
        }
      });
    }
  }

  Future<List<PasswordLock>> _collectAutoLocks() async {
    final locks = <PasswordLock>[];
    final root =
        PasswordLock.parse(await widget.globalDb.getSetting(AppDb.appLockKey));
    if (root != null && root.active) {
      locks.add(root);
    }
    final ref = PrivacySpaceRef.parse(
        await widget.globalDb.getSetting(AppDb.privacySpaceKey));
    if (ref != null && ref.active) {
      locks.add(ref.lock);
    }
    developer.log('done, 自动解锁候选锁数: ${locks.length}');
    return locks;
  }

  void _autoSubmit(String value) {
    _autoTimer?.cancel();
    if (_busy || _preparing || _cooldownMs > 0 || value.isEmpty) {
      return;
    }
    final matched =
        _autoLocks.where((lock) => lock.len == value.length).toList();
    for (final lock in matched) {
      if (lock.verify(value)) {
        developer.log('hit, 静默校验通过自动提交, len: ${value.length}');
        _submit();
        return;
      }
    }
    if (matched.isNotEmpty) {
      developer.log('skip, 长度达标静默校验未通过, len: ${value.length}');
    }
    final rest =
        _autoLocks.where((lock) => lock.len != value.length).toList();
    if (rest.isEmpty) {
      return;
    }
    _autoTimer = Timer(silentVerifyDebounce, () => _autoFallback(value, rest));
  }

  Future<void> _autoFallback(
      String value, List<PasswordLock> locks) async {
    if (_busy || _preparing || _cooldownMs > 0 || value != _controller.text) {
      return;
    }
    for (final lock in locks) {
      final ok = await silentVerify(lock, value);
      if (!mounted ||
          _busy ||
          _cooldownMs > 0 ||
          value != _controller.text) {
        return;
      }
      if (ok) {
        developer.log('hit, 停笔兜底静默校验通过自动提交, len: ${value.length}');
        _submit();
        return;
      }
    }
    developer.log('skip, 停笔兜底静默校验未通过, len: ${value.length}');
  }

  Future<void> _backfillLen(
      AppDb db, AppDb? parent, PasswordLock lock, String password) async {
    final filled = PasswordLock(
        salt: lock.salt,
        hash: lock.hash,
        updateAt: db.clock(),
        len: password.length);
    await db.setSetting(AppDb.appLockKey, filled.encode());
    if (parent != null) {
      final ref = PrivacySpaceRef.parse(
          await parent.getSetting(AppDb.privacySpaceKey));
      if (ref != null && ref.active) {
        await parent.setSetting(
            AppDb.privacySpaceKey,
            PrivacySpaceRef(
                    id: ref.id, lock: filled, createAt: ref.createAt)
                .encode());
      }
    }
    developer.log('done, 旧锁缺长度已补记, len: ${password.length}');
  }

  void _startCooldown(int ms) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownMs = ms;
      _error = null;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownMs -= 1000;
        if (_cooldownMs <= 0) {
          _cooldownMs = 0;
          timer.cancel();
          _focus.requestFocus();
        }
      });
    });
  }

  Future<void> _submit() async {
    if (_busy || _cooldownMs > 0 || _preparing) {
      return;
    }
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      _focus.requestFocus();
      return;
    }
    final cooling = await _rootAttempts.cooldownRemainingMs();
    if (cooling > 0) {
      developer.log('skip, 冷却期内拒绝提交, cooldownMs: $cooling');
      if (mounted) {
        _startCooldown(cooling);
      }
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final opened = <AppDb>[];
    try {
      var db = widget.globalDb;
      String? spaceId;
      AppDb? parent;
      for (var depth = 0; depth < 16; depth++) {
        final lock =
            PasswordLock.parse(await db.getSetting(AppDb.appLockKey));
        final matched =
            lock != null && lock.active && lock.verify(password);
        if (lock == null || !lock.active || matched) {
          if (matched && lock.len == 0) {
            try {
              await _backfillLen(db, parent, lock, password);
            } catch (err) {
              developer.log('fail, 补记密码长度失败不阻塞解锁, err: $err');
            }
          }
          developer.log(
              'done, 密码解锁成功, spaceId: ${spaceId ?? ''}, depth: $depth');
          await _enter(db, spaceId, opened);
          return;
        }
        final ref = PrivacySpaceRef.parse(
            await db.getSetting(AppDb.privacySpaceKey));
        if (ref == null || !ref.active) {
          break;
        }
        final child =
            AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(ref.id)));
        opened.add(child);
        if (await child.getSetting(AppDb.appLockKey) == null) {
          final engine = SyncEngine(db);
          await engine.provisionPrivacySpace(ref);
          engine.dispose();
        }
        parent = db;
        db = child;
        spaceId = ref.id;
      }
      final cooldown = await _rootAttempts.fail();
      developer.log('skip, 整链密码均未命中记一次错误, cooldownMs: $cooldown');
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = cooldown > 0 ? null : '密码错误，请重试';
      });
      if (cooldown > 0) {
        _startCooldown(cooldown);
      } else {
        _controller.clear();
        _focus.requestFocus();
      }
    } catch (err) {
      developer.log('fail, 解锁流程异常, err: $err');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '解锁失败，请重试';
        });
      }
    } finally {
      for (final db in opened) {
        if (db != widget.globalDb) {
          await db.close();
        }
      }
    }
  }

  Future<void> _enter(
      AppDb db, String? spaceId, List<AppDb> opened) async {
    for (final other in opened) {
      if (other != db && other != widget.globalDb) {
        await other.close();
      }
    }
    opened.clear();
    await _rootAttempts.succeed();
    await widget.globalDb
        .setSetting(AppDb.lockBioSpaceKey, spaceId ?? '');
    if (!mounted) {
      return;
    }
    widget.onUnlocked(db, spaceId);
  }

  Future<void> _enterTrustedSpace() async {
    final remembered =
        await widget.globalDb.getSetting(AppDb.lockBioSpaceKey) ?? '';
    var db = widget.globalDb;
    String? spaceId;
    if (remembered.isNotEmpty) {
      final child =
          AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(remembered)));
      final lock = PasswordLock.parse(await child.getSetting(AppDb.appLockKey));
      if (lock != null && lock.active) {
        db = child;
        spaceId = remembered;
      } else {
        developer.log(
            'skip, 托管解锁记忆空间已不存在回日常空间, spaceId: $remembered');
        await child.close();
      }
    }
    if (!mounted) {
      if (db != widget.globalDb) {
        await db.close();
      }
      return;
    }
    developer.log('hit, 系统应用锁托管启动解锁, spaceId: ${spaceId ?? ''}');
    await _enter(db, spaceId, []);
  }

  Future<void> _bioUnlock() async {
    if (_busy || _preparing) {
      return;
    }
    setState(() => _busy = true);
    final ok = await Biometrics.authenticate('解锁 onenote');
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() {
        _busy = false;
        _error = '生物识别未通过，请输入密码';
      });
      _focus.requestFocus();
      return;
    }
    final spaceId =
        await widget.globalDb.getSetting(AppDb.lockBioSpaceKey) ?? '';
    final db = spaceId.isEmpty
        ? widget.globalDb
        : AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(spaceId)));
    final lock = PasswordLock.parse(await db.getSetting(AppDb.appLockKey));
    if (lock == null || !lock.active) {
      developer.log(
          'skip, 生物识别指向的空间已不存在, spaceId: $spaceId');
      if (db != widget.globalDb) {
        await db.close();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '上次解锁的空间已不存在，请输入密码';
        });
      }
      return;
    }
    developer.log('done, 生物识别解锁成功, spaceId: $spaceId');
    await _enter(db, spaceId.isEmpty ? null : spaceId, []);
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    if (_preparing) {
      return const SizedBox.shrink();
    }
    final cooling = _cooldownMs > 0;
    return Scaffold(
      backgroundColor: t.paper,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(spaceLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline, size: 48, color: t.accentText),
                const SizedBox(height: spaceMd),
                Text(
                  'onenote 已锁定',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: spaceXs),
                Text(
                  '输入密码解锁',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.inkMuted),
                ),
                const SizedBox(height: spaceLg),
                PasswordField(
                  controller: _controller,
                  focusNode: _focus,
                  label: '密码',
                  obscure: _obscure,
                  customMask: true,
                  autofocus: true,
                  onToggle: () => setState(() {
                    _obscure = !_obscure;
                    _controller.masked = _obscure;
                  }),
                  onChanged: _autoSubmit,
                  onSubmitted: (_) => _submit(),
                ),
                if (cooling) ...[
                  const SizedBox(height: spaceSm),
                  Text(
                    '错误次数过多，请 ${(_cooldownMs / 1000).ceil()} 秒后重试',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: t.danger),
                  ),
                ] else if (_error != null) ...[
                  const SizedBox(height: spaceSm),
                  Text(_error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.danger)),
                ],
                const SizedBox(height: spaceLg),
                FilledButton(
                  onPressed: _busy || cooling ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Text('解锁'),
                ),
                if (_bioAvailable) ...[
                  const SizedBox(height: spaceMd),
                  Semantics(
                    button: true,
                    label: '生物识别解锁',
                    child: IconButton(
                      onPressed: _busy ? null : _bioUnlock,
                      style: const ButtonStyle(
                        mouseCursor: WidgetStatePropertyAll(
                            SystemMouseCursors.click),
                      ),
                      iconSize: 32,
                      icon: Icon(Icons.fingerprint, color: t.accentText),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}