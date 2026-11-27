import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/bg_theme.dart';
import 'package:onenote/ui/shell_background.dart';
import 'package:onenote/ui/theme.dart';

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
}