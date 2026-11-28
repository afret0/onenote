import 'dart:math';

class ShellBgTheme {
  const ShellBgTheme({
    required this.id,
    required this.name,
    required this.hue,
    required this.sat,
    required this.light,
    required this.seed,
  });

  final String id;
  final String name;
  final double hue;
  final double sat;
  final double light;
  final int seed;
}

const shellBgNone = 'none';
const shellBgRandom = 'random';
const shellBgLavender = 'lavender';
const shellBgIndigo = 'indigo';
const shellBgCeladon = 'celadon';
const shellBgAmber = 'amber';
const shellBgRose = 'rose';
const shellBgGraphite = 'graphite';

const shellBgThemes = <ShellBgTheme>[
  ShellBgTheme(
      id: shellBgLavender,
      name: '薰衣草紫',
      hue: 282,
      sat: 0.42,
      light: 0.66,
      seed: 11),
  ShellBgTheme(
      id: shellBgIndigo,
      name: '黛蓝',
      hue: 217,
      sat: 0.45,
      light: 0.62,
      seed: 23),
  ShellBgTheme(
      id: shellBgCeladon,
      name: '青瓷绿',
      hue: 162,
      sat: 0.40,
      light: 0.60,
      seed: 37),
  ShellBgTheme(
      id: shellBgAmber,
      name: '暮橙',
      hue: 28,
      sat: 0.52,
      light: 0.64,
      seed: 53),
  ShellBgTheme(
      id: shellBgRose,
      name: '绯樱粉',
      hue: 345,
      sat: 0.42,
      light: 0.68,
      seed: 71),
  ShellBgTheme(
      id: shellBgGraphite,
      name: '墨灰',
      hue: 270,
      sat: 0.08,
      light: 0.62,
      seed: 89),
];

ShellBgTheme? shellBgThemeOf(String id) {
  for (final theme in shellBgThemes) {
    if (theme.id == id) {
      return theme;
    }
  }
  return null;
}

bool isKnownShellBgTheme(String id) =>
    id == shellBgNone || shellBgThemeOf(id) != null;

const bgRandomSatMin = 0.40;
const bgRandomSatMax = 0.52;
const bgRandomLightMin = 0.60;
const bgRandomLightMax = 0.68;
const bgRandomSeedMax = 0x7FFFFFFF;

double _roundTo(double value, int places) {
  final factor = pow(10, places).toDouble();
  return (value * factor).roundToDouble() / factor;
}

ShellBgTheme randomShellBgTheme(Random rng) {
  final hue = _roundTo(rng.nextDouble() * 360, 2) % 360;
  final sat = _roundTo(
      bgRandomSatMin + rng.nextDouble() * (bgRandomSatMax - bgRandomSatMin), 4);
  final light = _roundTo(
      bgRandomLightMin + rng.nextDouble() * (bgRandomLightMax - bgRandomLightMin),
      4);
  return ShellBgTheme(
      id: shellBgRandom,
      name: '随机图案',
      hue: hue,
      sat: sat,
      light: light,
      seed: rng.nextInt(bgRandomSeedMax + 1));
}

String encodeShellBgTheme(ShellBgTheme theme) =>
    '${theme.hue.toStringAsFixed(2)},${theme.sat.toStringAsFixed(4)},'
    '${theme.light.toStringAsFixed(4)},${theme.seed}';

ShellBgTheme? decodeShellBgTheme(String raw) {
  final parts = raw.split(',');
  if (parts.length != 4) {
    return null;
  }
  final hue = double.tryParse(parts[0]);
  final sat = double.tryParse(parts[1]);
  final light = double.tryParse(parts[2]);
  final seed = int.tryParse(parts[3]);
  if (hue == null ||
      sat == null ||
      light == null ||
      seed == null ||
      !hue.isFinite ||
      !sat.isFinite ||
      !light.isFinite ||
      hue < 0 ||
      hue >= 360 ||
      sat < bgRandomSatMin ||
      sat > bgRandomSatMax ||
      light < bgRandomLightMin ||
      light > bgRandomLightMax ||
      seed < 0 ||
      seed > bgRandomSeedMax) {
    return null;
  }
  return ShellBgTheme(
      id: shellBgRandom,
      name: '随机图案',
      hue: hue,
      sat: sat,
      light: light,
      seed: seed);
}