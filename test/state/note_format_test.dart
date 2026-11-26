import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';

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
    supportDir = Directory.systemTemp.createTempSync('onenote_format_test');
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

  test('新建笔记跟随默认格式且默认只影响新笔记', () async {
    await stateA.createNotebook('work');
    expect(stateA.defaultNoteFormat, AppDb.noteFormatMarkdown);
    now += 1000;
    final first = await stateA.createNote();
    expect(first, isNotNull);
    expect(first!.format, AppDb.noteFormatMarkdown);

    await stateA.setDefaultNoteFormat(AppDb.noteFormatRichtext);
    now += 1000;
    final second = await stateA.createNote();
    expect(second!.format, AppDb.noteFormatRichtext);
    expect((await dbA.getNote(first.id)).format, AppDb.noteFormatMarkdown);
  });

  test('默认格式持久化且非法值被拒', () async {
    await stateA.setDefaultNoteFormat(AppDb.noteFormatRichtext);
    expect(await dbA.getSetting(AppDb.defaultNoteFormatKey),
        AppDb.noteFormatRichtext);
    final restarted = AppState(dbA, syncStoreOverride: remote);
    addTearDown(restarted.dispose);
    await restarted.init();
    expect(restarted.defaultNoteFormat, AppDb.noteFormatRichtext);

    await restarted.setDefaultNoteFormat('bogus');
    expect(restarted.defaultNoteFormat, AppDb.noteFormatRichtext);
  });

  test('转富文本规范化内容并单独记版本', () async {
    final notebook = await stateA.createNotebook('work');
    now += 1000;
    final note = await dbA.createNote(notebook.id,
        title: 'doc', content: '- a\n\n- b\n');
    final before = await dbA.listVersions(note.id);
    now += AppDb.versionCoalesceWindowMs;
    await stateA.setNoteFormat(note.id, AppDb.noteFormatRichtext);
    final fresh = await dbA.getNote(note.id);
    expect(fresh.format, AppDb.noteFormatRichtext);
    expect(fresh.content, '- a\n- b\n');
    final after = await dbA.listVersions(note.id);
    expect(after.length, before.length + 1);
  });

  test('转回 Markdown 保留内容且 bump updateAt', () async {
    final notebook = await stateA.createNotebook('work');
    now += 1000;
    final note = await dbA.createNote(notebook.id,
        title: 'doc', content: '# H\n\ntext\n', format: AppDb.noteFormatRichtext);
    final oldUpdate = note.updateAt;
    now += 1000;
    await stateA.setNoteFormat(note.id, AppDb.noteFormatMarkdown);
    final fresh = await dbA.getNote(note.id);
    expect(fresh.format, AppDb.noteFormatMarkdown);
    expect(fresh.content, '# H\n\ntext\n');
    expect(fresh.updateAt, greaterThan(oldUpdate));
  });

  test('上锁笔记拒绝格式切换', () async {
    final notebook = await stateA.createNotebook('work');
    now += 1000;
    final note = await dbA.createNote(notebook.id, title: 'doc', content: 'x\n');
    await stateA.setNotePassword(note.id, 'p');
    await stateA.lockApp();
    now += 1000;
    await stateA.setNoteFormat(note.id, AppDb.noteFormatRichtext);
    expect((await dbA.getNote(note.id)).format, AppDb.noteFormatMarkdown);
  });

  test('格式随同步传到另一台设备', () async {
    final notebook = await stateA.createNotebook('work');
    now += 1000;
    final note = await dbA.createNote(notebook.id, title: 'doc', content: 'x\n');
    await stateA.syncNow('seed');
    await stateB.syncNow('pull-B');
    expect((await dbB.getNote(note.id)).format, AppDb.noteFormatMarkdown);

    now += 1000;
    await stateA.setNoteFormat(note.id, AppDb.noteFormatRichtext);
    await stateA.syncNow('push-format');
    await stateB.syncNow('pull-format');
    expect((await dbB.getNote(note.id)).format, AppDb.noteFormatRichtext);
  });
}