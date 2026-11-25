import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/app_db.dart';
import 'remote_store.dart';

class WebdavStore implements RemoteStore {
  WebdavStore({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.rootPath,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final String rootPath;
  final http.Client _client;

  bool _ready = false;
  final Set<String> _ensuredDirs = {};

  static String normalizeRoot(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '/onenote';
    }
    final withLead = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return withLead.endsWith('/')
        ? withLead.substring(0, withLead.length - 1)
        : withLead;
  }

  String get _auth =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final segments = [...rootPath.split('/'), ...path.split('/')]
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent);
    return Uri.parse('$base/${segments.join('/')}');
  }

  Uri _dirUri(String path) {
    final uri = _uri(path);
    return uri.replace(path: '${uri.path}/');
  }

  Future<void> _ensureParent(String path) async {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) {
      return;
    }
    final segments =
        path.substring(0, idx).split('/').where((s) => s.isNotEmpty).toList();
    final walked = <String>[];
    for (final segment in segments) {
      walked.add(segment);
      final joined = walked.join('/');
      if (_ensuredDirs.contains(joined)) {
        continue;
      }
      final request = http.Request('MKCOL', _dirUri(joined))
        ..headers['Authorization'] = _auth;
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(AppDb.syncRequestTimeout));
      if (response.statusCode >= 400 &&
          response.statusCode != 405 &&
          response.statusCode != 301) {
        developer.log(
            'fail, WebDAV 子目录创建失败, path: $joined, status: ${response.statusCode}');
        throw StateError('webdav mkcol $joined: ${response.statusCode}');
      }
      _ensuredDirs.add(joined);
    }
  }

  @override
  String get describe => 'WebDAV $baseUrl$rootPath';

  @override
  Future<void> ensureReady() async {
    if (_ready) {
      return;
    }
    final segments =
        rootPath.split('/').where((s) => s.isNotEmpty).toList();
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final walked = <String>[];
    for (final segment in segments) {
      walked.add(Uri.encodeComponent(segment));
      final uri = Uri.parse('$base/${walked.join('/')}/');
      final request = http.Request('MKCOL', uri)
        ..headers['Authorization'] = _auth;
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(AppDb.syncRequestTimeout));
      if (response.statusCode == 405 || response.statusCode == 301) {
        continue;
      }
      if (response.statusCode >= 400) {
        developer.log(
            'fail, WebDAV 目录创建失败, path: ${walked.join('/')}, status: ${response.statusCode}');
        throw StateError('webdav mkcol ${walked.join('/')}: ${response.statusCode}');
      }
    }
    _ready = true;
    developer.log('done, WebDAV 远端目录就绪, root: $rootPath');
  }

  @override
  Future<RemoteReadResult> read(String path, {String? ifNoneMatch}) async {
    final headers = {'Authorization': _auth};
    if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) {
      headers['If-None-Match'] = ifNoneMatch;
    }
    final response = await _client
        .get(_uri(path), headers: headers)
        .timeout(AppDb.syncRequestTimeout);
    if (response.statusCode == 200) {
      return RemoteReadResult.found(
          RemoteObject(response.bodyBytes, response.headers['etag']));
    }
    if (response.statusCode == 304) {
      return const RemoteReadResult.notModified();
    }
    if (response.statusCode == 404) {
      return const RemoteReadResult.missing();
    }
    developer.log(
        'fail, WebDAV 读取失败, path: $path, status: ${response.statusCode}');
    throw StateError('webdav get $path: ${response.statusCode}');
  }

  @override
  Future<String?> write(String path, Uint8List bytes) async {
    await ensureReady();
    await _ensureParent(path);
    final response = await _client
        .put(_uri(path),
            headers: {
              'Authorization': _auth,
              'Content-Type': 'application/octet-stream',
            },
            body: bytes)
        .timeout(AppDb.syncRequestTimeout);
    if (response.statusCode >= 400) {
      developer.log(
          'fail, WebDAV 写入失败, path: $path, status: ${response.statusCode}, size: ${bytes.length}');
      throw StateError('webdav put $path: ${response.statusCode}');
    }
    return response.headers['etag'];
  }

  @override
  Future<void> remove(String path) async {
    final response = await _client
        .delete(_uri(path), headers: {'Authorization': _auth}).timeout(
            AppDb.syncRequestTimeout);
    if (response.statusCode == 404 || response.statusCode < 400) {
      return;
    }
    developer.log(
        'fail, WebDAV 删除失败, path: $path, status: ${response.statusCode}');
    throw StateError('webdav delete $path: ${response.statusCode}');
  }
}