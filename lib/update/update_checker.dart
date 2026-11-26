import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

const updateSkippedVersionKey = 'updateSkippedVersion';
const updateRepoApiLatest =
    'https://api.github.com/repos/afret0/onenote/releases/latest';
const updateRepoReleasePage = 'https://github.com/afret0/onenote/releases/latest';

class UpdateAsset {
  const UpdateAsset({required this.name, required this.url, required this.size});

  final String name;
  final String url;
  final int size;
}

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.pageUrl,
    required this.assets,
  });

  final String version;
  final String pageUrl;
  final List<UpdateAsset> assets;

  UpdateAsset? assetFor(String platform) {
    final suffix = switch (platform) {
      'macos' => '.dmg',
      'android' => '.apk',
      'windows' => '_windows.zip',
      _ => '',
    };
    if (suffix.isEmpty) return null;
    for (final a in assets) {
      if (a.name.endsWith(suffix)) return a;
    }
    return null;
  }
}

List<int>? parseVersionParts(String version) {
  final v = version.startsWith('v') ? version.substring(1) : version;
  final parts = v.split('.');
  if (parts.length != 3) return null;
  final nums = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    nums.add(n);
  }
  return nums;
}

int compareVersions(String a, String b) {
  final pa = parseVersionParts(a);
  final pb = parseVersionParts(b);
  if (pa == null || pb == null) return 0;
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

bool shouldUpdate(String current, String latest, String? skipped) {
  if (parseVersionParts(current) == null ||
      parseVersionParts(latest) == null) {
    return false;
  }
  if (skipped != null &&
      parseVersionParts(skipped) != null &&
      compareVersions(latest, skipped) == 0) {
    return false;
  }
  return compareVersions(latest, current) > 0;
}

UpdateRelease? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  if (tag is! String || parseVersionParts(tag) == null) return null;
  final assets = <UpdateAsset>[];
  final rawAssets = json['assets'];
  if (rawAssets is List) {
    for (final a in rawAssets) {
      if (a is! Map<String, dynamic>) continue;
      final name = a['name'];
      final url = a['browser_download_url'];
      if (name is String && url is String) {
        assets.add(UpdateAsset(
            name: name, url: url, size: (a['size'] as num?)?.toInt() ?? 0));
      }
    }
  }
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  return UpdateRelease(
    version: version,
    pageUrl: (json['html_url'] as String?) ?? updateRepoReleasePage,
    assets: assets,
  );
}

Future<UpdateRelease?> fetchLatestRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(Uri.parse(updateRepoApiLatest), headers: {
      'Accept': 'application/vnd.github+json',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) {
      developer.log('skip, 仓库还没有 release');
      return null;
    }
    if (res.statusCode != 200) {
      developer.log('fail, 拉取 latest release 非 200, status: ${res.statusCode}');
      return null;
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is! Map<String, dynamic>) return null;
    return parseRelease(json);
  } catch (err) {
    developer.log('fail, 检查更新请求失败, err: $err');
    return null;
  } finally {
    if (client == null) c.close();
  }
}