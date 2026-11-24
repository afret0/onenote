import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/attachment_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AttachmentStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('onenote_att_test');
    store = AttachmentStore.forTest(root);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<String> saveBytes(List<int> bytes, String name) =>
      store.save(Uint8List.fromList(bytes), name);

  test('save dedups identical content by sha256', () async {
    final id1 = await saveBytes([1, 2, 3], 'a.png');
    final id2 = await saveBytes([1, 2, 3], 'b.png');
    expect(id1, id2);
    expect(await store.listIds(), hasLength(1));
    expect(await store.read(id1), [1, 2, 3]);
  });

  test('save rejects oversize bytes', () async {
    final big = Uint8List(AttachmentStore.maxAttachmentBytes + 1);
    expect(() => store.save(big, 'big.bin'),
        throwsA(isA<AttachmentTooLargeException>()));
  });

  test('referencedIds extracts only scheme refs', () {
    final content = '''
![p](onenote-asset://${'a' * 64})
text https://example.com/x.png
[f](onenote-asset://${'b' * 64}) ![p](onenote-asset://${'a' * 64})
''';
    expect(AttachmentStore.referencedIds(content), {'a' * 64, 'b' * 64});
    expect(AttachmentStore.referencedIds('no assets here'), isEmpty);
  });

  test('purge keeps referenced ids and removes orphans with metadata',
      () async {
    final kept = await saveBytes([1], 'keep.png');
    final orphan = await saveBytes([2], 'orphan.png');
    expect(File('${root.path}/$orphan.name').existsSync(), isTrue);
    final removed = await store.purgeUnreferenced({kept});
    expect(removed, 1);
    expect(await store.listIds(), [kept]);
    expect(File('${root.path}/$orphan.name').existsSync(), isFalse);
    expect(await store.nameOf(kept), 'keep.png');
  });

  test('read missing id returns null and delete is idempotent', () async {
    expect(await store.read('f' * 64), isNull);
    await store.delete('f' * 64);
    final id = await saveBytes([9], 'x');
    await store.delete(id);
    await store.delete(id);
    expect(await store.listIds(), isEmpty);
  });
}