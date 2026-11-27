import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/update/update_checker.dart';
import 'package:onenote/update/update_download.dart';

const release = UpdateRelease(
  version: '9.9.9',
  pageUrl: 'https://example.com/release',
  assets: [
    UpdateAsset(name: 'onenote_9.9.9.dmg', url: 'https://x/dmg', size: 100),
  ],
);

const release2 = UpdateRelease(
  version: '9.9.10',
  pageUrl: 'https://example.com/release2',
  assets: [
    UpdateAsset(name: 'onenote_9.9.10.dmg', url: 'https://x/dmg2', size: 200),
  ],
);

void main() {
  test('ensureStarted 去重, 完成后 waitReady 直接给路径', () async {
    var calls = 0;
    final gate = Completer<String>();
    final m = SilentUpdateDownload(
      installSupported: true,
      existingCheck: (n, s) async => null,
      downloader: (url, name, {required onProgress, required isCancelled}) {
        calls++;
        return gate.future;
      },
    );
    m.ensureStarted(release);
    m.ensureStarted(release);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(m.downloading, isTrue);
    gate.complete('/tmp/a.dmg');
    expect(await m.waitReady(), '/tmp/a.dmg');
    expect(m.ready, isTrue);
    m.ensureStarted(release);
    expect(calls, 1);
  });

  test('进度回调更新 received/total 并通知', () async {
    final gate = Completer<String>();
    var notified = 0;
    final m = SilentUpdateDownload(
      installSupported: true,
      existingCheck: (n, s) async => null,
      downloader: (url, name, {required onProgress, required isCancelled}) {
        onProgress(40, 100);
        return gate.future;
      },
    );
    m.addListener(() => notified++);
    m.ensureStarted(release);
    await Future<void>.delayed(Duration.zero);
    expect(m.received, 40);
    expect(m.total, 100);
    gate.complete('/tmp/a.dmg');
    await m.waitReady();
    expect(notified, greaterThan(0));
  });

  test('已下载完成的同大小文件直接复用不发请求', () async {
    var calls = 0;
    final m = SilentUpdateDownload(
      installSupported: true,
      existingCheck: (n, s) async => '/tmp/cached.dmg',
      downloader: (url, name, {required onProgress, required isCancelled}) {
        calls++;
        return Future.value('/tmp/new.dmg');
      },
    );
    m.ensureStarted(release);
    expect(await m.waitReady(), '/tmp/cached.dmg');
    expect(calls, 0);
  });

  test('失败后 restart 重下, 新版本替换旧任务', () async {
    var calls = 0;
    final m = SilentUpdateDownload(
      installSupported: true,
      existingCheck: (n, s) async => null,
      downloader: (url, name, {required onProgress, required isCancelled}) {
        calls++;
        if (calls == 1) return Future.error(const FormatException('net down'));
        return Future.value('/tmp/$name');
      },
    );
    m.ensureStarted(release);
    await expectLater(m.waitReady(), throwsA(isA<FormatException>()));
    m.restart();
    expect(await m.waitReady(), '/tmp/onenote_9.9.9.dmg');
    m.ensureStarted(release2);
    expect(await m.waitReady(), '/tmp/onenote_9.9.10.dmg');
    expect(m.version, '9.9.10');
  });

  test('cancel 中断在途下载并清空任务', () async {
    final gate = Completer<String>();
    final m = SilentUpdateDownload(
      installSupported: true,
      existingCheck: (n, s) async => null,
      downloader: (url, name, {required onProgress, required isCancelled}) {
        return gate.future.then((p) {
          if (isCancelled()) throw const FormatException('cancelled');
          return p;
        });
      },
    );
    m.ensureStarted(release);
    m.cancel();
    expect(m.version, isNull);
    expect(m.downloading, isFalse);
    gate.complete('/tmp/a.dmg');
    await expectLater(m.waitReady(), throwsA(isA<StateError>()));
    expect(m.readyPath, isNull);
  });

  test('不支持应用内安装的平台不建任务', () {
    final m = SilentUpdateDownload(
      installSupported: false,
      existingCheck: (n, s) async => null,
      downloader: (url, name, {required onProgress, required isCancelled}) =>
          Future.value('x'),
    );
    m.ensureStarted(release);
    expect(m.version, isNull);
  });
}