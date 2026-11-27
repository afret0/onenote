import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

String get updatePlatform {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

bool get canInstallInApp =>
    Platform.isMacOS || Platform.isAndroid || Platform.isWindows;

Future<String?> existingDownloadPath(String fileName, int expectedSize) async {
  if (expectedSize <= 0) return null;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  if (file.existsSync() && file.lengthSync() == expectedSize) return file.path;
  return null;
}

Future<String> downloadUpdate(String url, String fileName,
    {required void Function(int received, int total) onProgress,
    required bool Function() isCancelled}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  if (file.existsSync()) file.deleteSync();
  final client = http.Client();
  IOSink? sink;
  try {
    final res = await client
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw HttpException('下载更新失败, status: ${res.statusCode}');
    }
    final total = res.contentLength ?? 0;
    var received = 0;
    sink = file.openWrite();
    await for (final chunk in res.stream) {
      if (isCancelled()) {
        throw const HttpException('下载已取消');
      }
      sink.add(chunk);
      received += chunk.length;
      onProgress(received, total);
    }
    await sink.flush();
    await sink.close();
    sink = null;
    developer.log('done, 更新包下载完成, path: ${file.path}, bytes: $received');
    return file.path;
  } catch (err) {
    await sink?.close();
    if (file.existsSync()) file.deleteSync();
    rethrow;
  } finally {
    client.close();
  }
}

Future<String> installUpdate(String path) async {
  if (Platform.isMacOS) return _installMac(path);
  if (Platform.isWindows) return _installWindows(path);
  if (Platform.isAndroid) return _installAndroid(path);
  throw UnsupportedError('当前平台不支持应用内安装');
}

Future<String> _installAndroid(String path) async {
  const channel = MethodChannel('onenote/update');
  final result =
      await channel.invokeMethod<String>('installApk', {'path': path});
  developer.log('done, 已调起系统安装器, result: $result');
  return result ?? 'ok';
}

Future<String> _installMac(String dmgPath) async {
  final attach = await Process.run(
      'hdiutil', ['attach', '-nobrowse', '-readonly', dmgPath]);
  if (attach.exitCode != 0) {
    throw ProcessException('hdiutil', ['attach'],
        '挂载更新镜像失败: ${attach.stderr}', attach.exitCode);
  }
  final lines = (attach.stdout as String).trim().split('\n');
  final mount = lines.last.split('\t').last.trim();
  final staging = await Directory.systemTemp.createTemp('onenote_update_');
  try {
    final copy = await Process.run(
        'cp', ['-R', '$mount/onenote.app', '${staging.path}/onenote.app']);
    if (copy.exitCode != 0) {
      throw ProcessException(
          'cp', [], '拷出更新应用失败: ${copy.stderr}', copy.exitCode);
    }
    await Process.run('hdiutil', ['detach', mount]);
    final script = File('${staging.path}/install.sh');
    script.writeAsStringSync('#!/bin/sh\n'
        'while kill -0 $pid 2>/dev/null; do sleep 0.3; done\n'
        'rm -rf /Applications/onenote.app\n'
        'cp -R "${staging.path}/onenote.app" /Applications/onenote.app\n'
        'open /Applications/onenote.app\n'
        'rm -rf "${staging.path}"\n');
    await Process.start('/bin/sh', [script.path],
        mode: ProcessStartMode.detached);
    developer.log('done, mac 更新脚本已派出, staging: ${staging.path}');
    exit(0);
  } catch (err) {
    await Process.run('hdiutil', ['detach', mount]);
    staging.deleteSync(recursive: true);
    rethrow;
  }
}

Future<String> _installWindows(String zipPath) async {
  final staging = await Directory.systemTemp.createTemp('onenote_update_');
  final extracted = '${staging.path}\\app';
  final expand = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    'Expand-Archive -LiteralPath "$zipPath" -DestinationPath "$extracted" -Force'
  ]);
  if (expand.exitCode != 0) {
    staging.deleteSync(recursive: true);
    throw ProcessException('powershell', ['Expand-Archive'],
        '解压更新包失败: ${expand.stderr}', expand.exitCode);
  }
  if (!File('$extracted\\onenote.exe').existsSync()) {
    staging.deleteSync(recursive: true);
    throw const FormatException('更新包里没有 onenote.exe');
  }
  final installDir = File(Platform.resolvedExecutable).parent.path;
  final script = File('${staging.path}\\install.ps1');
  script.writeAsStringSync('param(\$appId, \$src, \$dst, \$root)\n'
      'Wait-Process -Id \$appId -ErrorAction SilentlyContinue\n'
      'robocopy \$src \$dst /E /R:3 /W:1 | Out-Null\n'
      'Start-Process (Join-Path \$dst "onenote.exe")\n'
      'Remove-Item -Recurse -Force \$root\n');
  await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '$pid',
        extracted,
        installDir,
        staging.path,
      ],
      mode: ProcessStartMode.detached);
  developer.log('done, windows 更新脚本已派出, dst: $installDir');
  exit(0);
}

Future<void> openExternalUrl(String url) async {
  if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', url]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [url]);
  } else if (Platform.isAndroid) {
    const channel = MethodChannel('onenote/update');
    await channel.invokeMethod<String>('openUrl', {'url': url});
  }
}