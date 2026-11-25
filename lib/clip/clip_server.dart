import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../state/app_state.dart';

class ClipException implements Exception {
  ClipException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

class ClipServer {
  ClipServer(this.state);

  final AppState state;
  HttpServer? _server;

  bool get running => _server != null;

  int? get port => _server?.port;

  Future<void> start(int port) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_handle, onError: (Object err) {
      developer.log('fail, 剪藏桥接连接异常, err: $err');
    });
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    try {
      if (request.method == 'OPTIONS') {
        response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        response.headers.set('Access-Control-Allow-Headers', 'Content-Type, X-Clip-Token');
        response.headers.set('Access-Control-Max-Age', '86400');
        response.statusCode = HttpStatus.noContent;
      } else if (request.method == 'GET' && request.uri.path == '/ping') {
        response.write('onenote');
      } else if (request.method == 'GET' && request.uri.path == '/notebooks') {
        _requireToken(request);
        _writeJson(response, [
          for (final notebook in state.notebooks)
            {'id': notebook.id, 'name': notebook.name, 'color': notebook.color},
        ]);
      } else if (request.method == 'POST' && request.uri.path == '/clips') {
        _requireToken(request);
        final payload = await _readJson(request);
        final notebookId = payload['notebookId'];
        final title = payload['title'];
        final markdown = payload['markdown'];
        if (notebookId is! String || title is! String || markdown is! String) {
          throw ClipException(400, '请求缺少 notebookId / title / markdown 字符串字段');
        }
        final sourceUrl = payload['sourceUrl'];
        if (sourceUrl != null && sourceUrl is! String) {
          throw ClipException(400, 'sourceUrl 必须是字符串');
        }
        final note = await state.clipNote(
            notebookId: notebookId,
            title: title,
            markdown: markdown,
            sourceUrl: sourceUrl as String?);
        developer.log(
            'done, 剪藏已入库, noteId: ${note.id}, notebookId: $notebookId, title: ${note.title}, contentLength: ${note.content.length}');
        _writeJson(response,
            {'id': note.id, 'title': note.title, 'notebookId': note.notebookId});
      } else {
        throw ClipException(404, '未知路径: ${request.method} ${request.uri.path}');
      }
    } on ClipException catch (err) {
      developer.log(
          'skip, 剪藏请求被拒, path: ${request.uri.path}, status: ${err.status}, message: ${err.message}');
      response.statusCode = err.status;
      _writeJson(response, {'error': err.message});
    } catch (err) {
      developer.log('fail, 剪藏请求处理失败, path: ${request.uri.path}, err: $err');
      response.statusCode = HttpStatus.internalServerError;
      _writeJson(response, {'error': '应用内部错误，剪藏未完成'});
    }
    await response.close();
  }

  void _requireToken(HttpRequest request) {
    final token = request.headers.value('x-clip-token') ??
        request.uri.queryParameters['token'];
    if (state.clipToken.isEmpty || token != state.clipToken) {
      throw ClipException(401, '令牌不匹配，请把设置页的配对令牌粘贴到插件设置');
    }
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ClipException(400, '请求体不是合法 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ClipException(400, '请求体必须是 JSON 对象');
    }
    return decoded;
  }

  void _writeJson(HttpResponse response, Object payload) {
    response.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    response.write(jsonEncode(payload));
  }
}