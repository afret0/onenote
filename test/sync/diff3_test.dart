import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/sync/diff3.dart';

void main() {
  group('diff3Merge 无冲突路径', () {
    final cases = <({String name, String base, String local, String remote, String merged})>[
      (
        name: '三方一致',
        base: 'abc',
        local: 'abc',
        remote: 'abc',
        merged: 'abc',
      ),
      (
        name: '只有远端改动',
        base: 'line1\nline2\nline3\n',
        local: 'line1\nline2\nline3\n',
        remote: 'line1\nremote\nline3\n',
        merged: 'line1\nremote\nline3\n',
      ),
      (
        name: '只有本地改动',
        base: 'line1\nline2\nline3\n',
        local: 'line1\nlocal\nline3\n',
        remote: 'line1\nline2\nline3\n',
        merged: 'line1\nlocal\nline3\n',
      ),
      (
        name: '双端改动不同行自动合并',
        base: 'aaa\nbbb\nccc\nddd\n',
        local: 'AAA\nbbb\nccc\nddd\n',
        remote: 'aaa\nbbb\nccc\nDDD\n',
        merged: 'AAA\nbbb\nccc\nDDD\n',
      ),
      (
        name: '双端做了相同改动',
        base: 'aaa\nbbb\n',
        local: 'aaa\nBBB\n',
        remote: 'aaa\nBBB\n',
        merged: 'aaa\nBBB\n',
      ),
      (
        name: '双端在不同位置追加',
        base: 'mid\n',
        local: 'head\nmid\n',
        remote: 'mid\ntail\n',
        merged: 'head\nmid\ntail\n',
      ),
      (
        name: '基线为空双端各写不同内容成冲突外全空',
        base: '',
        local: '',
        remote: 'remote only\n',
        merged: 'remote only\n',
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        final result = diff3Merge(c.base, c.local, c.remote);
        expect(result.hasConflict, isFalse, reason: c.name);
        expect(result.autoMerged, c.merged, reason: c.name);
      });
    }
  });

  group('diff3Merge 冲突路径', () {
    test('同一行双端不同改动产生冲突块', () {
      final result = diff3Merge(
        'head\nbase line\ntail\n',
        'head\nlocal line\ntail\n',
        'head\nremote line\ntail\n',
      );
      expect(result.hasConflict, isTrue);
      expect(result.conflictCount, 1);
      expect(result.mergedWith([true]), 'head\nlocal line\ntail\n');
      expect(result.mergedWith([false]), 'head\nremote line\ntail\n');
    });

    test('冲突块做字符级公共前后缀裁剪', () {
      final result = diff3Merge(
        'prefix middle suffix\n',
        'prefix LOCAL suffix\n',
        'prefix REMOTE suffix\n',
      );
      expect(result.conflictCount, 1);
      final conflict =
          result.segments.firstWhere((s) => s.isConflict);
      expect(conflict.local!.contains('prefix'), isFalse);
      expect(conflict.local!.contains('suffix'), isFalse);
      expect(result.mergedWith([true]), 'prefix LOCAL suffix\n');
      expect(result.mergedWith([false]), 'prefix REMOTE suffix\n');
    });

    test('多个冲突块逐块裁决', () {
      final base = 'a1\nsep\na2\n';
      final local = 'L1\nsep\nL2\n';
      final remote = 'R1\nsep\nR2\n';
      final result = diff3Merge(base, local, remote);
      expect(result.conflictCount, 2);
      expect(result.mergedWith([true, false]), 'L1\nsep\nR2\n');
      expect(result.mergedWith([false, true]), 'R1\nsep\nL2\n');
    });

    test('本地删除远端修改同一区域成冲突', () {
      final result = diff3Merge(
        'keep\ndelete me\nkeep2\n',
        'keep\nkeep2\n',
        'keep\nedited\nkeep2\n',
      );
      expect(result.hasConflict, isTrue);
      expect(result.mergedWith([true]), 'keep\nkeep2\n');
      expect(result.mergedWith([false]), 'keep\nedited\nkeep2\n');
    });

    test('裁决数组缺省时冲突块默认取本地', () {
      final result = diff3Merge('x\n', 'L\n', 'R\n');
      expect(result.hasConflict, isTrue);
      expect(result.autoMerged, 'L\n');
    });

    test('正文永不出现冲突标记', () {
      final result = diff3Merge('x\n', '<<<<<<< L\n', 'R\n');
      final merged = result.mergedWith([false]);
      expect(merged.contains('<<<<<<<'), isFalse);
      expect(merged, 'R\n');
    });
  });

  group('diff3Merge 边界', () {
    test('三方全空', () {
      final result = diff3Merge('', '', '');
      expect(result.hasConflict, isFalse);
      expect(result.autoMerged, '');
    });

    test('基线为空双端写入不同内容', () {
      final result = diff3Merge('', 'local text', 'remote text');
      expect(result.hasConflict, isTrue);
      expect(result.mergedWith([true]), 'local text');
      expect(result.mergedWith([false]), 'remote text');
    });

    test('中文内容按字符合并不破坏码元', () {
      final result = diff3Merge(
        '第一行\n第二行\n第三行\n',
        '第一行\n本地改\n第三行\n',
        '第一行\n第二行\n远端改\n',
      );
      expect(result.hasConflict, isFalse);
      expect(result.autoMerged, '第一行\n本地改\n远端改\n');
    });
  });
}