import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/sync/sync_manifest.dart';

import '../sync/fake_remote_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  late FakeRemoteStore remote;
  late AppDb dbA;
  late AppDb dbB;
  late AppState stateA;
  late AppState stateB;
  var now = 1700000000000;

  setUp(() async {
    now = 1700000000000;
    supportDir = Directory.systemTemp.createTempSync('onenote_sync_save_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    remote = FakeRemoteStore();
    dbA = AppDb(NativeDatabase.memory(), clock: () => now);
    dbB = AppDb(NativeDatabase.memory(), clock: () => now);
    await dbA.setSetting(AppDb.syncDeviceNameKey, 'device-A');
    await dbB.setSetting(AppDb.syncDeviceNameKey, 'device-B');
    stateA = AppState(dbA, syncStoreOverride: remote);
    stateB = AppState(dbB, syncStoreOverride: remote);
    await stateA.init();
    await stateB.init();
    await stateA.syncNow('settle-A');
    await stateB.syncNow('settle-B');
  });

  tearDown(() async {
    stateA.dispose();
    stateB.dispose();
    await dbA.close();
    await dbB.close();
    supportDir.deleteSync(recursive: true);
  });

  test('保存时远端已改不同行 diff3 自动合并不丢远端内容', () async {
    final notebook = await stateA.createNotebook('work');
    now += 1000;
    final note =
        await dbA.createNote(notebook.id, title: 'doc', content: 'l1\nl2\nl3\nl4\n');
    await stateA.syncNow('seed');
    await stateB.syncNow('pull-B');

    now += 1000;
    await dbA.saveNote(note.id, 'doc', 'L1\nl2\nl3\nl4\n');
    await stateA.syncNow('push-A');

    now += 1000;
    final saved = await stateB.saveNote(note.id, 'doc', 'l1\nl2\nl3\nL4\n');
    expect(saved, isTrue);
    expect((await dbB.getNote(note.id)).content, 'L1\nl2\nl3\nL4\n');
    await stateB.syncNow('settle-push');
    expect(utf8.decode(remote.objects[contentFileOf(note.id)]!),
        'L1\nl2\nl3\nL4\n');
  });

  test('保存时远端已改同行进入冲突裁决而不是覆盖远端', () async {
    final notebook = await stateA.createNotebook('work');
    now += 1000;
    final note = await dbA.createNote(notebook.id,
        title: 'doc', content: 'head\nbase\ntail\n');
    await stateA.syncNow('seed');
    await stateB.syncNow('pull-B');

    now += 1000;
    await dbA.saveNote(note.id, 'doc', 'head\nremote X\ntail\n');
    await stateA.syncNow('push-A');

    now += 1000;
    await stateB.saveNote(note.id, 'doc', 'head\nlocal X\ntail\n');
    await stateB.syncNow('settle-conflict');
    expect(stateB.sync.conflictIds, contains(note.id));
    expect(utf8.decode(remote.objects[contentFileOf(note.id)]!),
        'head\nremote X\ntail\n');
    final payload = await stateB.conflictPayload(note.id);
    expect(payload, isNotNull);
    expect((payload!['remoteMeta'] as Map)['deviceName'], 'device-A');

    now += 1000;
    await stateB.resolveConflict(note.id, [true]);
    expect((await dbB.getNote(note.id)).content, 'head\nlocal X\ntail\n');
    expect(utf8.decode(remote.objects[contentFileOf(note.id)]!),
        'head\nlocal X\ntail\n');
  });

  test('编辑期间远端删除笔记保存时按本地改动复活', () async {
    final notebook = await stateA.createNotebook('work');
    now += 1000;
    final note =
        await dbA.createNote(notebook.id, title: 'doc', content: 'base\n');
    await stateA.syncNow('seed');
    await stateB.syncNow('pull-B');

    now += 1000;
    await dbA.hardDeleteNote(note.id);
    await dbA.addTombstoneAt(note.id, AppDb.syncKindNote, now);
    await stateA.syncNow('push-delete');

    now += 1000;
    final saved = await stateB.saveNote(note.id, 'doc', 'edited after delete\n');
    expect(saved, isTrue);
    expect((await dbB.getNote(note.id)).content, 'edited after delete\n');
    await stateB.syncNow('settle-resurrect');
    final manifest =
        SyncManifest.decode(utf8.decode(remote.objects['manifest.json']!));
    expect(manifest.notes.containsKey(note.id), isTrue);
    expect(manifest.tombstones.containsKey(note.id), isFalse);
  });

  test('远端故障时保存照常落库离线可用', () async {
    final notebook = await stateB.createNotebook('local');
    now += 1000;
    final note =
        await dbB.createNote(notebook.id, title: 'doc', content: 'old\n');
    remote.failAll = true;
    now += 1000;
    final saved = await stateB.saveNote(note.id, 'doc', 'offline edit\n');
    expect(saved, isTrue);
    expect((await dbB.getNote(note.id)).content, 'offline edit\n');
  });
}