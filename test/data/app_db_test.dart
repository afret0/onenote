import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';

void main() {
  late AppDb db;
  var now = 1700000000000;

  setUp(() {
    now = 1700000000000;
    db = AppDb(NativeDatabase.memory(), clock: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  Future<(Notebook, Note)> seedNote({String content = 'hello world'}) async {
    final notebook = await db.createNotebook('work');
    final note = await db.createNote(notebook.id, title: 'first', content: content);
    return (notebook, note);
  }

  test('save with unchanged content records no version', () async {
    final (_, note) = await seedNote();
    now += 1000;
    final changed = await db.saveNote(note.id, 'first', 'hello world');
    expect(changed, isFalse);
    expect(await db.listVersions(note.id), hasLength(1));
  });

  test('save with changed content records a version and bumps updateAt',
      () async {
    final (_, note) = await seedNote();
    now += 1000;
    final changed = await db.saveNote(note.id, 'first', 'hello again');
    expect(changed, isTrue);
    final versions = await db.listVersions(note.id);
    expect(versions, hasLength(2));
    expect(versions.first.content, 'hello again');
    expect((await db.getNote(note.id)).updateAt, now);
  });

  test('title-only change also records a version', () async {
    final (_, note) = await seedNote();
    final changed = await db.saveNote(note.id, 'renamed', 'hello world');
    expect(changed, isTrue);
    expect(await db.listVersions(note.id), hasLength(2));
  });

  test('search matches title and content case-insensitively, excludes trash',
      () async {
    final (notebook, note) = await seedNote(content: 'Flutter Rocks');
    final other = await db.createNotebook('life');
    await db.createNote(other.id, title: 'recipe', content: 'flutter pie');
    final all = await db.searchNotes('FLUTTER', {});
    expect(all, hasLength(2));
    final scoped = await db.searchNotes('flutter', {notebook.id});
    expect(scoped, hasLength(1));
    expect(scoped.single.id, note.id);
    await db.softDeleteNote(note.id);
    expect(await db.searchNotes('flutter', {}), hasLength(1));
    expect(await db.searchNotes('', {}), isEmpty);
  });

  test('trash restore and hard delete remove versions', () async {
    final (_, note) = await seedNote();
    await db.saveNote(note.id, 'first', 'v2');
    await db.softDeleteNote(note.id);
    expect(await db.listNotes(), isEmpty);
    expect(await db.listTrash(), hasLength(1));
    await db.restoreNote(note.id);
    expect(await db.listNotes(), hasLength(1));
    await db.hardDeleteNote(note.id);
    expect(await db.listTrash(), isEmpty);
    expect(await db.listVersions(note.id), isEmpty);
  });

  test('notebook delete rejects non-empty including trashed notes', () async {
    final (notebook, note) = await seedNote();
    await db.softDeleteNote(note.id);
    expect(() => db.deleteNotebook(notebook.id),
        throwsA(isA<NotebookNotEmptyException>()));
    await db.hardDeleteNote(note.id);
    await db.deleteNotebook(notebook.id);
    expect(await db.listNotebooks(), isEmpty);
  });

  test('purge respects retention boundary and configured days', () async {
    final (_, note) = await seedNote();
    final createdAt = now;
    await db.softDeleteNote(note.id);
    now = createdAt + AppDb.defaultRetentionDays * AppDb.msPerDay;
    await db.purgeExpired();
    expect(await db.listTrash(), hasLength(1));
    now += 1;
    await db.purgeExpired();
    expect(await db.listTrash(), isEmpty);
    expect(await db.listVersions(note.id), isEmpty);
  });

  test('purge drops old versions but keeps fresh ones', () async {
    final (_, note) = await seedNote();
    final createdAt = now;
    now = createdAt + AppDb.defaultRetentionDays * AppDb.msPerDay + 1;
    await db.saveNote(note.id, 'first', 'fresh');
    await db.purgeExpired();
    final versions = await db.listVersions(note.id);
    expect(versions, hasLength(1));
    expect(versions.single.content, 'fresh');
  });

  test('configured retention overrides default', () async {
    final (_, note) = await seedNote();
    await db.setSetting(AppDb.trashRetentionKey, '1');
    final deletedAt = now;
    await db.softDeleteNote(note.id);
    now = deletedAt + AppDb.msPerDay + 1;
    await db.purgeExpired();
    expect(await db.listTrash(), isEmpty);
  });

  test('restoreVersion reverts content and keeps history linear', () async {
    final (_, note) = await seedNote();
    final original = (await db.listVersions(note.id)).single;
    await db.saveNote(note.id, 'first', 'changed');
    now += 5000;
    final reverted = await db.restoreVersion(note.id, original.id);
    expect(reverted, isTrue);
    expect((await db.getNote(note.id)).content, 'hello world');
    expect(await db.listVersions(note.id), hasLength(3));
    final again = await db.restoreVersion(note.id, original.id);
    expect(again, isFalse);
    expect(await db.listVersions(note.id), hasLength(3));
  });

  test('notebook colors cycle through the palette in creation order', () async {
    final colors = <int>[];
    for (var i = 0; i < notebookPalette.length + 2; i++) {
      colors.add((await db.createNotebook('nb$i')).color);
    }
    for (var i = 0; i < colors.length; i++) {
      expect(colors[i], notebookPalette[i % notebookPalette.length]);
    }
  });

  test('attachment refs cover live notes, trash and history versions', () async {
    final idA = 'a' * 64;
    final idB = 'b' * 64;
    final idC = 'c' * 64;
    final (notebook, note) =
        await seedNote(content: '![img](onenote-asset://$idA)');
    await db.saveNote(note.id, 'first', '![img](onenote-asset://$idB)');
    final other =
        await db.createNote(notebook.id, title: 't', content: '[f](onenote-asset://$idC)');
    await db.softDeleteNote(other.id);
    final refs = await db.allAttachmentRefs();
    expect(refs, {idA, idB, idC});
  });
}