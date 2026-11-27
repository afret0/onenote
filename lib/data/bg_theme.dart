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