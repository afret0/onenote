import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/window_metrics.dart';

void main() {
  group('scaledDefaultWindowSize', () {
    const cases = <(Size, Size)>[
      (Size(1920, 1080), Size(1300, 800)),
      (Size(3840, 2160), Size(1300, 800)),
      (Size(1440, 900), Size(975, 600)),
      (Size(1512, 945), Size(1024, 630)),
      (Size(1280, 1024), Size(867, 533)),
      (Size(1920, 900), Size(1083, 667)),
      (Size(960, 540), Size(650, 400)),
    ];
    for (final (screen, expected) in cases) {
      test('screen $screen -> $expected', () {
        expect(scaledDefaultWindowSize(screen), expected);
      });
    }
  });

  group('fitWindowSize', () {
    const cases = <(Size, Size, Size)>[
      (Size(1000, 700), Size(1440, 900), Size(1000, 700)),
      (Size(1440, 900), Size(1440, 900), Size(1440, 900)),
      (Size(1300, 800), Size(1200, 800), Size(1200, 738)),
      (Size(1300, 800), Size(1280, 720), Size(1170, 720)),
    ];
    for (final (size, screen, expected) in cases) {
      test('size $size on $screen -> $expected', () {
        expect(fitWindowSize(size, screen), expected);
      });
    }
  });

  group('parseWindowSize', () {
    test('valid', () {
      expect(parseWindowSize('1300x800'), const Size(1300, 800));
      expect(parseWindowSize('975x600'), const Size(975, 600));
    });
    test('invalid falls back to null', () {
      expect(parseWindowSize(null), isNull);
      expect(parseWindowSize(''), isNull);
      expect(parseWindowSize('1300'), isNull);
      expect(parseWindowSize('axb'), isNull);
      expect(parseWindowSize('0x800'), isNull);
      expect(parseWindowSize('-5x800'), isNull);
      expect(parseWindowSize('1x2x3'), isNull);
    });
  });

  test('formatWindowSize rounds to ints', () {
    expect(formatWindowSize(const Size(1300, 800)), '1300x800');
    expect(formatWindowSize(const Size(975.4, 600.6)), '975x601');
  });
}
