class ShellBgShapeKind {
  const ShellBgShapeKind(this.id, this.name);

  final String id;
  final String name;
}

const shellBgShapeKinds = <ShellBgShapeKind>[
  ShellBgShapeKind('blob', '大圆'),
  ShellBgShapeKind('ring', '圆环'),
  ShellBgShapeKind('dot', '散点'),
  ShellBgShapeKind('wave', '波浪'),
  ShellBgShapeKind('tri', '圆角三角'),
  ShellBgShapeKind('square', '圆角方块'),
  ShellBgShapeKind('plus', '十字'),
  ShellBgShapeKind('sparkle', '四角星芒'),
  ShellBgShapeKind('arc', '圆弧'),
  ShellBgShapeKind('hex', '六边形'),
  ShellBgShapeKind('semi', '半圆'),
  ShellBgShapeKind('squiggle', '波浪线'),
];

const shellBgAllShapeIds = <String>[
  'blob', 'ring', 'dot', 'wave',
  'tri', 'square', 'plus', 'sparkle', 'arc', 'hex', 'semi', 'squiggle',
];

bool isKnownShellBgShape(String id) {
  for (final kind in shellBgShapeKinds) {
    if (kind.id == id) {
      return true;
    }
  }
  return false;
}

String? sanitizeShellBgShapes(String? raw) {
  if (raw == null) {
    return null;
  }
  if (raw.isEmpty) {
    return '';
  }
  final seen = <String>{};
  for (final part in raw.split(',')) {
    if (!isKnownShellBgShape(part) || !seen.add(part)) {
      return null;
    }
  }
  return shellBgShapeKinds
      .where((k) => seen.contains(k.id))
      .map((k) => k.id)
      .join(',');
}