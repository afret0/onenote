import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/ui/theme.dart';
import 'package:onenote/ui/update_dialog.dart';
import 'package:onenote/update/update_checker.dart';
import 'package:onenote/update/update_download.dart';

void main() {
  late AppDb db;

  setUp(() => db = AppDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  const release = UpdateRelease(
    version: '9.9.9',
    pageUrl: 'https://example.com/release',
    assets: [
      UpdateAsset(name: 'onenote_9.9.9.dmg', url: 'https://x/dmg', size: 1048576),
    ],
  );

  Widget wrap(Widget child) => MaterialApp(
        theme: buildInkTheme(Brightness.dark),
        home: Scaffold(body: child),
      );

  testWidgets('跳过此版本落库并关闭', (tester) async {
    await tester.pumpWidget(wrap(UpdateDialog(db: db, release: release)));
    await tester.pump();
    expect(find.text('发现新版本 v9.9.9'), findsOneWidget);
    await tester.tap(find.text('跳过此版本'));
    await tester.pumpAndSettle();
    expect(await db.getSetting(updateSkippedVersionKey), '9.9.9');
    expect(find.text('发现新版本 v9.9.9'), findsNothing);
  });

  testWidgets('静默下载已就绪时立即更新直接安装', (tester) async {
    final manager = SilentUpdateDownload(
      installSupported: true,
      existingCheck: (n, s) async => null,
      downloader: (url, name,
              {required onProgress, required isCancelled}) async =>
          '/tmp/fake.dmg',
    );
    SilentUpdateDownload.instance = manager;
    String? installedPath;
    UpdateDialog.installOverride = (path) async {
      installedPath = path;
      return 'ok';
    };
    addTearDown(() {
      SilentUpdateDownload.instance = SilentUpdateDownload();
      UpdateDialog.installOverride = null;
    });
    manager.ensureStarted(release);
    await manager.waitReady();
    await tester.pumpWidget(wrap(UpdateDialog(db: db, release: release)));
    await tester.pump();
    expect(find.text('更新包已下载完成，点击立即更新直接安装'), findsOneWidget);
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(installedPath, '/tmp/fake.dmg');
    expect(find.text('发现新版本 v9.9.9'), findsNothing);
  });

  testWidgets('跳过此版本同时取消静默下载任务', (tester) async {
    final manager = SilentUpdateDownload(
      installSupported: true,
      existingCheck: (n, s) async => null,
      downloader: (url, name,
              {required onProgress, required isCancelled}) =>
          Completer<String>().future,
    );
    SilentUpdateDownload.instance = manager;
    addTearDown(() {
      manager.cancel();
      SilentUpdateDownload.instance = SilentUpdateDownload();
    });
    manager.ensureStarted(release);
    await tester.pumpWidget(wrap(UpdateDialog(db: db, release: release)));
    await tester.pump();
    expect(manager.downloading, isTrue);
    await tester.tap(find.text('跳过此版本'));
    await tester.pumpAndSettle();
    expect(await db.getSetting(updateSkippedVersionKey), '9.9.9');
    expect(manager.version, isNull);
  });

  testWidgets('无当前平台资产时回退打开下载页', (tester) async {
    const noAsset = UpdateRelease(
        version: '9.9.9', pageUrl: 'https://example.com/release', assets: []);
    await tester.pumpWidget(wrap(UpdateDialog(db: db, release: noAsset)));
    await tester.pump();
    expect(find.text('立即更新'), findsNothing);
    expect(find.text('打开下载页'), findsOneWidget);
  });
}