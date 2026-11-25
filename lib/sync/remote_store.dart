import 'dart:typed_data';

class RemoteObject {
  RemoteObject(this.bytes, this.etag);

  final Uint8List bytes;
  final String? etag;
}

class RemoteReadResult {
  const RemoteReadResult.found(RemoteObject this.object)
      : notModified = false,
        missing = false;

  const RemoteReadResult.notModified()
      : object = null,
        notModified = true,
        missing = false;

  const RemoteReadResult.missing()
      : object = null,
        notModified = false,
        missing = true;

  final RemoteObject? object;
  final bool notModified;
  final bool missing;
}

abstract class RemoteStore {
  Future<RemoteReadResult> read(String path, {String? ifNoneMatch});

  Future<String?> write(String path, Uint8List bytes);

  Future<void> remove(String path);

  Future<void> ensureReady();

  String get describe;
}