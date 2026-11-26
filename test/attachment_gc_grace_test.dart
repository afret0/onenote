import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/attachment_store.dart';

void main() {
  test('附件 GC 宽限期：新落盘未引用不删，超龄孤儿才删', () async {
    final dir = Directory.systemTemp.createTempSync('onenote_gc_grace');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = AttachmentStore.forTest(dir);
    final fresh = await store.save(Uint8List.fromList([1, 2, 3]), 'fresh.mhtml');
    final old = await store.save(Uint8List.fromList([4, 5, 6]), 'old.bin');
    final oldTime = DateTime.now().subtract(const Duration(minutes: 11));
    store.fileOf(old).setLastModifiedSync(oldTime);
    File('${dir.path}/$old.name').setLastModifiedSync(oldTime);

    expect(await store.purgeUnreferenced({}), 1);
    expect(store.fileOf(fresh).existsSync(), true);
    expect(store.fileOf(old).existsSync(), false);

    expect(await store.purgeUnreferenced({fresh}), 0);
    expect(store.fileOf(fresh).existsSync(), true);
  });
}