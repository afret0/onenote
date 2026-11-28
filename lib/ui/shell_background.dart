import 'dart:math';

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

class ShellBgShape {
  const ShellBgShape(this.kind, this.cx, this.cy, this.size, this.rot,
      this.stroke, this.color);

  final String kind;
  final double cx;
  final double cy;
  final double size;
  final double rot;
  final double stroke;
  final Color color;
}

class ShellBgScene {
  const ShellBgScene(this.blobs, this.rings, this.dots, this.waves, this.shapes);

  final List<ShellBgCircle> blobs;
  final List<ShellBgRing> rings;
  final List<ShellBgCircle> dots;
  final List<ShellBgWave> waves;
  final List<ShellBgShape> shapes;

  List<Color> get colors => [
        for (final b in blobs) b.color,
        for (final r in rings) r.color,
        for (final d in dots) d.color,
        for (final w in waves) w.color,
        for (final s in shapes) s.color,
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
  final kinds = <String>[];
  void push(String kind, int n) {
    for (var i = 0; i < n; i++) {
      kinds.add(kind);
    }
  }

  push('tri', 1 + (r.next() * 2).floor());
  push('square', 1 + (r.next() * 2).floor());
  push('plus', 1);
  push('sparkle', 1 + (r.next() * 2).floor());
  push('arc', 1 + (r.next() * 2).floor());
  push('hex', 1);
  push('semi', 1);
  push('squiggle', 1);
  for (var i = kinds.length - 1; i > 0; i--) {
    final j = (r.next() * (i + 1)).floor();
    final tmp = kinds[i];
    kinds[i] = kinds[j];
    kinds[j] = tmp;
  }
  final shapes = <ShellBgShape>[];
  final shapeSlot = 1.0 / kinds.length;
  for (var i = 0; i < kinds.length; i++) {
    final kind = kinds[i];
    final cx = (i + r.range(0.25, 0.75)) * shapeSlot;
    final cy = r.range(0.18, 0.68);
    final filled =
        kind == 'tri' || kind == 'plus' || kind == 'sparkle' || kind == 'semi';
    double size;
    double rot;
    var stroke = 0.0;
    switch (kind) {
      case 'tri':
        size = r.range(0.035, 0.065);
        rot = r.range(-0.4, 0.4);
      case 'square':
        size = r.range(0.028, 0.05);
        rot = r.range(-0.5, 0.5);
        stroke = r.range(0.007, 0.012);
      case 'plus':
        size = r.range(0.024, 0.04);
        rot = r.range(-0.3, 0.3);
      case 'sparkle':
        size = r.range(0.02, 0.038);
        rot = r.range(-0.3, 0.3);
      case 'arc':
        size = r.range(0.06, 0.11);
        rot = r.range(0, 6.28);
        stroke = r.range(0.008, 0.015);
      case 'hex':
        size = r.range(0.04, 0.065);
        rot = r.range(0, 1.05);
        stroke = r.range(0.007, 0.012);
      case 'semi':
        size = r.range(0.04, 0.065);
        rot = r.range(0, 6.28);
      default:
        size = r.range(0.035, 0.055);
        rot = r.range(-0.15, 0.15);
        stroke = r.range(0.006, 0.011);
    }
    shapes.add(ShellBgShape(
        kind,
        cx,
        cy,
        size,
        rot,
        stroke,
        _elementColor(r, theme, dark, 24,
            filled ? _blobDarkW : _ringDarkW,
            filled ? _blobLightW : _ringLightW)));
  }
  return ShellBgScene(blobs, rings, dots, waves, shapes);
}

class ShellBgPainter extends CustomPainter {
  ShellBgPainter({required this.theme, required this.dark, this.enabled});

  final ShellBgTheme theme;
  final bool dark;
  final Set<String>? enabled;

  bool _on(String kind) => enabled == null || enabled!.contains(kind);

  @override
  void paint(Canvas canvas, Size size) {
    final scene = shellBgScene(theme, dark: dark);
    final w = size.width;
    final h = size.height;
    if (_on('blob')) {
      for (final b in scene.blobs) {
        canvas.drawCircle(
            Offset(b.cx * w, b.cy * h), b.r * h, Paint()..color = b.color);
      }
    }
    if (_on('ring')) {
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
    }
    if (_on('dot')) {
      for (final d in scene.dots) {
        canvas.drawCircle(
            Offset(d.cx * w, d.cy * h), d.r * h, Paint()..color = d.color);
      }
    }
    if (_on('wave')) {
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
    for (final s in scene.shapes) {
      if (_on(s.kind)) {
        _paintShape(canvas, s, w, h);
      }
    }
  }

  void _paintShape(Canvas canvas, ShellBgShape s, double w, double h) {
    canvas.save();
    canvas.translate(s.cx * w, s.cy * h);
    canvas.rotate(s.rot);
    final size = s.size * h;
    final fill = Paint()..color = s.color;
    final line = Paint()
      ..color = s.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.stroke * h
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (s.kind) {
      case 'tri':
        canvas.drawPath(_roundedTriangle(size), fill);
      case 'square':
        final half = size * 0.8;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(-half, -half, half * 2, half * 2),
                Radius.circular(size * 0.35)),
            line);
      case 'plus':
        final arm = size;
        final thick = size * 0.36;
        final rad = Radius.circular(thick * 0.8);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(-arm, -thick, arm * 2, thick * 2), rad),
            fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(-thick, -arm, thick * 2, arm * 2), rad),
            fill);
      case 'sparkle':
        canvas.drawPath(_sparkle(size), fill);
      case 'arc':
        canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: size), 0,
            pi * 1.1, false, line);
      case 'hex':
        canvas.drawPath(_hexagon(size), line);
      case 'semi':
        final path = Path()
          ..addArc(Rect.fromCircle(center: Offset.zero, radius: size), pi, pi)
          ..close();
        canvas.drawPath(path, fill);
      default:
        canvas.drawPath(_squiggle(size), line);
    }
    canvas.restore();
  }

  Path _roundedTriangle(double size) {
    final pts = [
      Offset(-size * 0.9, size * 0.62),
      Offset(size * 0.9, size * 0.62),
      Offset(0, -size),
    ];
    final k = size * 0.22;
    Offset mid(int a, int b) =>
        Offset((pts[a].dx + pts[b].dx) / 2, (pts[a].dy + pts[b].dy) / 2);
    final path = Path()..moveTo(mid(0, 1).dx, mid(0, 1).dy);
    for (var i = 1; i <= 3; i++) {
      final corner = pts[i % 3];
      final next = mid(i % 3, (i + 1) % 3);
      final prev = mid((i + 2) % 3, i % 3);
      final toCorner = corner - prev;
      final dist = toCorner.distance;
      final p1 = corner - toCorner * (k / dist);
      final fromCorner = next - corner;
      final p2 = corner + fromCorner * (k / fromCorner.distance);
      path.lineTo(p1.dx, p1.dy);
      path.quadraticBezierTo(corner.dx, corner.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  Path _sparkle(double size) {
    final q = size * 0.22;
    return Path()
      ..moveTo(0, -size)
      ..quadraticBezierTo(q, -q, size, 0)
      ..quadraticBezierTo(q, q, 0, size)
      ..quadraticBezierTo(-q, q, -size, 0)
      ..quadraticBezierTo(-q, -q, 0, -size)
      ..close();
  }

  Path _hexagon(double size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = pi / 3 * i;
      final x = cos(a) * size;
      final y = sin(a) * size;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  Path _squiggle(double size) {
    final len = size * 4;
    final amp = size * 0.5;
    final path = Path()..moveTo(-len / 2, 0);
    for (var i = 0; i < 3; i++) {
      final x0 = -len / 2 + len * i / 3;
      final x1 = -len / 2 + len * (i + 1) / 3;
      path.quadraticBezierTo((x0 + x1) / 2, i.isEven ? amp : -amp, x1, 0);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant ShellBgPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.theme.id != theme.id ||
      oldDelegate.theme.hue != theme.hue ||
      oldDelegate.theme.sat != theme.sat ||
      oldDelegate.theme.light != theme.light ||
      oldDelegate.theme.seed != theme.seed ||
      !_sameEnabled(oldDelegate.enabled);

  bool _sameEnabled(Set<String>? other) {
    if (enabled == null || other == null) {
      return enabled == null && other == null;
    }
    return enabled!.length == other.length && enabled!.containsAll(other);
  }
}

class ShellBackground extends StatelessWidget {
  const ShellBackground({super.key, required this.theme, this.enabled});

  final ShellBgTheme? theme;
  final Set<String>? enabled;

  @override
  Widget build(BuildContext context) {
    final theme = this.theme;
    if (theme == null) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: ShellBgPainter(theme: theme, dark: dark, enabled: enabled),
          isComplex: true,
        ),
      ),
    );
  }
}