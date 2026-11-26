import 'package:flutter/services.dart' show rootBundle;

const appVersionAssetKey = 'pubspec.yaml';

String parseAppVersion(String pubspecText) {
  final match = RegExp(r'^version:\s*([^\s+]+)', multiLine: true)
      .firstMatch(pubspecText);
  return match == null ? '' : 'v${match.group(1)}';
}

Future<String> loadAppVersion() async {
  try {
    return parseAppVersion(await rootBundle.loadString(appVersionAssetKey));
  } catch (_) {
    return '';
  }
}