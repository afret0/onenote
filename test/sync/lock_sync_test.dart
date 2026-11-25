import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/sync/sync_engine.dart';

import 'fake_remote_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRemoteStore remote;
  late Directory supportDir;
  var now = 1700000000000;
  final dbs = <AppDb>[];
  final engines = <SyncEngine>[];

  Future<AppDb> newDb(String deviceName) async {
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    await db.setSetting(AppDb.syncDeviceNameKey, deviceName);
    dbs.add(db);
    return db;
  }

  Future<SyncEngine> engineFor(AppDb db) async {
    final engine = SyncEngine(db, storeOverride: remote);
    await engine.init();
    engines.add(engine);
    return engine;
  }

  setUp(() async {
    now = 1700000000000;
    remote = FakeRemoteStore();
    supportDir = await Directory.systemTemp.createTemp('onenote_lock_sync_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
  });

  tearDown(() async {
    for (final engine in engines) {
      engine.dispose();
    }
    engines.clear();
    for (final db in dbs) {
      await db.close();
    }
    dbs.clear();
    await supportDir.delete(recursive: true);
  });

  test('笔记本与笔记密码随同步传播到另一台设备', () async {
    final a = await newDb('device-A');
    final b = await newDb('device-B');
    final ea = await engineFor(a);
    final eb = await engineFor(b);
    final notebook = await a.createNotebook('work');
    now += 1000;
    final note = await a.createNote(notebook.id, title: 't', content: 'body');
    now += 1000;
    await a.setNotebookLock(
        notebook.id, PasswordLock.create('nb-pass', now).encode());
    now += 1000;
    await a.setNoteLock(note.id, PasswordLock.create('note-pass', now).encode());

    expect((await ea.requestSync('a-push')).ok, isTrue);
    expect((await eb.requestSync('b-pull')).ok, isTrue);

    final remoteNotebook =
        PasswordLock.parse((await b.findNotebook(notebook.id))!.lock);
    expect(remoteNotebook!.verify('nb-pass'), isTrue);
    final remoteNote = PasswordLock.parse((await b.findNote(note.id))!.lock);
    expect(remoteNote!.verify('note-pass'), isTrue);
  });

  test('修改密码后另一台设备同步到新版本', () async {
    final a = await newDb('device-A');
    final b = await newDb('device-B');
    final ea = await engineFor(a);
    final eb = await engineFor(b);
    final notebook = await a.createNotebook('work');
    now += 1000;
    await a.setNotebookLock(
        notebook.id, PasswordLock.create('old-pass', now).encode());
    await ea.requestSync('a-push-1');
    await eb.requestSync('b-pull-1');
    expect(
        PasswordLock.parse((await b.findNotebook(notebook.id))!.lock)!
            .verify('old-pass'),
        isTrue);

    now += 1000;
    await a.setNotebookLock(
        notebook.id, PasswordLock.create('new-pass', now).encode());
    await ea.requestSync('a-push-2');
    await eb.requestSync('b-pull-2');
    final updated =
        PasswordLock.parse((await b.findNotebook(notebook.id))!.lock)!;
    expect(updated.verify('new-pass'), isTrue);
    expect(updated.verify('old-pass'), isFalse);
  });

  test('App 密码标记经 syncLockMarkers 传播, 本地更新的密码不被回退', () async {
    final a = await newDb('device-A');
    final b = await newDb('device-B');
    final ea = await engineFor(a);
    final eb = await engineFor(b);
    now += 1000;
    await a.setSetting(
        AppDb.appLockKey, PasswordLock.create('app-pass', now).encode());
    await ea.requestSync('a-push');

    await eb.syncLockMarkers();
    final adopted = PasswordLock.parse(await b.getSetting(AppDb.appLockKey));
    expect(adopted!.verify('app-pass'), isTrue);

    now += 1000;
    await b.setSetting(
        AppDb.appLockKey, PasswordLock.create('newer-local', now).encode());
    await eb.syncLockMarkers();
    final kept = PasswordLock.parse(await b.getSetting(AppDb.appLockKey));
    expect(kept!.verify('newer-local'), isTrue);
  });

  test('隐私空间标记传播后另一台设备可就地建库', () async {
    final a = await newDb('device-A');
    final b = await newDb('device-B');
    final ea = await engineFor(a);
    final eb = await engineFor(b);
    now += 1000;
    await a.setSetting(
        AppDb.appLockKey, PasswordLock.create('app-pass', now).encode());
    now += 1000;
    final ref = PrivacySpaceRef(
        id: 'space-test-1',
        lock: PasswordLock.create('space-pass', now),
        createAt: now);
    await ea.provisionPrivacySpace(ref);
    await a.setSetting(AppDb.privacySpaceKey, ref.encode());
    await ea.requestSync('a-push');

    await eb.syncLockMarkers();
    final adoptedRef =
        PrivacySpaceRef.parse(await b.getSetting(AppDb.privacySpaceKey));
    expect(adoptedRef!.active, isTrue);
    expect(adoptedRef.id, 'space-test-1');
    expect(adoptedRef.lock.verify('space-pass'), isTrue);

    await eb.provisionPrivacySpace(adoptedRef);
    final child =
        AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(adoptedRef.id)));
    addTearDown(child.close);
    final childLock =
        PasswordLock.parse(await child.getSetting(AppDb.appLockKey));
    expect(childLock!.verify('space-pass'), isTrue);
    expect(await child.getSetting(AppDb.spaceIdKey), 'space-test-1');
  });

  test('销毁隐私空间清空子库数据', () async {
    final a = await newDb('device-A');
    final ea = await engineFor(a);
    now += 1000;
    final ref = PrivacySpaceRef(
        id: 'space-test-2',
        lock: PasswordLock.create('space-pass', now),
        createAt: now);
    await ea.provisionPrivacySpace(ref);
    final child =
        AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(ref.id)));
    final notebook = await child.createNotebook('secret');
    await child.createNote(notebook.id, title: 's', content: 'secret body');
    await child.close();

    await ea.destroyPrivacySpaceData(ref.id);
    final reopened =
        AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(ref.id)));
    addTearDown(reopened.close);
    expect(await reopened.listNotebooks(), isEmpty);
    expect(await reopened.getSetting(AppDb.appLockKey), isNull);
  });
}