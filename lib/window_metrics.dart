import 'dart:math' as math;
import 'dart:ui' show Size;

const designScreenWidth = 1920.0;
const designScreenHeight = 1080.0;
const defaultWindowWidth = 1300.0;
const defaultWindowHeight = 800.0;
const windowSizeSettingKey = 'windowSize';

Size scaledDefaultWindowSize(Size screen) {
  final scale = math.min(
    1,
    math.min(
        screen.width / designScreenWidth, screen.height / designScreenHeight),
  );
  return Size((defaultWindowWidth * scale).roundToDouble(),
      (defaultWindowHeight * scale).roundToDouble());
}

Size fitWindowSize(Size size, Size screen) {
  if (size.width <= screen.width && size.height <= screen.height) return size;
  final scale =
      math.min(screen.width / size.width, screen.height / size.height);
  return Size((size.width * scale).floorToDouble(),
      (size.height * scale).floorToDouble());
}

Size? parseWindowSize(String? raw) {
  if (raw == null) return null;
  final parts = raw.split('x');
  if (parts.length != 2) return null;
  final width = double.tryParse(parts[0]);
  final height = double.tryParse(parts[1]);
  if (width == null || height == null || width <= 0 || height <= 0) return null;
  return Size(width, height);
}

String formatWindowSize(Size size) =>
    '${size.width.round()}x${size.height.round()}';
