import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'app_db.dart';
import 'font_catalog.dart';

typedef FontFetcher = Future<Uint8List> Function(String url,
    {void Function(int received, int total)? onProgress});

typedef FontRegistrar = Future<void> Function(
    String family, Map<int, Uint8List> weights);

class LocalFont {
  LocalFont({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    this.catalogId,
    Map<int, String>? weights,
  }) : weights = weights ?? {};

  final String id;
  final String name;
  final String kind;
  final String? catalogId;
  final int createdAt;
  final Map<int, String> weights;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'catalogId': catalogId,
        'createdAt': createdAt,
        'weights': weights.map((w, file) => MapEntry('$w', file)),
      };

  static LocalFont fromJson(Map<String, dynamic> json) => LocalFont(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        catalogId: json['catalogId'] as String?,
        createdAt: json['createdAt'] as int? ?? 0,
        weights: (json['weights'] as Map? ?? {})
            .map((k, v) => MapEntry(int.parse('$k'), v as String)),
      );
}

class LocalFontStore {
  LocalFontStore._(this.root)
      : fetcher = _httpFetch,
        registrar = _loadViaEngine;

  LocalFontStore.forTest(this.root, {FontFetcher? fetcher, FontRegistrar? registrar})
      : fetcher = fetcher ?? _httpFetch,
        registrar = registrar ?? _loadViaEngine;

  final Directory root;
  final FontFetcher fetcher;
  final FontRegistrar registrar;
  final List<LocalFont> fonts = [];
  AppDb? _db;

  static const importKind = 'import';
  static const downloadKind = 'download';

  static String familyOf(String id) => 'LocalFont:$id';

  static Future<LocalFontStore> open() async {
    if (kIsWeb) {
      throw UnsupportedError('local fonts are not available on web yet');
    }
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/fonts');
    await root.create(recursive: true);
    return LocalFontStore._(root);
  }

  bool has(String id) => fonts.any((f) => f.id == id);

  LocalFont? byId(String id) {
    for (final f in fonts) {
      if (f.id == id) {
        return f;
      }
    }
    return null;
  }

  Future<void> loadRegistry(AppDb db) async {
    _db = db;
    fonts.clear();
    final raw = await db.getSetting(AppDb.localFontsKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
      for (final item in list) {
        final font = LocalFont.fromJson(item as Map<String, dynamic>);
        font.weights.removeWhere((w, file) => !File('${root.path}/$file').existsSync());
        if (font.weights.isEmpty) {
          developer.log('skip, 本地字体文件缺失剔除注册项, name: ${font.name}, id: ${font.id}');
          continue;
        }
        fonts.add(font);
      }
    } catch (err) {
      developer.log('fail, 本地字体注册表解析失败, err: $err');
    }
  }

  Future<void> registerAll() async {
    for (final font in fonts) {
      await _register(font);
    }
  }

  Future<List<LocalFont>> importFiles(List<String> paths) async {
    final touched = <LocalFont>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        developer.log('skip, 导入字体文件不存在, path: $path');
        continue;
      }
      final base = file.uri.pathSegments.last;
      final (name, weight) = parseFontFileName(base);
      LocalFont? entry;
      for (final f in fonts) {
        if (f.name == name) {
          entry = f;
          break;
        }
      }
      if (entry == null) {
        entry = LocalFont(
            id: const Uuid().v4(),
            name: name,
            kind: importKind,
            createdAt: DateTime.now().millisecondsSinceEpoch);
        fonts.add(entry);
      }
      final ext = base.toLowerCase().endsWith('.otf') ? '.otf' : '.ttf';
      final dest = '${entry.id}-$weight$ext';
      await file.copy('${root.path}/$dest');
      entry.weights[weight] = dest;
      if (!touched.contains(entry)) {
        touched.add(entry);
      }
      developer.log('done, 字体文件已导入, name: $name, weight: $weight, file: $dest');
    }
    if (touched.isEmpty) {
      return touched;
    }
    await _persist();
    for (final entry in touched) {
      await _register(entry);
    }
    return touched;
  }

  Future<LocalFont> download(FontCatalogEntry catalog,
      {void Function(int received, int total)? onProgress}) async {
    final stale = fonts.where((f) => f.catalogId == catalog.id).toList();
    for (final font in stale) {
      await delete(font.id);
    }
    final entry = LocalFont(
        id: const Uuid().v4(),
        name: catalog.name,
        kind: downloadKind,
        catalogId: catalog.id,
        createdAt: DateTime.now().millisecondsSinceEpoch);
    if (catalog.isZip) {
      final bytes = await fetcher(catalog.zipUrl, onProgress: onProgress);
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in catalog.files) {
        final member = archive.files.firstWhere(
            (m) => m.name == file.zipMember,
            orElse: () => throw StateError('zip member missing: ${file.zipMember}'));
        final dest = '${entry.id}-${file.weight}${_extOf(file.fileName)}';
        await File('${root.path}/$dest')
            .writeAsBytes(Uint8List.fromList(member.content as List<int>));
        entry.weights[file.weight] = dest;
      }
      if (catalog.licenseZipMember.isNotEmpty) {
        for (final member in archive.files) {
          if (member.name == catalog.licenseZipMember) {
            await File('${root.path}/${entry.id}-LICENSE.txt')
                .writeAsBytes(Uint8List.fromList(member.content as List<int>));
            break;
          }
        }
      }
    } else {
      var receivedBase = 0;
      for (final file in catalog.files) {
        final bytes = await fetcher(file.url,
            onProgress: (received, total) =>
                onProgress?.call(receivedBase + received, catalog.downloadBytes));
        final dest = '${entry.id}-${file.weight}${_extOf(file.fileName)}';
        await File('${root.path}/$dest').writeAsBytes(bytes);
        entry.weights[file.weight] = dest;
        receivedBase += bytes.length;
      }
    }
    if (catalog.licenseZipMember.isEmpty && catalog.licenseUrl.isNotEmpty) {
      final license = await fetcher(catalog.licenseUrl);
      await File('${root.path}/${entry.id}-LICENSE.txt').writeAsBytes(license);
    }
    fonts.add(entry);
    await _persist();
    await _register(entry);
    developer.log('done, 在线字体已安装, name: ${entry.name}, weights: ${entry.weights.keys.toList()}');
    return entry;
  }

  Future<void> delete(String id) async {
    final entry = byId(id);
    if (entry == null) {
      return;
    }
    for (final name in entry.weights.values) {
      final file = File('${root.path}/$name');
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    final license = File('${root.path}/$id-LICENSE.txt');
    if (license.existsSync()) {
      license.deleteSync();
    }
    fonts.removeWhere((f) => f.id == id);
    await _persist();
    developer.log('done, 本地字体已删除, name: ${entry.name}, id: $id');
  }

  Future<void> _register(LocalFont font) async {
    final weights = <int, Uint8List>{};
    for (final item in font.weights.entries) {
      weights[item.key] = await File('${root.path}/${item.value}').readAsBytes();
    }
    await registrar(familyOf(font.id), weights);
  }

  Future<void> _persist() async {
    final db = _db;
    if (db == null) {
      return;
    }
    await db.setSetting(
        AppDb.localFontsKey, jsonEncode(fonts.map((f) => f.toJson()).toList()));
  }

  static String _extOf(String fileName) =>
      fileName.toLowerCase().endsWith('.otf') ? '.otf' : '.ttf';

  static const _weightTokens = <String, int>{
    'extralight': 200,
    'ultralight': 200,
    'thin': 100,
    'semilight': 350,
    'demilight': 350,
    'light': 300,
    'regular': 400,
    'normal': 400,
    'roman': 400,
    'book': 400,
    'medium': 500,
    'semibold': 600,
    'demibold': 600,
    'extrabold': 800,
    'ultrabold': 800,
    'bold': 700,
    'black': 900,
    'heavy': 900,
  };

  static (String, int) parseFontFileName(String fileName) {
    final base =
        fileName.replaceFirst(RegExp(r'\.(ttf|otf)$', caseSensitive: false), '');
    var weight = 400;
    String? matched;
    final numeric = RegExp(
            r'[-_ ](100|200|250|300|350|400|450|500|600|700|800|900)$')
        .firstMatch(base);
    if (numeric != null) {
      weight = int.parse(numeric.group(1)!);
      matched = numeric.group(0)!;
    } else {
      for (final token in _weightTokens.entries) {
        final m = RegExp('[-_ ]${token.key}\$', caseSensitive: false)
            .firstMatch(base);
        if (m != null) {
          weight = token.value;
          matched = m.group(0)!;
          break;
        }
      }
    }
    var name = base;
    if (matched != null) {
      name = base.substring(0, base.length - matched.length);
    }
    name = name.replaceAll(RegExp(r'[-_ ]+$'), '');
    if (name.isEmpty) {
      name = base;
    }
    return (name, weight);
  }

  static Future<Uint8List> _httpFetch(String url,
      {void Function(int received, int total)? onProgress}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final total = response.contentLength;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response) {
        builder.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  static Future<void> _loadViaEngine(
      String family, Map<int, Uint8List> weights) async {
    final loader = FontLoader(family);
    for (final bytes in weights.values) {
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}