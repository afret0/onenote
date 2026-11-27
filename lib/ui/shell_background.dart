import 'package:flutter/material.dart';

import '../data/bg_theme.dart';

const int _blobDarkW = 92;
const int _blobLightW = 84;
const int _ringDarkW = 90;
const int _ringLightW = 80;
const int _dotDarkW = 88;
const int _dotLightW = 78;
const int _waveDarkW = 93;
const int _waveLightW = 86;

class ShellBgCircle {
  const ShellBgCircle(this.cx, this.cy, this.r, this.color);

  final double cx;
  final double cy;
  final double r;
  final Color color;
}

class ShellBgRing {
  const ShellBgRing(this.cx, this.cy, this.r, this.stroke, this.color);

  final double cx;
  final double cy;
  final double r;
  final double stroke;
  final Color color;
}

class ShellBgWave {
  const ShellBgWave(this.base, this.amp, this.xs, this.ups, this.color);

  final double base;
  final double amp;
  final List<double> xs;
  final List<bool> ups;
  final Color color;
}

class ShellBgScene {
  const ShellBgScene(this.blobs, this.rings, this.dots, this.waves);

  final List<ShellBgCircle> blobs;
  final List<ShellBgRing> rings;
  final List<ShellBgCircle> dots;
  final List<ShellBgWave> waves;

  List<Color> get colors => [
        for (final b in blobs) b.color,
        for (final r in rings) r.color,
        for (final d in dots) d.color,
        for (final w in waves) w.color,
      ];
}

class _Lcg {
  _Lcg(int seed) : _s = seed & 0xFFFFFFFF;

  int _s;

  double next() {
    _s = (_s * 1664525 + 1013904223) & 0xFFFFFFFF;
    return _s / 4294967296;
  }

  double range(double lo, double hi) => lo + next() * (hi - lo);
}

Color _elementColor(
    _Lcg r, ShellBgTheme theme, bool dark, double drift, int darkW, int lightW) {
  var hue = (theme.hue + r.range(-drift, drift)) % 360;
  if (hue < 0) {
    hue += 360;
  }
  final c =
      HSLColor.fromAHSL(1, hue, theme.sat, theme.light).toColor();
  final w = dark ? darkW : lightW;
  int mixCh(int ch, int base) =>
      dark ? ch - ((ch - base) * w ~/ 100) : ch + ((255 - ch) * w ~/ 100);
  return Color.fromARGB(
    255,
    mixCh((c.r * 255).round(), 17),
    mixCh((c.g * 255).round(), 17),
    mixCh((c.b * 255).round(), 19),
  );
}

ShellBgScene shellBgScene(ShellBgTheme theme, {required bool dark}) {
  final r = _Lcg(theme.seed);
  final blobs = <ShellBgCircle>[];
  final blobCount = 2 + (r.next() * 2).floor();
  final blobSlot = 1.0 / blobCount;
  for (var i = 0; i < blobCount; i++) {
    final cx = (i + r.range(0.25, 0.75)) * blobSlot;
    final cy = r.range(0.80, 1.05);
    final rad = r.range(0.34, 0.60);
    blobs.add(ShellBgCircle(
        cx, cy, rad, _elementColor(r, theme, dark, 24, _blobDarkW, _blobLightW)));
  }
  final rings = <ShellBgRing>[];
  final ringCount = 1 + (r.next() * 3).floor();
  final ringSlot = 1.0 / ringCount;
  for (var i = 0; i < ringCount; i++) {
    final cx = (i + r.range(0.10, 0.90)) * ringSlot;
    final cy = r.range(0.08, 0.42);
    final rad = r.range(0.09, 0.20);
    final stroke = r.range(0.012, 0.026);
    rings.add(ShellBgRing(cx, cy, rad, stroke,
        _elementColor(r, theme, dark, 24, _ringDarkW, _ringLightW)));
  }
  final dots = <ShellBgCircle>[];
  final dotCount = 5 + (r.next() * 8).floor();
  for (var i = 0; i < dotCount; i++) {
    final cx = r.next();
    final cy = r.range(0.16, 0.80);
    final rad = r.range(0.004, 0.009);
    dots.add(ShellBgCircle(
        cx, cy, rad, _elementColor(r, theme, dark, 30, _dotDarkW, _dotLightW)));
  }
  final waves = <ShellBgWave>[];
  final waveCount = 1 + (r.next() * 2).floor();
  for (var i = 0; i < waveCount; i++) {
    final base = r.range(0.90, 0.97);
    final amp = r.range(0.015, 0.05);
    final xs = <double>[
      r.range(0.10, 0.30),
      r.range(0.32, 0.50),
      r.range(0.52, 0.68),
      r.range(0.72, 0.86),
      r.range(0.88, 0.98),
    ];
    final ups = <bool>[
      r.next() < 0.5,
      r.next() < 0.5,
      r.next() < 0.5,
      r.next() < 0.5,
    ];
    waves.add(ShellBgWave(base, amp, xs, ups,
        _elementColor(r, theme, dark, 18, _waveDarkW, _waveLightW)));
  }
  return ShellBgScene(blobs, rings, dots, waves);
}

class ShellBgPainter extends CustomPainter {
  ShellBgPainter({required this.theme, required this.dark});

  final ShellBgTheme theme;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final scene = shellBgScene(theme, dark: dark);
    final w = size.width;
    final h = size.height;
    for (final b in scene.blobs) {
      canvas.drawCircle(
          Offset(b.cx * w, b.cy * h), b.r * h, Paint()..color = b.color);
    }
    for (final ring in scene.rings) {
      canvas.drawCircle(
        Offset(ring.cx * w, ring.cy * h),
        ring.r * h,
        Paint()
          ..color = ring.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.stroke * h,
      );
    }
    for (final d in scene.dots) {
      canvas.drawCircle(
          Offset(d.cx * w, d.cy * h), d.r * h, Paint()..color = d.color);
    }
    for (final wave in scene.waves) {
      final base = wave.base * h;
      final amp = wave.amp * h;
      double cy(int i) => base + (wave.ups[i] ? -amp : amp);
      final path = Path()
        ..moveTo(-0.05 * w, h + 4)
        ..lineTo(-0.05 * w, base)
        ..cubicTo(wave.xs[0] * w, cy(0), wave.xs[1] * w, cy(1),
            wave.xs[2] * w, base)
        ..cubicTo(wave.xs[3] * w, cy(2), wave.xs[4] * w, cy(3), 1.05 * w, base)
        ..lineTo(1.05 * w, h + 4)
        ..close();
      canvas.drawPath(path, Paint()..color = wave.color);
    }
  }

  @override
  bool shouldRepaint(covariant ShellBgPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.theme.id != theme.id;
}

class ShellBackground extends StatelessWidget {
  const ShellBackground({super.key, required this.themeId});

  final String themeId;

  @override
  Widget build(BuildContext context) {
    final theme = shellBgThemeOf(themeId);
    if (theme == null) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: ShellBgPainter(theme: theme, dark: dark),
          isComplex: true,
        ),
      ),
    );
  }
}