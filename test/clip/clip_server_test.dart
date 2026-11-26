import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/clip/clip_server.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  late AppDb db;
  late AppState state;
  late ClipServer server;
  var now = 1700000000000;

  setUp(() async {
    HttpOverrides.global = null;
    now = 1700000000000;
    supportDir = await Directory.systemTemp.createTemp('onenote_clip_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    db = AppDb(NativeDatabase.memory(), clock: () => now);
    state = AppState(db);
    await state.init();
    server = ClipServer(state);
    await server.start(0);
  });

  tearDown(() async {
    await server.stop();
    state.dispose();
    await db.close();
    await supportDir.delete(recursive: true);
  });

  Future<(int, String, HttpHeaders)> hit(String method, String path,
      {String? token, Object? body, bool rawBody = false}) async {
    final client = HttpClient()..findProxy = (uri) => 'DIRECT';
    try {
      final request = await client.openUrl(
          method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      if (token != null) {
        request.headers.set('X-Clip-Token', token);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(rawBody ? body : jsonEncode(body));
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      return (response.statusCode, text, response.headers);
    } finally {
      client.close(force: true);
    }
  }

  test('ping needs no token and preflight carries cors headers', () async {
    final (status, text, _) = await hit('GET', '/ping');
    expect(status, 200);
    expect(text, 'onenote');

    final (optStatus, _, headers) = await hit('OPTIONS', '/clips');
    expect(optStatus, 204);
    expect(headers.value('access-control-allow-origin'), '*');
    expect(headers.value('access-control-allow-headers'),
        'Content-Type, X-Clip-Token');
  });

  test('notebooks requires token and lists notebooks', () async {
    now += 1000;
    final work = await db.createNotebook('工作');
    await state.refresh();

    final (denied, _, _) = await hit('GET', '/notebooks');
    expect(denied, 401);
    final (wrong, _, _) = await hit('GET', '/notebooks', token: 'nope');
    expect(wrong, 401);

    final (status, text, _) =
        await hit('GET', '/notebooks', token: state.clipToken);
    expect(status, 200);
    final list = jsonDecode(text) as List;
    expect(list, hasLength(1));
    expect((list.first as Map)['id'], work.id);
    expect((list.first as Map)['name'], '工作');
  });

  test('clip creates note with source link on top of body', () async {
    now += 1000;
    final work = await db.createNotebook('工作');
    await state.refresh();

    now += 1000;
    final (status, text, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': work.id,
          'title': '示例文章',
          'markdown': '# 标题\n\n正文段落',
          'sourceUrl': 'https://example.com/post',
        });
    expect(status, 200);
    final payload = jsonDecode(text) as Map;
    final note = await db.getNote(payload['id'] as String);
    expect(note.title, '示例文章');
    expect(note.content,
        '<https://example.com/post>\n\n# 标题\n\n正文段落');
    expect(state.notes.where((n) => n.id == note.id), hasLength(1));
    final versions = await db.listVersions(note.id);
    expect(versions, hasLength(1));
  });

  test('bookmark clip with empty markdown keeps only source link', () async {
    now += 1000;
    final work = await db.createNotebook('工作');
    await state.refresh();

    now += 1000;
    final (status, text, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': work.id,
          'title': '书签',
          'markdown': '',
          'sourceUrl': 'https://example.com',
        });
    expect(status, 200);
    final note =
        await db.getNote((jsonDecode(text) as Map)['id'] as String);
    expect(note.content, '<https://example.com>');
  });

  test('image attachment clip stores asset and embeds markdown', () async {
    now += 1000;
    final work = await db.createNotebook('工作');
    await state.refresh();
    final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
    final id = sha256.convert(bytes).toString();

    now += 1000;
    final (status, text, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': work.id,
          'title': '示例页面 截图',
          'markdown': '',
          'sourceUrl': 'https://example.com/shot',
          'attachment': {
            'name': 'shot.png',
            'mime': 'image/png',
            'data': base64Encode(bytes),
          },
        });
    expect(status, 200);
    final note = await db.getNote((jsonDecode(text) as Map)['id'] as String);
    expect(note.title, '示例页面 截图');
    expect(note.content,
        '<https://example.com/shot>\n\n![shot.png](onenote-asset://$id)');
    expect(await state.attachments!.read(id), bytes);
    expect(await state.attachments!.nameOf(id), 'shot.png');
  });

  test('mhtml attachment clip stores file link', () async {
    now += 1000;
    final work = await db.createNotebook('工作');
    await state.refresh();
    final bytes = Uint8List.fromList(utf8.encode('From: <Saved by onenote>\n'));
    final id = sha256.convert(bytes).toString();

    now += 1000;
    final (status, text, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': work.id,
          'title': '整页',
          'markdown': '',
          'sourceUrl': 'https://example.com/full',
          'attachment': {
            'name': '整页.mhtml',
            'mime': 'multipart/related',
            'data': base64Encode(bytes),
          },
        });
    expect(status, 200);
    final note = await db.getNote((jsonDecode(text) as Map)['id'] as String);
    expect(note.content,
        '<https://example.com/full>\n\n[整页.mhtml](onenote-asset://$id)');
    expect(await state.attachments!.read(id), bytes);
  });

  test('attachment rejects oversize bad base64 and empty name', () async {
    now += 1000;
    final work = await db.createNotebook('工作');
    await state.refresh();

    now += 1000;
    final (oversize, _, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': work.id,
          'title': '大',
          'markdown': '',
          'attachment': {
            'name': 'big.mhtml',
            'mime': 'multipart/related',
            'data': 'A' * (20 * 1024 * 1024 * 4 ~/ 3 + 8),
          },
        });
    expect(oversize, 413);

    now += 1000;
    final (badBase64, _, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': work.id,
          'title': '坏',
          'markdown': '',
          'attachment': {'name': 'x.png', 'mime': 'image/png', 'data': '!!!'},
        });
    expect(badBase64, 400);

    now += 1000;
    final (noName, _, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': work.id,
          'title': '无名',
          'markdown': '',
          'attachment': {
            'name': ' ',
            'mime': 'image/png',
            'data': base64Encode([1]),
          },
        });
    expect(noName, 400);
  });

  test('clip rejects unknown notebook empty content and bad payloads',
      () async {
    now += 1000;
    await db.createNotebook('工作');
    await state.refresh();

    final (missingNotebook, _, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': 'gone',
          'title': 't',
          'markdown': 'x',
        });
    expect(missingNotebook, 404);

    final (empty, _, _) = await hit('POST', '/clips',
        token: state.clipToken,
        body: {
          'notebookId': state.notebooks.first.id,
          'title': 't',
          'markdown': '   ',
        });
    expect(empty, 400);

    final (badJson, _, _) = await hit('POST', '/clips',
        token: state.clipToken, body: '{oops', rawBody: true);
    expect(badJson, 400);

    final (missingFields, _, _) = await hit('POST', '/clips',
        token: state.clipToken, body: {'title': 't'});
    expect(missingFields, 400);

    final (unknownPath, _, _) = await hit('GET', '/nope');
    expect(unknownPath, 404);
  });

  test('clip settings persist across restart and validate port range',
      () async {
    expect(state.clipEnabled, isFalse);
    expect(state.clipPort, AppState.clipPortDefault);
    expect(state.clipToken, hasLength(32));

    expect(await state.setClipPort(80), isFalse);
    expect(await state.setClipPort(70000), isFalse);
    expect(state.clipPort, AppState.clipPortDefault);
    expect(await state.setClipPort(42424), isTrue);

    final oldToken = state.clipToken;
    await state.regenerateClipToken();
    expect(state.clipToken, isNot(oldToken));
    expect(state.clipToken, hasLength(32));

    final restarted = AppState(db);
    addTearDown(restarted.dispose);
    await restarted.init();
    expect(restarted.clipPort, 42424);
    expect(restarted.clipToken, state.clipToken);
    expect(restarted.clipEnabled, isFalse);
  });

  test('enabling clip starts bridge on configured port and disabling stops it',
      () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final freePort = probe.port;
    await probe.close();

    expect(await state.setClipPort(freePort), isTrue);
    await state.setClipEnabled(true);
    expect(state.clipEnabled, isTrue);
    expect(state.clipError, isNull);

    final client = HttpClient()..findProxy = (uri) => 'DIRECT';
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:$freePort/ping'));
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(await utf8.decoder.bind(response).join(), 'onenote');
    client.close(force: true);

    await state.setClipEnabled(false);
    expect(state.clipEnabled, isFalse);
    final refused = HttpClient()..findProxy = (uri) => 'DIRECT';
    await expectLater(() async {
      final request = await refused
          .getUrl(Uri.parse('http://127.0.0.1:$freePort/ping'));
      await request.close();
    }, throwsA(isA<SocketException>()));
    refused.close(force: true);
  });
}