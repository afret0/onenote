import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/attachment_store.dart';
import 'package:onenote/sync/sync_engine.dart';
import 'package:onenote/sync/sync_manifest.dart';

import 'fake_remote_store.dart';

class _Device {
  _Device(this.db, this.attachments, this.engine, this.attachDir);

  final AppDb db;
  AttachmentStore? attachments;
  final SyncEngine engine;
  final Directory? attachDir;

  Future<void> dispose() async {
    engine.dispose();
    await db.close();
    attachDir?.deleteSync(recursive: true);
  }
}

void main() {
  late FakeRemoteStore remote;
  var now = 1700000000000;
  final devices = <_Device>[];

  Future<_Device> newDevice(String name, {bool withAttachments = false}) async {
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    await db.setSetting(AppDb.syncDeviceNameKey, name);
    Directory? dir;
    AttachmentStore? attachments;
    if (withAttachments) {
      dir = Directory.systemTemp.createTempSync('onenote-sync-test-');
      attachments = AttachmentStore.forTest(dir);
    }
    final engine =
        SyncEngine(db, attachments: () => attachments, storeOverride: remote);
    await engine.init();
    final device = _Device(db, attachments, engine, dir);
    devices.add(device);
    return device;
  }

  setUp(() {
    now = 1700000000000;
    remote = FakeRemoteStore();
  });

  tearDown(() async {
    for (final device in devices) {
      await device.dispose();
    }
    devices.clear();
  });

  test('首次同步上传全部内容, 二次同步零写零正文下载', () async {
    final a = await newDevice('device-A');
    final notebook = await a.db.createNotebook('work');
    now += 1000;
    final note = await a.db.createNote(notebook.id,
        title: 't1', content: 'hello sync');

    final first = await a.engine.requestSync('test-first');
    expect(first.ok, isTrue);
    expect(first.uploadedNotes, 1);
    expect(remote.objects.keys,
        containsAll(['manifest.json', contentFileOf(note.id)]));

    remote.clearLogs();
    final second = await a.engine.requestSync('test-second');
    expect(second.ok, isTrue);
    expect(second.uploadedNotes, 0);
    expect(second.downloadedNotes, 0);
    expect(remote.writeLog, isEmpty);
    expect(remote.readLog, ['manifest.json']);
  });

  test('零增量同步后引擎暴露远端笔记与笔记本计数', () async {
    final a = await newDevice('计数设备');
    final nb = await a.db.createNotebook('计数本');
    await a.db.createNote(nb.id, title: 'n1', content: 'c1');
    await a.engine.requestSync('seed');
    final second = await a.engine.requestSync('zero');
    expect(second.uploadedNotes, 0);
    expect(second.downloadedNotes, 0);
    expect(a.engine.remoteNoteCount, 1);
    expect(a.engine.remoteNotebookCount, 1);
  });

  test('只改一篇时只重传该篇正文与 manifest', () async {
    final a = await newDevice('device-A');
    final notebook = await a.db.createNotebook('work');
    now += 1000;
    final n1 = await a.db.createNote(notebook.id, title: 'a', content: 'aaa');
    now += 1000;
    final n2 = await a.db.createNote(notebook.id, title: 'b', content: 'bbb');
    await a.engine.requestSync('seed');
    remote.clearLogs();

    now += 1000;
    await a.db.saveNote(n1.id, 'a', 'aaa edited');
    final outcome = await a.engine.requestSync('incremental');
    expect(outcome.uploadedNotes, 1);
    expect(remote.writeLog,
        unorderedEquals([contentFileOf(n1.id), 'manifest.json']));
    expect(remote.writeLog.contains(contentFileOf(n2.id)), isFalse);
  });

  test('同步进行中远端故障本地数据不动', () async {
    final a = await newDevice('device-A');
    final notebook = await a.db.createNotebook('work');
    now += 1000;
    await a.db.createNote(notebook.id, title: 't', content: 'keep me');
    remote.failAll = true;
    final outcome = await a.engine.requestSync('failure');
    expect(outcome.ran, isTrue);
    expect(outcome.error, isNotNull);
    expect(await a.db.listNotebooks(), hasLength(1));
    expect(await a.db.listAllNotes(), hasLength(1));
    expect(a.engine.lastError, isNotNull);
  });

  test('远端 manifest 为空但本地有数据绝不清本地并重建远端', () async {
    final a = await newDevice('device-A');
    final notebook = await a.db.createNotebook('work');
    now += 1000;
    final note = await a.db.createNote(notebook.id, title: 't', content: 'data');
    await a.engine.requestSync('seed');
    remote.objects['manifest.json'] =
        Uint8List.fromList(utf8.encode(SyncManifest().encode()));
    remote.etags['manifest.json'] = 'etag-empty-override';

    final outcome = await a.engine.requestSync('empty-remote');
    expect(outcome.ok, isTrue);
    expect(await a.db.listNotebooks(), hasLength(1));
    expect(await a.db.listAllNotes(), hasLength(1));
    final rebuilt = SyncManifest.decode(
        utf8.decode(remote.objects['manifest.json']!));
    expect(rebuilt.notes.containsKey(note.id), isTrue);
    expect(rebuilt.notebooks.containsKey(notebook.id), isTrue);
  });

  test('双设备增量拉取只下载改动笔记', () async {
    final a = await newDevice('device-A');
    final b = await newDevice('device-B');
    final notebook = await a.db.createNotebook('shared');
    now += 1000;
    final n1 = await a.db.createNote(notebook.id, title: 'one', content: 'v1');
    now += 1000;
    await a.db.createNote(notebook.id, title: 'two', content: 'stable');
    await a.engine.requestSync('seed-A');

    final pullB = await b.engine.requestSync('pull-B');
    expect(pullB.downloadedNotes, 2);
    expect((await b.db.getNote(n1.id)).content, 'v1');

    now += 1000;
    await a.db.saveNote(n1.id, 'one', 'v2');
    await a.engine.requestSync('push-A2');
    remote.clearLogs();
    final pullB2 = await b.engine.requestSync('pull-B2');
    expect(pullB2.downloadedNotes, 1);
    expect((await b.db.getNote(n1.id)).content, 'v2');
    expect(remote.readLog.where((p) => p.startsWith('notes/')).length, 1);
  });

  test('远端删除墓碑传播到本地', () async {
    final a = await newDevice('device-A');
    final b = await newDevice('device-B');
    final notebook = await a.db.createNotebook('shared');
    now += 1000;
    final note = await a.db.createNote(notebook.id, title: 't', content: 'x');
    await a.engine.requestSync('seed');
    await b.engine.requestSync('pull-B');

    now += 1000;
    await a.db.hardDeleteNote(note.id);
    await a.db.addTombstoneAt(note.id, AppDb.syncKindNote, now);
    final push = await a.engine.requestSync('push-delete');
    expect(push.ok, isTrue);
    expect(remote.objects.containsKey(contentFileOf(note.id)), isFalse);

    await b.engine.requestSync('pull-delete');
    expect(await b.db.findNote(note.id), isNull);
    expect((await b.db.listTombstones()).map((t) => t.id), contains(note.id));
  });

  test('远端删除但本地基线后有改动按本地优先复活', () async {
    final a = await newDevice('device-A');
    final b = await newDevice('device-B');
    final notebook = await a.db.createNotebook('shared');
    now += 1000;
    final note = await a.db.createNote(notebook.id, title: 't', content: 'base');
    await a.engine.requestSync('seed');
    await b.engine.requestSync('pull-B');

    now += 1000;
    await a.db.hardDeleteNote(note.id);
    await a.db.addTombstoneAt(note.id, AppDb.syncKindNote, now);
    await a.engine.requestSync('push-delete');

    now += 1000;
    await b.db.saveNote(note.id, 't', 'local edit after delete');
    final outcome = await b.engine.requestSync('resurrect');
    expect(outcome.ok, isTrue);
    expect((await b.db.getNote(note.id)).content, 'local edit after delete');

    final manifest = SyncManifest.decode(
        utf8.decode(remote.objects['manifest.json']!));
    expect(manifest.notes.containsKey(note.id), isTrue);
    expect(manifest.tombstones.containsKey(note.id), isFalse);
    await a.engine.requestSync('pull-resurrect');
    expect((await a.db.getNote(note.id)).content, 'local edit after delete');
  });

  test('双端不相交改动 diff3 自动合并并回传', () async {
    final a = await newDevice('device-A');
    final b = await newDevice('device-B');
    final notebook = await a.db.createNotebook('shared');
    now += 1000;
    final note = await a.db.createNote(notebook.id,
        title: 'doc', content: 'l1\nl2\nl3\nl4\n');
    await a.engine.requestSync('seed');
    await b.engine.requestSync('pull-B');

    now += 1000;
    await b.db.saveNote(note.id, 'doc', 'L1\nl2\nl3\nl4\n');
    await b.engine.requestSync('push-B');
    now += 1000;
    await a.db.saveNote(note.id, 'doc', 'l1\nl2\nl3\nL4\n');
    final outcome = await a.engine.requestSync('merge-A');
    expect(outcome.ok, isTrue);
    expect(outcome.conflicts, 0);
    expect((await a.db.getNote(note.id)).content, 'L1\nl2\nl3\nL4\n');
    expect(utf8.decode(remote.objects[contentFileOf(note.id)]!),
        'L1\nl2\nl3\nL4\n');
  });

  test('同行双端改动记录冲突, 裁决后合并推送', () async {
    final a = await newDevice('device-A');
    final b = await newDevice('device-B');
    final notebook = await a.db.createNotebook('shared');
    now += 1000;
    final note = await a.db.createNote(notebook.id,
        title: 'doc', content: 'head\nbase\ntail\n');
    await a.engine.requestSync('seed');
    await b.engine.requestSync('pull-B');

    now += 1000;
    await b.db.saveNote(note.id, 'doc', 'head\nremote version\ntail\n');
    await b.engine.requestSync('push-B');
    now += 1000;
    await a.db.saveNote(note.id, 'doc', 'head\nlocal version\ntail\n');
    final outcome = await a.engine.requestSync('conflict-A');
    expect(outcome.conflicts, 1);
    expect(a.engine.conflictIds, contains(note.id));
    expect((await a.db.getNote(note.id)).content, 'head\nlocal version\ntail\n');
    expect(utf8.decode(remote.objects[contentFileOf(note.id)]!),
        'head\nremote version\ntail\n');

    now += 1000;
    await a.engine.resolveConflict(note.id, [false]);
    expect(await a.db.getConflict(note.id), isNull);
    expect((await a.db.getNote(note.id)).content, 'head\nremote version\ntail\n');
    expect(utf8.decode(remote.objects[contentFileOf(note.id)]!),
        'head\nremote version\ntail\n');
  });

  test('附件内容寻址增量同步：已存在不重传, 缺失才下载', () async {
    final a = await newDevice('device-A', withAttachments: true);
    final b = await newDevice('device-B', withAttachments: true);
    final bytes = Uint8List.fromList(utf8.encode('image-bytes'));
    final assetId = await a.attachments!.save(bytes, 'pic.png');
    final notebook = await a.db.createNotebook('shared');
    now += 1000;
    final note = await a.db.createNote(notebook.id,
        title: 'with asset', content: '![pic](onenote-asset://$assetId)');
    final first = await a.engine.requestSync('seed-asset');
    expect(first.uploadedAssets, 1);
    expect(remote.objects.containsKey(assetFileOf(assetId)), isTrue);

    final pull = await b.engine.requestSync('pull-asset');
    expect(pull.downloadedAssets, 1);
    expect(await b.attachments!.fileOf(assetId).exists(), isTrue);
    expect(await b.attachments!.read(assetId), bytes);
    expect(await b.attachments!.nameOf(assetId), 'pic.png');

    remote.clearLogs();
    now += 1000;
    await a.db.saveNote(note.id, 'with asset',
        'text only change ![pic](onenote-asset://$assetId)');
    final second = await a.engine.requestSync('reuse-asset');
    expect(second.uploadedAssets, 0);
    expect(remote.writeLog.contains(assetFileOf(assetId)), isFalse);
  });

  test('以远端为准重建：丢弃本地按远端恢复', () async {
    final a = await newDevice('device-A');
    final b = await newDevice('device-B');
    final notebook = await a.db.createNotebook('shared');
    now += 1000;
    final note =
        await a.db.createNote(notebook.id, title: 'remote', content: 'remote v');
    await a.engine.requestSync('seed');

    final localOnly = await b.db.createNotebook('local-only');
    now += 1000;
    await b.db.createNote(localOnly.id, title: 'local', content: 'local v');
    final outcome = await b.engine.rebuildFromRemote();
    expect(outcome.ok, isTrue);
    expect(outcome.changedLocal, isTrue);
    final notebooks = await b.db.listNotebooks();
    expect(notebooks.map((n) => n.id), [notebook.id]);
    expect((await b.db.getNote(note.id)).content, 'remote v');
    expect(await b.db.listAllNotes(), hasLength(1));
  });

  test('远端无 manifest 时重建被拒绝且本地保留', () async {
    final b = await newDevice('device-B');
    final localOnly = await b.db.createNotebook('mine');
    now += 1000;
    await b.db.createNote(localOnly.id, title: 'keep', content: 'keep v');
    final outcome = await b.engine.rebuildFromRemote();
    expect(outcome.error, isNotNull);
    expect(await b.db.listNotebooks(), hasLength(1));
    expect(await b.db.listAllNotes(), hasLength(1));
  });

  test('软删除进回收站随同步传播', () async {
    final a = await newDevice('device-A');
    final b = await newDevice('device-B');
    final notebook = await a.db.createNotebook('shared');
    now += 1000;
    final note = await a.db.createNote(notebook.id, title: 't', content: 'x');
    await a.engine.requestSync('seed');
    await b.engine.requestSync('pull-B');

    now += 1000;
    await a.db.softDeleteNote(note.id);
    await a.engine.requestSync('push-trash');
    await b.engine.requestSync('pull-trash');
    final pulled = await b.db.getNote(note.id);
    expect(pulled.deletedAt, isNotNull);
    expect(await b.db.listNotes(), isEmpty);
    expect(await b.db.listTrash(), hasLength(1));
  });

  test('笔记本改名双端冲突时更新时间新的赢', () async {
    final a = await newDevice('device-A');
    final b = await newDevice('device-B');
    final notebook = await a.db.createNotebook('origin');
    await a.engine.requestSync('seed');
    await b.engine.requestSync('pull-B');

    now += 1000;
    await b.db.renameNotebook(notebook.id, 'rename-B');
    await b.engine.requestSync('push-B');
    now += 1000;
    await a.db.renameNotebook(notebook.id, 'rename-A');
    await a.engine.requestSync('conflict-A');
    expect((await a.db.listNotebooks()).single.name, 'rename-A');
    await b.engine.requestSync('pull-final');
    expect((await b.db.listNotebooks()).single.name, 'rename-A');
  });
}