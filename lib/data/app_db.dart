import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'attachment_store.dart';

part 'app_db.g.dart';

class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer().withDefault(const Constant(0xFF2E7D5B))();
  IntColumn get createAt => integer()();
  IntColumn get updateAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

const notebookPalette = [
  0xFF2E7D5B,
  0xFF0E7490,
  0xFF2563EB,
  0xFF7C3AED,
  0xFFDB2777,
  0xFFD97706,
  0xFFDC2626,
  0xFF64748B,
];

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get notebookId => text().references(Notebooks, #id)();
  TextColumn get title => text()();
  TextColumn get content => text()();
  IntColumn get createAt => integer()();
  IntColumn get updateAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteVersions extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get title => text()();
  TextColumn get content => text()();
  IntColumn get createAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class NotebookNotEmptyException implements Exception {
  NotebookNotEmptyException(this.noteCount);

  final int noteCount;

  @override
  String toString() => 'notebook still has $noteCount notes';
}

@DriftDatabase(tables: [Notebooks, Notes, NoteVersions, Settings])
class AppDb extends _$AppDb {
  AppDb(super.executor, {int Function()? clock})
      : clock = clock ?? _systemClock;

  final int Function() clock;

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;

  static const _uuid = Uuid();
  static const defaultRetentionDays = 90;
  static const trashRetentionKey = 'trashRetentionDays';
  static const versionRetentionKey = 'versionRetentionDays';
  static const searchScopeKey = 'searchScope';
  static const msPerDay = 86400000;

  static QueryExecutor openExecutor() => driftDatabase(
        name: 'onenote',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(notebooks, notebooks.color);
            final rows = await (select(notebooks)
                  ..orderBy([(t) => OrderingTerm.asc(t.createAt)]))
                .get();
            for (var i = 0; i < rows.length; i++) {
              await (update(notebooks)..where((t) => t.id.equals(rows[i].id)))
                  .write(NotebooksCompanion(
                      color: Value(notebookPalette[i % notebookPalette.length])));
            }
          }
        },
      );

  Future<Notebook> createNotebook(String name) async {
    final now = clock();
    final id = _uuid.v4();
    final existing = await listNotebooks();
    final color = notebookPalette[existing.length % notebookPalette.length];
    await into(notebooks).insert(NotebooksCompanion.insert(
        id: id,
        name: name,
        color: Value(color),
        createAt: now,
        updateAt: now));
    developer.log('done, 笔记本已创建, notebookId: $id, name: $name, color: $color');
    return (select(notebooks)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> renameNotebook(String id, String name) async {
    await (update(notebooks)..where((t) => t.id.equals(id))).write(
        NotebooksCompanion(name: Value(name), updateAt: Value(clock())));
  }

  Future<void> deleteNotebook(String id) async {
    final countExp = notes.id.count();
    final query = selectOnly(notes)
      ..addColumns([countExp])
      ..where(notes.notebookId.equals(id));
    final count = await query.map((row) => row.read(countExp)!).getSingle();
    if (count > 0) {
      final err = NotebookNotEmptyException(count);
      developer.log(
          'fail, 笔记本非空禁止删除, notebookId: $id, noteCount: $count, err: $err');
      throw err;
    }
    await (delete(notebooks)..where((t) => t.id.equals(id))).go();
    developer.log('done, 笔记本已删除, notebookId: $id');
  }

  Future<List<Notebook>> listNotebooks() =>
      (select(notebooks)..orderBy([(t) => OrderingTerm.asc(t.createAt)]))
          .get();

  Future<Note> createNote(String notebookId,
      {String title = '', String content = ''}) async {
    final now = clock();
    final id = _uuid.v4();
    await into(notes).insert(NotesCompanion.insert(
        id: id,
        notebookId: notebookId,
        title: title,
        content: content,
        createAt: now,
        updateAt: now));
    await _insertVersion(id, title, content, now);
    developer.log('done, 笔记已创建, noteId: $id, notebookId: $notebookId');
    return getNote(id);
  }

  Future<Note> getNote(String id) =>
      (select(notes)..where((t) => t.id.equals(id))).getSingle();

  Future<bool> saveNote(String id, String title, String content) async {
    final current = await getNote(id);
    if (current.title == title && current.content == content) {
      developer.log('skip, 内容未变更不记版本, noteId: $id');
      return false;
    }
    final now = clock();
    await (update(notes)..where((t) => t.id.equals(id))).write(NotesCompanion(
        title: Value(title), content: Value(content), updateAt: Value(now)));
    final versionId = await _insertVersion(id, title, content, now);
    developer.log('done, 笔记已保存并记版本, noteId: $id, versionId: $versionId');
    return true;
  }

  Future<String> _insertVersion(
      String noteId, String title, String content, int at) async {
    final id = _uuid.v4();
    await into(noteVersions).insert(NoteVersionsCompanion.insert(
        id: id,
        noteId: noteId,
        title: title,
        content: content,
        createAt: at));
    return id;
  }

  Future<void> softDeleteNote(String id) async {
    await (update(notes)..where((t) => t.id.equals(id)))
        .write(NotesCompanion(deletedAt: Value(clock())));
    developer.log('done, 笔记已移入回收站, noteId: $id');
  }

  Future<void> restoreNote(String id) async {
    await (update(notes)..where((t) => t.id.equals(id)))
        .write(const NotesCompanion(deletedAt: Value(null)));
    developer.log('done, 笔记已从回收站恢复, noteId: $id');
  }

  Future<void> hardDeleteNote(String id) async {
    await transaction(() async {
      final versions =
          await (delete(noteVersions)..where((t) => t.noteId.equals(id))).go();
      await (delete(notes)..where((t) => t.id.equals(id))).go();
      developer.log('done, 笔记已彻底删除, noteId: $id, deletedVersions: $versions');
    });
  }

  Future<List<Note>> listNotes({String? notebookId}) {
    final query = select(notes)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.updateAt)]);
    if (notebookId != null) {
      query.where((t) => t.notebookId.equals(notebookId));
    }
    return query.get();
  }

  Future<List<Note>> listTrash() => (select(notes)
        ..where((t) => t.deletedAt.isNotNull())
        ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
      .get();

  Future<List<Note>> searchNotes(String query, Set<String> scope) async {
    if (query.isEmpty) {
      return [];
    }
    final needle = query.toLowerCase();
    final selection = select(notes)..where((t) => t.deletedAt.isNull());
    if (scope.isNotEmpty) {
      selection.where((t) => t.notebookId.isIn(scope));
    }
    final rows = await selection.get();
    final hits = rows
        .where((n) =>
            n.title.toLowerCase().contains(needle) ||
            n.content.toLowerCase().contains(needle))
        .toList()
      ..sort((a, b) => b.updateAt.compareTo(a.updateAt));
    return hits;
  }

  Future<Set<String>> allAttachmentRefs() async {
    final refs = <String>{};
    for (final note in await select(notes).get()) {
      refs.addAll(AttachmentStore.referencedIds(note.content));
    }
    for (final version in await select(noteVersions).get()) {
      refs.addAll(AttachmentStore.referencedIds(version.content));
    }
    return refs;
  }

  Future<List<NoteVersion>> listVersions(String noteId) =>
      (select(noteVersions)
            ..where((t) => t.noteId.equals(noteId))
            ..orderBy([(t) => OrderingTerm.desc(t.createAt)]))
          .get();

  Future<NoteVersion> getVersion(String id) =>
      (select(noteVersions)..where((t) => t.id.equals(id))).getSingle();

  Future<bool> restoreVersion(String noteId, String versionId) async {
    final version = await getVersion(versionId);
    developer.log(
        'hit, 恢复历史版本, noteId: $noteId, versionId: $versionId, versionCreateAt: ${version.createAt}');
    return saveNote(noteId, version.title, version.content);
  }

  Future<String?> getSetting(String key) async =>
      (await (select(settings)..where((t) => t.key.equals(key)))
          .getSingleOrNull())
      ?.value;

  Future<void> setSetting(String key, String value) => into(settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  Future<int> retentionDays(String key) async =>
      int.tryParse(await getSetting(key) ?? '') ?? defaultRetentionDays;

  Future<void> purgeExpired() async {
    final now = clock();
    final trashDays = await retentionDays(trashRetentionKey);
    final versionDays = await retentionDays(versionRetentionKey);
    final trashCutoff = now - trashDays * msPerDay;
    final versionCutoff = now - versionDays * msPerDay;
    await transaction(() async {
      final expired = await (select(notes)
            ..where((t) => t.deletedAt.isSmallerThanValue(trashCutoff)))
          .get();
      for (final note in expired) {
        await hardDeleteNote(note.id);
      }
      final versions = await (delete(noteVersions)
            ..where((t) => t.createAt.isSmallerThanValue(versionCutoff)))
          .go();
      developer.log(
          'done, 过期清理完成, purgedNotes: ${expired.length}, purgedVersions: $versions, trashDays: $trashDays, versionDays: $versionDays');
    });
  }
}