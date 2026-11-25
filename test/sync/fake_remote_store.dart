import 'dart:typed_data';

import 'package:onenote/sync/remote_store.dart';

class FakeRemoteStore implements RemoteStore {
  final Map<String, Uint8List> objects = {};
  final Map<String, String> etags = {};
  final List<String> writeLog = [];
  final List<String> readLog = [];
  bool failAll = false;
  int _etagSeq = 0;

  @override
  String get describe => 'fake';

  @override
  Future<void> ensureReady() async {}

  @override
  Future<RemoteReadResult> read(String path, {String? ifNoneMatch}) async {
    readLog.add(path);
    if (failAll) {
      throw StateError('remote down');
    }
    final bytes = objects[path];
    if (bytes == null) {
      return const RemoteReadResult.missing();
    }
    final etag = etags[path];
    if (ifNoneMatch != null &&
        ifNoneMatch.isNotEmpty &&
        ifNoneMatch == etag) {
      return const RemoteReadResult.notModified();
    }
    return RemoteReadResult.found(RemoteObject(bytes, etag));
  }

  @override
  Future<String?> write(String path, Uint8List bytes) async {
    if (failAll) {
      throw StateError('remote down');
    }
    writeLog.add(path);
    objects[path] = bytes;
    final etag = 'etag-${++_etagSeq}';
    etags[path] = etag;
    return etag;
  }

  @override
  Future<void> remove(String path) async {
    if (failAll) {
      throw StateError('remote down');
    }
    writeLog.add('DEL:$path');
    objects.remove(path);
    etags.remove(path);
  }

  void clearLogs() {
    writeLog.clear();
    readLog.clear();
  }
}