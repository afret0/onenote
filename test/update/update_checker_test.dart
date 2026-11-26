import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/update/update_checker.dart';

void main() {
  group('parseVersionParts', () {
    test('接受三段与 v 前缀', () {
      expect(parseVersionParts('1.0.77'), [1, 0, 77]);
      expect(parseVersionParts('v1.0.77'), [1, 0, 77]);
    });
    test('拒绝非法格式', () {
      expect(parseVersionParts(''), isNull);
      expect(parseVersionParts('1.0'), isNull);
      expect(parseVersionParts('1.0.77+2'), isNull);
      expect(parseVersionParts('nightly'), isNull);
      expect(parseVersionParts('1.0.-1'), isNull);
    });
  });

  group('compareVersions', () {
    test('数值比较而非字典序', () {
      expect(compareVersions('1.0.9', '1.0.10'), lessThan(0));
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });
    test('相等与 v 前缀', () {
      expect(compareVersions('v1.0.77', '1.0.77'), 0);
    });
  });

  group('shouldUpdate', () {
    test('有新版才提醒', () {
      expect(shouldUpdate('1.0.77', '1.0.78', null), isTrue);
      expect(shouldUpdate('1.0.77', '1.0.77', null), isFalse);
      expect(shouldUpdate('1.0.78', '1.0.77', null), isFalse);
    });
    test('跳过版本只压住该版本', () {
      expect(shouldUpdate('1.0.77', '1.0.78', '1.0.78'), isFalse);
      expect(shouldUpdate('1.0.77', '1.0.79', '1.0.78'), isTrue);
      expect(shouldUpdate('1.0.77', '1.0.78', ''), isTrue);
      expect(shouldUpdate('1.0.77', '1.0.78', '坏值'), isTrue);
    });
    test('非法版本一律不提醒', () {
      expect(shouldUpdate('', '1.0.78', null), isFalse);
      expect(shouldUpdate('1.0.77', 'nightly', null), isFalse);
    });
  });

  group('parseRelease / assetFor', () {
    final json = {
      'tag_name': 'v1.0.78',
      'html_url': 'https://github.com/afret0/onenote/releases/tag/v1.0.78',
      'assets': [
        {
          'name': 'onenote_1.0.78.dmg',
          'browser_download_url': 'https://x/dmg',
          'size': 56370605
        },
        {
          'name': 'onenote_1.0.78.apk',
          'browser_download_url': 'https://x/apk',
          'size': 52677895
        },
        {
          'name': 'onenote_1.0.78_web.zip',
          'browser_download_url': 'https://x/web',
          'size': 1
        },
        {
          'name': 'onenote_1.0.78_windows.zip',
          'browser_download_url': 'https://x/win',
          'size': 42458987
        },
      ],
    };

    test('解析 tag 与资产', () {
      final r = parseRelease(json)!;
      expect(r.version, '1.0.78');
      expect(r.assets, hasLength(4));
      expect(r.assetFor('macos')?.url, 'https://x/dmg');
      expect(r.assetFor('android')?.url, 'https://x/apk');
      expect(r.assetFor('windows')?.url, 'https://x/win');
      expect(r.assetFor('web'), isNull);
      expect(r.assetFor('linux'), isNull);
    });
    test('非法 tag 返回 null', () {
      expect(parseRelease({'tag_name': 'nightly'}), isNull);
      expect(parseRelease({}), isNull);
    });
    test('缺资产可解析但选不出', () {
      final r = parseRelease({'tag_name': 'v1.0.78'})!;
      expect(r.assets, isEmpty);
      expect(r.assetFor('macos'), isNull);
    });
  });
}