import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../data/app_db.dart';
import 'remote_store.dart';

class OssStore implements RemoteStore {
  OssStore({
    required this.endpoint,
    required this.bucket,
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.prefix,
    http.Client? client,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final String endpoint;
  final String bucket;
  final String accessKeyId;
  final String accessKeySecret;
  final String prefix;
  final http.Client _client;
  final DateTime Function() _clock;

  static String normalizePrefix(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return trimmed.isEmpty ? 'onenote' : trimmed;
  }

  static String httpDate(DateTime time) =>
      DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US')
          .format(time.toUtc());

  static String signature({
    required String method,
    required String contentMd5,
    required String contentType,
    required String date,
    required String canonicalizedResource,
    required String accessKeySecret,
  }) {
    final payload =
        '$method\n$contentMd5\n$contentType\n$date\n$canonicalizedResource';
    final mac = Hmac(sha1, utf8.encode(accessKeySecret));
    return base64Encode(mac.convert(utf8.encode(payload)).bytes);
  }

  Uri _uri(String path) {
    var host = endpoint.trim();
    var scheme = 'https';
    if (host.startsWith('http://')) {
      scheme = 'http';
      host = host.substring(7);
    } else if (host.startsWith('https://')) {
      host = host.substring(8);
    }
    host = host.replaceAll(RegExp(r'/+$'), '');
    final key = '$prefix/$path';
    final encoded =
        key.split('/').map(Uri.encodeComponent).join('/');
    return Uri.parse('$scheme://$bucket.$host/$encoded');
  }

  String _canonicalizedResource(String path) => '/$bucket/$prefix/$path';

  Map<String, String> _headers(
      String method, String path, String date, String contentType,
      {String? ifNoneMatch}) {
    final sig = signature(
      method: method,
      contentMd5: '',
      contentType: contentType,
      date: date,
      canonicalizedResource: _canonicalizedResource(path),
      accessKeySecret: accessKeySecret,
    );
    return {
      'Date': date,
      'Authorization': 'OSS $accessKeyId:$sig',
      if (contentType.isNotEmpty) 'Content-Type': contentType,
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
        'If-None-Match': ifNoneMatch,
    };
  }

  @override
  String get describe => 'OSS $bucket.$endpoint/$prefix';

  @override
  Future<void> ensureReady() async {}

  @override
  Future<RemoteReadResult> read(String path, {String? ifNoneMatch}) async {
    final date = httpDate(_clock());
    final response = await _client
        .get(_uri(path), headers: _headers('GET', path, date, '',
            ifNoneMatch: ifNoneMatch))
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
        'fail, OSS 读取失败, path: $path, status: ${response.statusCode}');
    throw StateError('oss get $path: ${response.statusCode}');
  }

  @override
  Future<String?> write(String path, Uint8List bytes) async {
    final date = httpDate(_clock());
    const contentType = 'application/octet-stream';
    final response = await _client
        .put(_uri(path),
            headers: _headers('PUT', path, date, contentType), body: bytes)
        .timeout(AppDb.syncRequestTimeout);
    if (response.statusCode >= 400) {
      developer.log(
          'fail, OSS 写入失败, path: $path, status: ${response.statusCode}, size: ${bytes.length}');
      throw StateError('oss put $path: ${response.statusCode}');
    }
    return response.headers['etag'];
  }

  @override
  Future<void> remove(String path) async {
    final date = httpDate(_clock());
    final response = await _client
        .delete(_uri(path), headers: _headers('DELETE', path, date, ''))
        .timeout(AppDb.syncRequestTimeout);
    if (response.statusCode == 404 || response.statusCode < 400) {
      return;
    }
    developer.log(
        'fail, OSS 删除失败, path: $path, status: ${response.statusCode}');
    throw StateError('oss delete $path: ${response.statusCode}');
  }
}