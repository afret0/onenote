import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AttachmentTooLargeException implements Exception {
  AttachmentTooLargeException(this.sizeBytes);

  final int sizeBytes;

  @override
  String toString() => 'attachment exceeds size cap: $sizeBytes bytes';
}

class AttachmentStore {
  AttachmentStore._(this.root);

  AttachmentStore.forTest(this.root);

  final Directory root;

  static final RegExp _idFileName = RegExp(r'^[0-9a-f]{64}$');

  static const maxAttachmentBytes = 20 * 1024 * 1024;
  static const scheme = 'onenote-asset';

  static final RegExp refPattern =
      RegExp(r'onenote-asset://([0-9a-f]{64})');

  static Future<AttachmentStore> open({String? spaceId}) async {
    if (kIsWeb) {
      throw UnsupportedError('attachment storage is not available on web yet');
    }
    final support = await getApplicationSupportDirectory();
    final folder = spaceId == null || spaceId.isEmpty
        ? 'attachments'
        : 'attachments_space_$spaceId';
    final root = Directory('${support.path}/$folder');
    await root.create(recursive: true);
    return AttachmentStore._(root);
  }

  static Set<String> referencedIds(String content) =>
      refPattern.allMatches(content).map((m) => m.group(1)!).toSet();

  static String imageMarkdown(String id, String name) => '![$name]($scheme://$id)';

  static String fileMarkdown(String id, String name) => '[$name]($scheme://$id)';

  File fileOf(String id) => File('${root.path}/$id');

  Future<String> save(Uint8List bytes, String name) async {
    if (bytes.length > maxAttachmentBytes) {
      final err = AttachmentTooLargeException(bytes.length);
      developer.log('fail, 附件超过大小上限, name: $name, size: ${bytes.length}, cap: $maxAttachmentBytes, err: $err');
      throw err;
    }
    final id = sha256.convert(bytes).toString();
    final file = fileOf(id);
    if (await file.exists()) {
      developer.log('hit, 附件内容已存在复用去重, id: $id, name: $name, size: ${bytes.length}');
      return id;
    }
    await file.writeAsBytes(bytes, flush: true);
    await File('${root.path}/$id.name').writeAsString(name, flush: true);
    developer.log('done, 附件已落盘, id: $id, name: $name, size: ${bytes.length}');
    return id;
  }

  Future<String?> nameOf(String id) async {
    final meta = File('${root.path}/$id.name');
    if (await meta.exists()) {
      return meta.readAsString();
    }
    return null;
  }

  Future<Uint8List?> read(String id) async {
    final file = fileOf(id);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    developer.log('skip, 附件文件不存在, id: $id');
    return null;
  }

  Future<void> delete(String id) async {
    final file = fileOf(id);
    if (await file.exists()) {
      await file.delete();
    }
    final meta = File('${root.path}/$id.name');
    if (await meta.exists()) {
      await meta.delete();
    }
  }

  Future<List<String>> listIds() async {
    final ids = <String>[];
    await for (final entity in root.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        if (_idFileName.hasMatch(name)) {
          ids.add(name);
        }
      }
    }
    return ids;
  }

  Future<int> purgeUnreferenced(Set<String> referenced) async {
    var removed = 0;
    for (final id in await listIds()) {
      if (!referenced.contains(id)) {
        await delete(id);
        removed++;
        developer.log('done, 孤儿附件已清理, id: $id');
      }
    }
    developer.log('done, 附件清理完成, removed: $removed, referencedCount: ${referenced.length}');
    return removed;
  }
}