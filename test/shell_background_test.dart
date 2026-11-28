import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/bg_shape_kinds.dart';
import 'package:onenote/data/bg_theme.dart';
import 'package:onenote/ui/shell_background.dart';
import 'package:onenote/ui/theme.dart';

class _CountingCanvas implements Canvas {
  var circles = 0;
  var paths = 0;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  void drawPath(Path path, Paint paint) => paths++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('主题目录收录六套且 id 唯一', () {
    expect(shellBgThemes.length, 6);
    expect(shellBgThemes.map((t) => t.id).toSet().length, 6);
    expect(shellBgThemeOf(shellBgNone), isNull);
    expect(shellBgThemeOf('bogus'), isNull);
    expect(isKnownShellBgTheme(shellBgNone), isTrue);
    expect(isKnownShellBgTheme('bogus'), isFalse);
    for (final theme in shellBgThemes) {
      expect(shellBgThemeOf(theme.id), same(theme));
    }
  });

  test('同主题同明暗构图确定', () {
    for (final theme in shellBgThemes) {
      for (final dark in [true, false]) {
        final a = shellBgScene(theme, dark: dark);
        final b = shellBgScene(theme, dark: dark);
        expect(a.colors, b.colors);
        expect(a.blobs.map((e) => [e.cx, e.cy, e.r]),
            b.blobs.map((e) => [e.cx, e.cy, e.r]));
        expect(a.waves.map((e) => [e.base, e.amp, e.xs, e.ups]),
            b.waves.map((e) => [e.base, e.amp, e.xs, e.ups]));
        expect(
            a.shapes.map((e) => [e.kind, e.cx, e.cy, e.size, e.rot, e.stroke]),
            b.shapes.map((e) => [e.kind, e.cx, e.cy, e.size, e.rot, e.stroke]));
      }
    }
  });

  test('任何主题明暗两版文字对比度均不低于 4.5', () {
    for (final theme in shellBgThemes) {
      for (final dark in [true, false]) {
        final t = dark ? InkTokens.dark : InkTokens.light;
        final scene = shellBgScene(theme, dark: dark);
        expect(scene.blobs, isNotEmpty);
        expect(scene.rings, isNotEmpty);
        expect(scene.dots, isNotEmpty);
        expect(scene.waves, isNotEmpty);
        expect(scene.shapes.length, greaterThanOrEqualTo(8));
        expect(scene.shapes.map((e) => e.kind).toSet(),
            containsAll(['tri', 'square', 'plus', 'sparkle', 'arc', 'hex', 'semi', 'squiggle']));
        for (final color in scene.colors) {
          expect(contrastRatio(t.ink, color), greaterThanOrEqualTo(4.5),
              reason: '${theme.id} dark=$dark ink vs $color');
          expect(contrastRatio(t.inkMuted, color), greaterThanOrEqualTo(4.5),
              reason: '${theme.id} dark=$dark inkMuted vs $color');
        }
      }
    }
  });

  test('图案对纸色有可见色差', () {
    for (final theme in shellBgThemes) {
      for (final dark in [true, false]) {
        final paper = dark ? InkTokens.dark.paper : InkTokens.light.paper;
        var maxDelta = 0.0;
        for (final color in shellBgScene(theme, dark: dark).colors) {
          maxDelta = [
            maxDelta,
            (color.r * 255 - paper.r * 255).abs(),
            (color.g * 255 - paper.g * 255).abs(),
            (color.b * 255 - paper.b * 255).abs(),
          ].reduce((a, b) => a > b ? a : b);
        }
        expect(maxDelta, greaterThanOrEqualTo(6),
            reason: '${theme.id} dark=$dark 与纸色几乎无差异');
      }
    }
  });

  test('随机主题编解码可逆且非法串拒收', () {
    for (final seed in [1, 7, 99]) {
      final theme = randomShellBgTheme(Random(seed));
      final decoded = decodeShellBgTheme(encodeShellBgTheme(theme))!;
      expect(decoded.hue, theme.hue);
      expect(decoded.sat, theme.sat);
      expect(decoded.light, theme.light);
      expect(decoded.seed, theme.seed);
      expect(decoded.id, shellBgRandom);
    }
    expect(decodeShellBgTheme('bogus'), isNull);
    expect(decodeShellBgTheme('1,2,3'), isNull);
    expect(decodeShellBgTheme('1,2,3,4,5'), isNull);
    expect(decodeShellBgTheme('360,0.45,0.64,11'), isNull);
    expect(decodeShellBgTheme('-1,0.45,0.64,11'), isNull);
    expect(decodeShellBgTheme('200,0.9,0.64,11'), isNull);
    expect(decodeShellBgTheme('200,0.45,0.9,11'), isNull);
    expect(decodeShellBgTheme('200,0.45,0.64,-1'), isNull);
    expect(decodeShellBgTheme('200,0.45,0.64,2147483648'), isNull);
  });

  test('随机窄带任意色相明暗两版对比度均不低于 4.5', () {
    for (var hue = 0.0; hue < 360; hue += 5) {
      for (final sat in [bgRandomSatMin, bgRandomSatMax]) {
        for (final light in [bgRandomLightMin, bgRandomLightMax]) {
          final theme = ShellBgTheme(
              id: shellBgRandom,
              name: '随机图案',
              hue: hue,
              sat: sat,
              light: light,
              seed: 42);
          for (final dark in [true, false]) {
            final t = dark ? InkTokens.dark : InkTokens.light;
            for (final color in shellBgScene(theme, dark: dark).colors) {
              expect(contrastRatio(t.ink, color), greaterThanOrEqualTo(4.5),
                  reason: 'hue=$hue sat=$sat light=$light dark=$dark');
              expect(contrastRatio(t.inkMuted, color),
                  greaterThanOrEqualTo(4.5),
                  reason: 'hue=$hue sat=$sat light=$light dark=$dark');
            }
          }
        }
      }
    }
  });

  test('随机换种子或色相触发重绘而同参数不重绘', () {
    final a = randomShellBgTheme(Random(7));
    final same = decodeShellBgTheme(encodeShellBgTheme(a))!;
    final base = ShellBgPainter(theme: a, dark: true);
    expect(base.shouldRepaint(ShellBgPainter(theme: same, dark: true)),
        isFalse);
    expect(
        base.shouldRepaint(
            ShellBgPainter(theme: randomShellBgTheme(Random(8)), dark: true)),
        isTrue);
    final shifted = ShellBgTheme(
        id: a.id,
        name: a.name,
        hue: (a.hue + 30) % 360,
        sat: a.sat,
        light: a.light,
        seed: a.seed);
    expect(base.shouldRepaint(ShellBgPainter(theme: shifted, dark: true)),
        isTrue);
  });

  test('形状目录十二种 id 唯一且清洗保持目录序', () {
    expect(shellBgShapeKinds.length, 12);
    expect(shellBgShapeKinds.map((k) => k.id).toSet(),
        shellBgAllShapeIds.toSet());
    expect(isKnownShellBgShape('blob'), isTrue);
    expect(isKnownShellBgShape('bogus'), isFalse);
    expect(sanitizeShellBgShapes(null), isNull);
    expect(sanitizeShellBgShapes(''), '');
    expect(sanitizeShellBgShapes('bogus,tri'), isNull);
    expect(sanitizeShellBgShapes('tri,tri'), isNull);
    expect(sanitizeShellBgShapes('tri,blob,tri'), isNull);
    expect(sanitizeShellBgShapes('tri,blob'), 'blob,tri');
    expect(sanitizeShellBgShapes(shellBgAllShapeIds.reversed.join(',')),
        shellBgAllShapeIds.join(','));
  });

  test('未启用形状不绘制且启用项位置不变', () {
    final theme = shellBgThemeOf(shellBgLavender)!;
    final scene = shellBgScene(theme, dark: true);
    const size = Size(1000, 800);

    final all = _CountingCanvas();
    ShellBgPainter(theme: theme, dark: true).paint(all, size);
    expect(all.circles,
        scene.blobs.length + scene.rings.length + scene.dots.length);
    expect(all.paths, greaterThan(scene.waves.length));

    final off = _CountingCanvas();
    ShellBgPainter(theme: theme, dark: true, enabled: <String>{})
        .paint(off, size);
    expect(off.circles, 0);
    expect(off.paths, 0);

    final onlyRing = _CountingCanvas();
    ShellBgPainter(theme: theme, dark: true, enabled: {'ring'})
        .paint(onlyRing, size);
    expect(onlyRing.circles, scene.rings.length);
    expect(onlyRing.paths, 0);

    final onlyTri = _CountingCanvas();
    ShellBgPainter(theme: theme, dark: true, enabled: {'tri'})
        .paint(onlyTri, size);
    expect(onlyTri.circles, 0);
    expect(onlyTri.paths,
        scene.shapes.where((s) => s.kind == 'tri').length);
  });

  test('形状开关变化触发重绘而顺序无关', () {
    final theme = shellBgThemeOf(shellBgLavender)!;
    final base = ShellBgPainter(theme: theme, dark: true, enabled: {'tri'});
    expect(
        base.shouldRepaint(
            ShellBgPainter(theme: theme, dark: true, enabled: {'tri'})),
        isFalse);
    expect(
        base.shouldRepaint(
            ShellBgPainter(theme: theme, dark: true, enabled: {'tri', 'hex'})),
        isTrue);
    expect(
        base.shouldRepaint(ShellBgPainter(theme: theme, dark: true)),
        isTrue);
    final full = ShellBgPainter(
        theme: theme, dark: true, enabled: shellBgAllShapeIds.toSet());
    expect(
        full.shouldRepaint(ShellBgPainter(
            theme: theme,
            dark: true,
            enabled: shellBgAllShapeIds.reversed.toSet())),
        isFalse);
  });
}