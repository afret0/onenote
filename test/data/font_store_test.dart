import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/font_catalog.dart';
import 'package:onenote/data/font_store.dart';

void main() {
  late Directory root;
  late AppDb db;
  late List<String> registered;
  late LocalFontStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('onenote_font_store');
    db = AppDb(NativeDatabase.memory());
    registered = [];
    store = LocalFontStore.forTest(root,
        registrar: (family, weights) async => registered.add(family));
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('parseFontFileName 识别字重并剥离后缀', () {
    expect(LocalFontStore.parseFontFileName('LXGWWenKai-Regular.ttf'),
        ('LXGWWenKai', 400));
    expect(LocalFontStore.parseFontFileName('CascadiaCodePL-SemiBold.ttf'),
        ('CascadiaCodePL', 600));
    expect(LocalFontStore.parseFontFileName('MyFont-Bold.otf'), ('MyFont', 700));
    expect(LocalFontStore.parseFontFileName('SomeFont-500.ttf'), ('SomeFont', 500));
    expect(LocalFontStore.parseFontFileName('Plain.ttf'), ('Plain', 400));
    expect(LocalFontStore.parseFontFileName('SourceHanSansSC-Medium.otf'),
        ('SourceHanSansSC', 500));
  });

  test('导入同名文件合并字重且注册表可重载', () async {
    final regular = File('${root.path}/src/TestFont-Regular.ttf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
    final bold = File('${root.path}/src/TestFont-Bold.ttf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.fromList([4, 5, 6]));
    await store.loadRegistry(db);
    final imported =
        await store.importFiles([regular.path, bold.path]);
    expect(imported.length, 1);
    expect(imported.single.name, 'TestFont');
    expect(imported.single.weights.keys.toSet(), {400, 700});
    expect(registered, [LocalFontStore.familyOf(imported.single.id)]);

    final raw = await db.getSetting(AppDb.localFontsKey);
    expect(raw, isNotNull);
    expect(jsonDecode(raw!), hasLength(1));

    final reloaded = LocalFontStore.forTest(root,
        registrar: (family, weights) async {});
    await reloaded.loadRegistry(db);
    expect(reloaded.has(imported.single.id), isTrue);
    expect(reloaded.byId(imported.single.id)!.weights.keys.toSet(), {400, 700});
  });

  test('在线目录直下安装字重与许可', () async {
    final catalog = fontCatalogById('lxgw-wenkai')!;
    final fetched = <String>[];
    final fake = LocalFontStore.forTest(root, fetcher: (url,
        {onProgress}) async {
      fetched.add(url);
      onProgress?.call(10, 10);
      return Uint8List.fromList(utf8.encode('font:$url'));
    }, registrar: (family, weights) async => registered.add(family));
    await fake.loadRegistry(db);
    final entry = await fake.download(catalog);
    expect(entry.name, '霞鹜文楷');
    expect(entry.weights.keys.toSet(), {400, 500});
    expect(fetched, [catalog.files[0].url, catalog.files[1].url, catalog.licenseUrl]);
    expect(File('${root.path}/${entry.id}-LICENSE.txt').existsSync(), isTrue);
    for (final name in entry.weights.values) {
      expect(File('${root.path}/$name').existsSync(), isTrue);
    }
    expect(registered, [LocalFontStore.familyOf(entry.id)]);
  });

  test('zip 目录按成员解出字重与许可', () async {
    final catalog = fontCatalogById('source-han-sans-sc')!;
    final archive = Archive();
    for (final file in catalog.files) {
      final bytes = utf8.encode('otf:${file.zipMember}');
      archive.addFile(ArchiveFile(file.zipMember, bytes.length, bytes));
    }
    final license = utf8.encode('OFL text');
    archive.addFile(
        ArchiveFile(catalog.licenseZipMember, license.length, license));
    archive.addFile(ArchiveFile('OTF/SimplifiedChinese/SourceHanSansSC-Heavy.otf',
        3, [9, 9, 9]));
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final fake = LocalFontStore.forTest(root,
        fetcher: (url, {onProgress}) async => zipBytes,
        registrar: (family, weights) async => registered.add(family));
    await fake.loadRegistry(db);
    final entry = await fake.download(catalog);
    expect(entry.weights.keys.toSet(), {400, 500, 700});
    expect(File('${root.path}/${entry.id}-400.otf').readAsBytesSync(),
        utf8.encode('otf:${catalog.files[0].zipMember}'));
    expect(File('${root.path}/${entry.id}-LICENSE.txt').existsSync(), isTrue);
    expect(File('${root.path}/${entry.id}-900.otf').existsSync(), isFalse);
  });

  test('删除清掉文件与注册项', () async {
    final source = File('${root.path}/src/Gone-Regular.ttf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.fromList([7]));
    await store.loadRegistry(db);
    final entry = (await store.importFiles([source.path])).single;
    await store.delete(entry.id);
    expect(store.has(entry.id), isFalse);
    for (final name in entry.weights.values) {
      expect(File('${root.path}/$name').existsSync(), isFalse);
    }
    expect(await db.getSetting(AppDb.localFontsKey), '[]');
  });
}