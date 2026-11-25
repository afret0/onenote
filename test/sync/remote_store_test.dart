import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/sync/oss_store.dart';
import 'package:onenote/sync/webdav_store.dart';

void main() {
  group('OssStore.signature', () {
    test('已知向量：PUT 带 Content-Type 与 Date', () {
      const payload =
          'PUT\n\napplication/octet-stream\nWed, 25 Nov 2026 08:00:00 GMT\n/bucket/onenote/manifest.json';
      final expected = base64Encode(
          Hmac(sha1, utf8.encode('secret-key')).convert(utf8.encode(payload)).bytes);
      final actual = OssStore.signature(
        method: 'PUT',
        contentMd5: '',
        contentType: 'application/octet-stream',
        date: 'Wed, 25 Nov 2026 08:00:00 GMT',
        canonicalizedResource: '/bucket/onenote/manifest.json',
        accessKeySecret: 'secret-key',
      );
      expect(actual, expected);
    });

    test('GET 无 Content-Type 时签名段落为空行', () {
      const payload =
          'GET\n\n\nWed, 25 Nov 2026 08:00:00 GMT\n/bucket/onenote/notes/n1.md';
      final expected = base64Encode(
          Hmac(sha1, utf8.encode('sk')).convert(utf8.encode(payload)).bytes);
      final actual = OssStore.signature(
        method: 'GET',
        contentMd5: '',
        contentType: '',
        date: 'Wed, 25 Nov 2026 08:00:00 GMT',
        canonicalizedResource: '/bucket/onenote/notes/n1.md',
        accessKeySecret: 'sk',
      );
      expect(actual, expected);
    });

    test('密钥不同签名不同', () {
      String sign(String sk) => OssStore.signature(
            method: 'GET',
            contentMd5: '',
            contentType: '',
            date: 'Thu, 26 Nov 2026 00:00:00 GMT',
            canonicalizedResource: '/b/p/x',
            accessKeySecret: sk,
          );
      expect(sign('a'), isNot(sign('b')));
    });
  });

  group('OssStore.httpDate', () {
    test('输出 GMT 英文格式', () {
      final time = DateTime.utc(2026, 11, 25, 8, 0, 0);
      expect(OssStore.httpDate(time), 'Wed, 25 Nov 2026 08:00:00 GMT');
    });

    test('本地时间先转 UTC', () {
      final time = DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal();
      expect(OssStore.httpDate(time), 'Fri, 02 Jan 2026 03:04:05 GMT');
    });
  });

  group('OssStore.normalizePrefix', () {
    final cases = {
      '': 'onenote',
      '  ': 'onenote',
      '/notes/': 'notes',
      'a/b': 'a/b',
      '///x///': 'x',
    };
    cases.forEach((raw, expected) {
      test('「$raw」→「$expected」', () {
        expect(OssStore.normalizePrefix(raw), expected);
      });
    });
  });

  group('WebdavStore.normalizeBaseUrl', () {
    final cases = {
      '': '',
      '  ': '',
      'webdav.kekeyuyin.com': 'https://webdav.kekeyuyin.com',
      'webdav.kekeyuyin.com/dav': 'https://webdav.kekeyuyin.com/dav',
      'https://dav.jianguoyun.com/dav': 'https://dav.jianguoyun.com/dav',
      'http://192.168.1.2:5005': 'http://192.168.1.2:5005',
      ' https://a.b ': 'https://a.b',
    };
    cases.forEach((raw, expected) {
      test('「$raw」→「$expected」', () {
        expect(WebdavStore.normalizeBaseUrl(raw), expected);
      });
    });

    test('构造时归一化，裸域名不再产生无 host 的 URI', () {
      final store = WebdavStore(
        baseUrl: 'webdav.kekeyuyin.com',
        username: 'u',
        password: 'p',
        rootPath: '/onenote',
      );
      expect(store.baseUrl, 'https://webdav.kekeyuyin.com');
    });
  });

  group('WebdavStore.normalizeRoot', () {
    final cases = {
      '': '/onenote',
      '  ': '/onenote',
      'dav': '/dav',
      '/dav/': '/dav',
      '/a/b/': '/a/b',
    };
    cases.forEach((raw, expected) {
      test('「$raw」→「$expected」', () {
        expect(WebdavStore.normalizeRoot(raw), expected);
      });
    });
  });
}