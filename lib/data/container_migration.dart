import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const legacyMacContainerData =
    'Library/Containers/com.afreto.onenote/Data';

Future<void> migrateLegacyMacContainer() async {
  if (kIsWeb || !Platform.isMacOS) return;
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return;
  final oldData = Directory('$home/$legacyMacContainerData');
  if (!oldData.existsSync()) return;
  final newDocs = await getApplicationDocumentsDirectory();
  final newSupport = await getApplicationSupportDirectory();
  await migrateContainerData(
    oldDocs: Directory('${oldData.path}/Documents'),
    oldSupport:
        Directory('${oldData.path}/Library/Application Support/com.afreto.onenote'),
    newDocs: newDocs,
    newSupport: newSupport,
  );
}

Future<void> migrateContainerData({
  required Directory oldDocs,
  required Directory oldSupport,
  required Directory newDocs,
  required Directory newSupport,
}) async {
  if (!oldDocs.existsSync()) return;
  final migratedDb = File('${newDocs.path}/onenote.sqlite').existsSync();
  if (migratedDb) {
    developer.log('skip, 新位置已有数据库, 不再迁移, path: ${newDocs.path}');
    return;
  }
  var dbCount = 0;
  for (final e in oldDocs.listSync()) {
    if (e is! File) continue;
    final name = e.uri.pathSegments.last;
    if (!name.startsWith('onenote') || !name.contains('.sqlite')) continue;
    final target = File('${newDocs.path}/$name');
    if (target.existsSync()) continue;
    e.copySync(target.path);
    dbCount++;
  }
  var supportCount = 0;
  if (oldSupport.existsSync()) {
    newSupport.createSync(recursive: true);
    for (final e in oldSupport.listSync()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!name.startsWith('attachments') && name != 'fonts') continue;
      final targetPath = '${newSupport.path}/$name';
      if (FileSystemEntity.typeSync(targetPath) != FileSystemEntityType.notFound) {
        continue;
      }
      supportCount += _copyEntity(e, targetPath);
    }
  }
  developer.log(
      'done, 旧沙箱数据已迁移(旧容器保留), dbFiles: $dbCount, supportEntries: $supportCount');
}

int _copyEntity(FileSystemEntity entity, String targetPath) {
  if (entity is File) {
    entity.copySync(targetPath);
    return 1;
  }
  if (entity is Directory) {
    Directory(targetPath).createSync(recursive: true);
    var count = 0;
    for (final child in entity.listSync()) {
      final name = child.uri.pathSegments.where((s) => s.isNotEmpty).last;
      count += _copyEntity(child, '$targetPath/$name');
    }
    return count;
  }
  return 0;
}