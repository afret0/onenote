import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/state/lock_attempts.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  late AppDb db;
  late AppState state;
  var now = 1700000000000;

  setUp(() async {
    now = 1700000000000;
    supportDir = await Directory.systemTemp.createTemp('onenote_lock_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    db = AppDb(NativeDatabase.memory(), clock: () => now);
    state = AppState(db);
  });

  tearDown(() async {
    state.dispose();
    await db.close();
    await supportDir.delete(recursive: true);
  });

  group('PasswordLock', () {
    test('create/verify 正确密码通过错误密码拒绝', () {
      final lock = PasswordLock.create('secret-密码', now);
      expect(lock.active, isTrue);
      expect(lock.verify('secret-密码'), isTrue);
      expect(lock.verify('wrong'), isFalse);
      expect(lock.verify(''), isFalse);
    });

    test('encode/parse 往返一致且 cleared 标记不算激活', () {
      final lock = PasswordLock.create('p', now);
      final parsed = PasswordLock.parse(lock.encode());
      expect(parsed, isNotNull);
      expect(parsed!.verify('p'), isTrue);
      expect(parsed.updateAt, now);

      final cleared = PasswordLock.clearedAt(now + 1);
      expect(cleared.active, isFalse);
      expect(cleared.verify('p'), isFalse);
      final parsedCleared = PasswordLock.parse(cleared.encode());
      expect(parsedCleared!.cleared, isTrue);
      expect(parsedCleared.active, isFalse);
      expect(PasswordLock.parse(null), isNull);
      expect(PasswordLock.parse('not-json'), isNull);
    });

    test('PrivacySpaceRef 扁平编码往返一致', () {
      final ref = PrivacySpaceRef(
          id: 'space-1',
          lock: PasswordLock.create('b', now),
          createAt: now);
      final parsed = PrivacySpaceRef.parse(ref.encode());
      expect(parsed!.active, isTrue);
      expect(parsed.id, 'space-1');
      expect(parsed.lock.verify('b'), isTrue);
      expect(parsed.createAt, now);
      final cleared = PrivacySpaceRef.clearedAt(now + 1);
      expect(cleared.active, isFalse);
      expect(PrivacySpaceRef.parse(cleared.encode())!.cleared, isTrue);
    });
  });

  group('LockAttempts', () {
    test('连错 5 次触发 60 秒冷却且重启后仍在冷却', () async {
      final lock = PasswordLock.create('right', now);
      final attempts = LockAttempts(db);
      for (var i = 0; i < 4; i++) {
        final result = await attempts.verify(lock, 'wrong');
        expect(result.ok, isFalse);
        expect(result.cooldownMs, 0);
      }
      final fifth = await attempts.verify(lock, 'wrong');
      expect(fifth.ok, isFalse);
      expect(fifth.cooldownMs, AppDb.lockCooldownMs);

      final restarted = LockAttempts(db);
      final cooling = await restarted.verify(lock, 'right');
      expect(cooling.ok, isFalse);
      expect(cooling.cooldownMs, AppDb.lockCooldownMs);

      now += AppDb.lockCooldownMs;
      final after = await restarted.verify(lock, 'right');
      expect(after.ok, isTrue);
    });

    test('成功校验清零失败计数', () async {
      final lock = PasswordLock.create('right', now);
      final attempts = LockAttempts(db);
      await attempts.verify(lock, 'wrong');
      await attempts.verify(lock, 'wrong');
      await attempts.verify(lock, 'right');
      for (var i = 0; i < 4; i++) {
        final result = await attempts.verify(lock, 'wrong');
        expect(result.cooldownMs, 0);
      }
    });
  });

  group('笔记本锁', () {
    test('上锁后进入/新建/改名/改色/删除全被拦截, 解锁后放行', () async {
      final work = await db.createNotebook('work');
      now += 1000;
      final note = await db.createNote(work.id, title: 't', content: 'body');
      await state.init();
      await state.setNotebookPassword(work.id, 'nb-pass');
      await state.lockApp();
      expect(state.isNotebookLocked(work.id), isTrue);

      await state.selectScope(NoteScope.notebook(work.id));
      expect(state.scope.kind, NoteScopeKind.all);
      await state.openNote(note.id);
      expect(state.openNoteId, isNull);
      expect(await state.createNote(), isNull);
      await state.renameNotebook(work.id, 'renamed');
      expect(state.notebookName(work.id), 'work');
      await state.trashNote(note.id);
      expect((await db.findNote(note.id))!.deletedAt, isNull);

      state.grantNotebookUnlock(work.id);
      expect(state.isNotebookLocked(work.id), isFalse);
      await state.selectScope(NoteScope.notebook(work.id));
      expect(state.scope.kind, NoteScopeKind.notebook);
      await state.openNote(note.id);
      expect(state.openNoteId, note.id);
    });

    test('租期到期自动重新上锁, 任何操作续期', () async {
      final work = await db.createNotebook('work');
      await state.init();
      await state.setNotebookPassword(work.id, 'nb-pass');
      state.grantNotebookUnlock(work.id);
      expect(state.isNotebookLocked(work.id), isFalse);

      now += 9 * 60000;
      state.touchLease('notebook:${work.id}');
      now += 9 * 60000;
      expect(state.isNotebookLocked(work.id), isFalse);

      now += 2 * 60000;
      expect(state.isNotebookLocked(work.id), isTrue);
    });

    test('不定时租期本次运行内一直免密', () async {
      final work = await db.createNotebook('work');
      await state.init();
      await state.setLockLeaseMinutes(0);
      await state.setNotebookPassword(work.id, 'nb-pass');
      state.grantNotebookUnlock(work.id);
      now += 365 * 24 * 3600000;
      expect(state.isNotebookLocked(work.id), isFalse);
    });

    test('移除密码后不再上锁', () async {
      final work = await db.createNotebook('work');
      await state.init();
      await state.setNotebookPassword(work.id, 'nb-pass');
      await state.removeNotebookPassword(work.id);
      expect(state.isNotebookLocked(work.id), isFalse);
      expect(state.notebookLock(work.id), isNull);
    });
  });

  group('笔记锁', () {
    test('笔记上锁拦截打开与删除, 父笔记本锁连带生效', () async {
      final work = await db.createNotebook('work');
      now += 1000;
      final note = await db.createNote(work.id, title: 't', content: 'body');
      await state.init();
      await state.setNotePassword(note.id, 'note-pass');
      await state.lockApp();
      expect(state.isNoteLocked(note.id), isTrue);
      await state.openNote(note.id);
      expect(state.openNoteId, isNull);
      await state.trashNote(note.id);
      expect((await db.findNote(note.id))!.deletedAt, isNull);

      state.grantNoteUnlock(note.id);
      expect(state.isNoteLocked(note.id), isFalse);
      await state.openNote(note.id);
      expect(state.openNoteId, note.id);

      await state.setNotebookPassword(work.id, 'nb-pass');
      expect(state.isNoteLocked(note.id), isFalse);
      await state.lockApp();
      expect(state.isNoteLocked(note.id), isTrue);
      state.grantNotebookUnlock(work.id);
      expect(state.isNoteLocked(note.id), isTrue);
      state.grantNoteUnlock(note.id);
      expect(state.isNoteLocked(note.id), isFalse);
    });

    test('touchNote 同时续期笔记与父笔记本租期', () async {
      final work = await db.createNotebook('work');
      now += 1000;
      final note = await db.createNote(work.id, title: 't', content: 'body');
      await state.init();
      await state.setNotebookPassword(work.id, 'nb-pass');
      await state.setNotePassword(note.id, 'note-pass');
      state.grantNotebookUnlock(work.id);
      state.grantNoteUnlock(note.id);

      now += 9 * 60000;
      state.touchNote(note.id);
      now += 9 * 60000;
      expect(state.isNoteLocked(note.id), isFalse);
      expect(state.isNotebookLocked(work.id), isFalse);
      now += 2 * 60000;
      expect(state.isNoteLocked(note.id), isTrue);
    });

    test('回收站里的上锁笔记恢复与彻底删除也被拦截', () async {
      final work = await db.createNotebook('work');
      now += 1000;
      final note = await db.createNote(work.id, title: 't', content: 'body');
      await state.init();
      await state.trashNote(note.id);
      await state.setNotePassword(note.id, 'note-pass');
      await state.lockApp();
      await state.restoreNote(note.id);
      expect((await db.findNote(note.id))!.deletedAt, isNotNull);
      await state.hardDeleteNote(note.id);
      expect(await db.findNote(note.id), isNotNull);
      state.grantNoteUnlock(note.id);
      await state.restoreNote(note.id);
      expect((await db.findNote(note.id))!.deletedAt, isNull);
    });
  });

  group('App 密码与隐私空间', () {
    test('设置/移除 App 密码, 存在隐私空间时禁止移除', () async {
      await state.init();
      expect(state.appLock, isNull);
      await state.setAppPassword('app-pass');
      expect(state.appLock!.active, isTrue);
      expect(state.appLock!.verify('app-pass'), isTrue);

      await state.createPrivacySpace('space-pass');
      expect(state.privacyRef!.active, isTrue);
      expect(state.privacyRef!.lock.verify('space-pass'), isTrue);

      expect(() => state.removeAppPassword(), throwsStateError);
      expect(() => state.createPrivacySpace('another'), throwsStateError);

      await state.deletePrivacySpace();
      expect(state.privacyRef!.active, isFalse);
      await state.removeAppPassword();
      expect(state.appLock!.active, isFalse);
    });

    test('未设置 App 密码不能创建隐私空间', () async {
      await state.init();
      expect(() => state.createPrivacySpace('space-pass'), throwsStateError);
    });

    test('隐私空间子库继承同步配置并带 spaces 前缀', () async {
      await db.setSetting(AppDb.syncProtocolKey, AppDb.syncProtocolWebdav);
      await db.setSetting(AppDb.syncWebdavUrlKey, 'https://dav.example');
      await db.setSetting(AppDb.syncWebdavPathKey, '/notes');
      await state.init();
      await state.setAppPassword('app-pass');
      final ref = await state.createPrivacySpace('space-pass');

      final child = AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(ref.id)));
      addTearDown(child.close);
      final childLock =
          PasswordLock.parse(await child.getSetting(AppDb.appLockKey));
      expect(childLock!.verify('space-pass'), isTrue);
      expect(await child.getSetting(AppDb.spaceIdKey), ref.id);
      expect(await child.getSetting(AppDb.spaceParentKey), '');
      expect(await child.getSetting(AppDb.syncWebdavPathKey),
          '/notes/spaces/${ref.id}');
    });

    test('App 空闲租期到期回锁屏, 操作续期不锁', () async {
      await state.init();
      await state.setAppPassword('app-pass');
      var locked = 0;
      state.lockHandler = () => locked++;

      now += 9 * 60000;
      state.touchAppActivity();
      now += 9 * 60000;
      state.sweepLeases();
      expect(locked, 0);

      now += 2 * 60000;
      state.sweepLeases();
      await Future<void>.delayed(Duration.zero);
      expect(locked, 1);
    });

    test('未设 App 密码不授 App 租期, 移除密码后清租期', () async {
      await state.init();
      now += 60 * 60000;
      state.sweepLeases();
      var locked = 0;
      state.lockHandler = () => locked++;
      expect(locked, 0);

      await state.setAppPassword('app-pass');
      await state.removeAppPassword();
      now += 60 * 60000;
      state.sweepLeases();
      await Future<void>.delayed(Duration.zero);
      expect(locked, 0);
    });

    test('进入已设密码的空间即授 App 租期, 到期回锁屏', () async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('app-pass', now).encode());
      await state.init();
      var locked = 0;
      state.lockHandler = () => locked++;
      now += 11 * 60000;
      state.sweepLeases();
      await Future<void>.delayed(Duration.zero);
      expect(locked, 1);
    });

    test('自动上锁改为不定时后 App 租期永不到期, 改回分钟重新计时', () async {
      await state.init();
      await state.setAppPassword('app-pass');
      var locked = 0;
      state.lockHandler = () => locked++;

      await state.setLockLeaseMinutes(0);
      now += 365 * 24 * 3600000;
      state.sweepLeases();
      await Future<void>.delayed(Duration.zero);
      expect(locked, 0);

      await state.setLockLeaseMinutes(5);
      now += 4 * 60000;
      state.sweepLeases();
      expect(locked, 0);
      now += 2 * 60000;
      state.sweepLeases();
      await Future<void>.delayed(Duration.zero);
      expect(locked, 1);
    });

    test('缩短时长对已授租期立即生效', () async {
      await state.init();
      await state.setAppPassword('app-pass');
      var locked = 0;
      state.lockHandler = () => locked++;
      await state.setLockLeaseMinutes(5);
      now += 6 * 60000;
      state.sweepLeases();
      await Future<void>.delayed(Duration.zero);
      expect(locked, 1);
    });

    test('lockApp 清空全部租期并触发 lockHandler', () async {
      final work = await db.createNotebook('work');
      now += 1000;
      final note = await db.createNote(work.id, title: 't', content: 'body');
      await state.init();
      await state.setNotebookPassword(work.id, 'nb-pass');
      state.grantNotebookUnlock(work.id);
      await state.openNote(note.id, verified: true);
      var locked = 0;
      state.lockHandler = () => locked++;
      await state.lockApp();
      expect(locked, 1);
      expect(state.openNoteId, isNull);
      expect(state.isNotebookLocked(work.id), isTrue);
    });
  });

  group('后台与失焦锁定开关', () {
    test('缺省两个开关都开', () async {
      await state.init();
      expect(state.appBackgroundLock, isTrue);
      expect(state.appBlurLock, isTrue);
    });

    test('老库只有关闭的后台开关时失焦开关继承其值', () async {
      await db.setSetting(AppDb.appBackgroundLockKey, '0');
      await state.init();
      expect(state.appBackgroundLock, isFalse);
      expect(state.appBlurLock, isFalse);
    });

    test('两个开关独立存取, 失焦开关落库后不再跟随后台开关', () async {
      await db.setSetting(AppDb.appBackgroundLockKey, '0');
      await state.init();
      await state.setAppBlurLock(true);
      await state.setAppBackgroundLock(true);
      await state.setAppBlurLock(false);
      expect(await db.getSetting(AppDb.appBlurLockKey), '0');
      expect(await db.getSetting(AppDb.appBackgroundLockKey), '1');

      final restarted = AppState(db);
      addTearDown(restarted.dispose);
      await restarted.init();
      expect(restarted.appBackgroundLock, isTrue);
      expect(restarted.appBlurLock, isFalse);
    });
  });
}