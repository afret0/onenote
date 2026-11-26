import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/app_version.dart';

void main() {
  test('parseAppVersion reads X.Y.Z and drops build number', () {
    const cases = <String, String>{
      'version: 1.0.50+2': 'v1.0.50',
      'name: x\nversion: 2.3.4+9\nenvironment:': 'v2.3.4',
      'version: 1.2.3': 'v1.2.3',
      '  version: 9.9.9+1': '',
      'name: x\ndescription: version: 1.0.0\n': '',
      '': '',
    };
    cases.forEach((input, want) {
      expect(parseAppVersion(input), want, reason: 'input: $input');
    });
  });
}