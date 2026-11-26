import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/container_migration.dart';

void main() {
  late Directory root;
  late Directory oldDocs;
  late Directory oldSupport;
  late Directory newDocs;
  late Directory newSupport;

  setUp(() {
    root = Directory.systemTemp.createTempSync('container_migration_test_');
    oldDocs = Directory('${root.path}/old/Documents')..createSync(recursive: true);
    oldSupport = Directory(
        '${root.path}/old/Library/Application Support/com.afreto.onenote')
      ..createSync(recursive: true);
    newDocs = Directory('${root.path}/new/Documents')..createSync(recursive: true);
    newSupport = Directory(
        '${root.path}/new/Application Support/com.afreto.onenote');
  });

  tearDown(() => root.deleteSync(recursive: true));

  void seedOld() {
    File('${oldDocs.path}/onenote.sqlite').writeAsStringSync('db-main');
    File('${oldDocs.path}/onenote.sqlite-wal').writeAsStringSync('wal');
    File('${oldDocs.path}/onenote_space_abc.sqlite').writeAsStringSync('db-space');
    File('${oldDocs.path}/unrelated.txt').writeAsStringSync('user-file');
    Directory('${oldSupport.path}/attachments').createSync();
    File('${oldSupport.path}/attachments/aa').writeAsStringSync('asset-a');
    File('${oldSupport.path}/attachments/aa.name').writeAsStringSync('a.png');
    Directory('${oldSupport.path}/attachments_space_abc').createSync();
    File('${oldSupport.path}/attachments_space_abc/bb').writeAsStringSync('asset-b');
    Directory('${oldSupport.path}/fonts').createSync();
    File('${oldSupport.path}/fonts/f.ttf').writeAsStringSync('font');
    Directory('${oldSupport.path}/misc').createSync();
    File('${oldSupport.path}/misc/keep-out').writeAsStringSync('x');
  }

  test('迁移数据库与附件字体, 不带无关文件, 旧容器保留', () async {
    seedOld();
    await migrateContainerData(
        oldDocs: oldDocs,
        oldSupport: oldSupport,
        newDocs: newDocs,
        newSupport: newSupport);
    expect(File('${newDocs.path}/onenote.sqlite').readAsStringSync(), 'db-main');
    expect(File('${newDocs.path}/onenote.sqlite-wal').readAsStringSync(), 'wal');
    expect(File('${newDocs.path}/onenote_space_abc.sqlite').existsSync(), isTrue);
    expect(File('${newDocs.path}/unrelated.txt').existsSync(), isFalse);
    expect(File('${newSupport.path}/attachments/aa').readAsStringSync(), 'asset-a');
    expect(File('${newSupport.path}/attachments/aa.name').existsSync(), isTrue);
    expect(
        File('${newSupport.path}/attachments_space_abc/bb').readAsStringSync(),
        'asset-b');
    expect(File('${newSupport.path}/fonts/f.ttf').readAsStringSync(), 'font');
    expect(Directory('${newSupport.path}/misc').existsSync(), isFalse);
    expect(File('${oldDocs.path}/onenote.sqlite').existsSync(), isTrue);
  });

  test('新位置已有数据库则整体跳过不覆盖', () async {
    seedOld();
    File('${newDocs.path}/onenote.sqlite').writeAsStringSync('newer-db');
    await migrateContainerData(
        oldDocs: oldDocs,
        oldSupport: oldSupport,
        newDocs: newDocs,
        newSupport: newSupport);
    expect(
        File('${newDocs.path}/onenote.sqlite').readAsStringSync(), 'newer-db');
    expect(File('${newSupport.path}/attachments/aa').existsSync(), isFalse);
  });

  test('重复跑幂等, 已存在目标不覆盖', () async {
    seedOld();
    await migrateContainerData(
        oldDocs: oldDocs,
        oldSupport: oldSupport,
        newDocs: newDocs,
        newSupport: newSupport);
    File('${newDocs.path}/onenote.sqlite').writeAsStringSync('edited-after');
    File('${oldDocs.path}/onenote.sqlite').writeAsStringSync('stale-old');
    await migrateContainerData(
        oldDocs: oldDocs,
        oldSupport: oldSupport,
        newDocs: newDocs,
        newSupport: newSupport);
    expect(File('${newDocs.path}/onenote.sqlite').readAsStringSync(),
        'edited-after');
  });

  test('旧容器不存在直接返回', () async {
    await migrateContainerData(
        oldDocs: Directory('${root.path}/absent'),
        oldSupport: oldSupport,
        newDocs: newDocs,
        newSupport: newSupport);
    expect(newDocs.listSync(), isEmpty);
  });
}