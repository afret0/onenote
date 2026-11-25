import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'attachment_store.dart';

part 'app_db.g.dart';

class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer().withDefault(const Constant(0xFF9333EA))();
  IntColumn get sortKey => integer().nullable()();
  IntColumn get createAt => integer()();
  IntColumn get updateAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

const notebookPalette = [
  0xFF9333EA,
  0xFF16A34A,
  0xFFEA580C,
  0xFF2563EB,
  0xFFDB2777,
  0xFF0D9488,
  0xFFCA8A04,
  0xFFDC2626,
];

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get notebookId => text().references(Notebooks, #id)();
  TextColumn get title => text()();
  TextColumn get content => text()();
  IntColumn get sortKey => integer().nullable()();
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

class SyncState extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get baseJson => text()();
  IntColumn get syncedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncConflicts extends Table {
  TextColumn get noteId => text()();
  TextColumn get json => text()();
  IntColumn get createAt => integer()();

  @override
  Set<Column> get primaryKey => {noteId};
}

class Tombstones extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  IntColumn get deletedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

int _compareSortKey(int? a, int? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return 1;
  }
  if (b == null) {
    return -1;
  }
  return a.compareTo(b);
}

class NotebookNotEmptyException implements Exception {
  NotebookNotEmptyException(this.noteCount);

  final int noteCount;

  @override
  String toString() => 'notebook still has $noteCount notes';
}

@DriftDatabase(tables: [
  Notebooks,
  Notes,
  NoteVersions,
  Settings,
  SyncState,
  SyncConflicts,
  Tombstones,
])
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
  static const paneWidthSidebarKey = 'paneWidth:sidebar';
  static const paneWidthListKey = 'paneWidth:list';
  static const uiFontKey = 'uiFont';
  static const uiFontScaleKey = 'uiFontScale';
  static const noteFontSizeKey = 'noteFontSize';
  static const lastOpenNotePrefix = 'lastOpenNote:';
  static const allNotesScopeKey = 'all';
  static const trashScopeKey = 'trash';
  static const lastViewScopeKey = 'lastViewScope';
  static const lastViewNoteKey = 'lastViewNote';
  static const narrowStartupKey = 'narrowStartup';
  static const msPerDay = 86400000;
  static const versionCoalesceWindowMs = 10 * 60 * 1000;
  static const syncProtocolKey = 'syncProtocol';
  static const syncWebdavUrlKey = 'syncWebdavUrl';
  static const syncWebdavUserKey = 'syncWebdavUser';
  static const syncWebdavPassKey = 'syncWebdavPass';
  static const syncWebdavPathKey = 'syncWebdavPath';
  static const syncOssEndpointKey = 'syncOssEndpoint';
  static const syncOssBucketKey = 'syncOssBucket';
  static const syncOssAkKey = 'syncOssAk';
  static const syncOssSkKey = 'syncOssSk';
  static const syncOssPrefixKey = 'syncOssPrefix';
  static const syncPollMinutesKey = 'syncPollMinutes';
  static const syncDeviceIdKey = 'syncDeviceId';
  static const syncDeviceNameKey = 'syncDeviceName';
  static const syncManifestCacheKey = 'syncManifestCache';
  static const syncManifestEtagKey = 'syncManifestEtag';
  static const syncLastAtKey = 'syncLastAt';
  static const syncProtocolOff = 'off';
  static const syncProtocolWebdav = 'webdav';
  static const syncProtocolOss = 'oss';
  static const syncKindNote = 'note';
  static const syncKindNotebook = 'notebook';
  static const tombstoneRetentionDays = 90;
  static const syncRequestTimeout = Duration(seconds: 15);
  static const syncPollMinutesMax = 1440;

  static QueryExecutor openExecutor() => driftDatabase(
        name: 'onenote',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );

  @override
  int get schemaVersion => 5;

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
          if (from < 3) {
            final rows = await (select(notebooks)
                  ..orderBy([(t) => OrderingTerm.asc(t.createAt)]))
                .get();
            for (var i = 0; i < rows.length; i++) {
              await (update(notebooks)..where((t) => t.id.equals(rows[i].id)))
                  .write(NotebooksCompanion(
                      color: Value(notebookPalette[i % notebookPalette.length])));
            }
            developer.log(
                'done, v3 迁移按新色板重排笔记本颜色, notebookCount: ${rows.length}');
          }
          if (from < 4) {
            await m.addColumn(notebooks, notebooks.sortKey);
            await m.addColumn(notes, notes.sortKey);
          }
          if (from < 5) {
            await m.createTable(syncState);
            await m.createTable(syncConflicts);
            await m.createTable(tombstones);
            await customStatement(
                'CREATE INDEX IF NOT EXISTS note_versions_note_id '
                'ON note_versions (note_id)');
          }
        },
      );

  Future<Notebook> createNotebook(String name) async {
    final now = clock();
    final id = _uuid.v4();
    final existing = await listNotebooks();
    final color = notebookPalette[existing.length % notebookPalette.length];
    int? sortKey;
    if (existing.any((n) => n.sortKey != null)) {
      sortKey = existing
              .map((n) => n.sortKey)
              .whereType<int>()
              .reduce((a, b) => a > b ? a : b) +
          1;
    }
    await into(notebooks).insert(NotebooksCompanion.insert(
        id: id,
        name: name,
        color: Value(color),
        sortKey: Value(sortKey),
        createAt: now,
        updateAt: now));
    developer.log(
        'done, 笔记本已创建, notebookId: $id, name: $name, color: $color, sortKey: $sortKey');
    return (select(notebooks)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> renameNotebook(String id, String name) async {
    await (update(notebooks)..where((t) => t.id.equals(id))).write(
        NotebooksCompanion(name: Value(name), updateAt: Value(clock())));
  }

  Future<void> setNotebookColor(String id, int color) async {
    final row =
        await (select(notebooks)..where((t) => t.id.equals(id))).getSingle();
    if (row.color == color) {
      developer.log('skip, 笔记本颜色未变更不写入, notebookId: $id');
      return;
    }
    await (update(notebooks)..where((t) => t.id.equals(id))).write(
        NotebooksCompanion(color: Value(color), updateAt: Value(clock())));
    developer.log(
        'done, 笔记本颜色已更新, notebookId: $id, old: ${row.color}, new: $color');
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
    await addTombstone(id, syncKindNotebook);
    developer.log('done, 笔记本已删除, notebookId: $id');
  }

  Future<List<Notebook>> listNotebooks() async {
    final rows = await (select(notebooks)
          ..orderBy([(t) => OrderingTerm.asc(t.createAt)]))
        .get();
    if (rows.any((n) => n.sortKey != null)) {
      rows.sort((a, b) {
        final byKey = _compareSortKey(a.sortKey, b.sortKey);
        return byKey != 0 ? byKey : a.createAt.compareTo(b.createAt);
      });
    }
    return rows;
  }

  Future<void> moveNotebook(String id, int delta) async {
    final rows = await listNotebooks();
    final index = rows.indexWhere((n) => n.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= rows.length) {
      developer.log(
          'skip, 笔记本移动越界, notebookId: $id, index: $index, delta: $delta, total: ${rows.length}');
      return;
    }
    await transaction(() async {
      if (rows.any((n) => n.sortKey == null)) {
        for (var i = 0; i < rows.length; i++) {
          await (update(notebooks)..where((t) => t.id.equals(rows[i].id)))
              .write(NotebooksCompanion(sortKey: Value(i)));
        }
      }
      final aKey = rows[index].sortKey ?? index;
      final bKey = rows[target].sortKey ?? target;
      await (update(notebooks)..where((t) => t.id.equals(rows[index].id)))
          .write(NotebooksCompanion(sortKey: Value(bKey)));
      await (update(notebooks)..where((t) => t.id.equals(rows[target].id)))
          .write(NotebooksCompanion(sortKey: Value(aKey)));
    });
    developer.log('done, 笔记本已移动, notebookId: $id, from: $index, to: $target');
  }

  Future<Note> createNote(String notebookId,
      {String title = '', String content = ''}) async {
    final now = clock();
    final id = _uuid.v4();
    final siblings = await (select(notes)
          ..where((t) => t.notebookId.equals(notebookId)))
        .get();
    int? sortKey;
    if (siblings.any((n) => n.sortKey != null)) {
      sortKey = siblings
              .map((n) => n.sortKey)
              .whereType<int>()
              .reduce((a, b) => a < b ? a : b) -
          1;
    }
    await into(notes).insert(NotesCompanion.insert(
        id: id,
        notebookId: notebookId,
        title: title,
        content: content,
        sortKey: Value(sortKey),
        createAt: now,
        updateAt: now));
    await _insertVersion(id, title, content, now);
    developer.log(
        'done, 笔记已创建, noteId: $id, notebookId: $notebookId, sortKey: $sortKey');
    return getNote(id);
  }

  Future<Note> getNote(String id) =>
      (select(notes)..where((t) => t.id.equals(id))).getSingle();

  Future<Note?> findNote(String id) =>
      (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<bool> saveNote(String id, String title, String content,
      {bool coalesce = true}) async {
    final current = await getNote(id);
    if (current.title == title && current.content == content) {
      developer.log('skip, 内容未变更不记版本, noteId: $id');
      return false;
    }
    final now = clock();
    await (update(notes)..where((t) => t.id.equals(id))).write(NotesCompanion(
        title: Value(title), content: Value(content), updateAt: Value(now)));
    final latest = await (select(noteVersions)
          ..where((t) => t.noteId.equals(id))
          ..orderBy([(t) => OrderingTerm.desc(t.createAt)])
          ..limit(1))
        .getSingleOrNull();
    final latestAge = latest == null ? null : now - latest.createAt;
    if (coalesce &&
        latest != null &&
        now - latest.createAt < versionCoalesceWindowMs) {
      await (update(noteVersions)..where((t) => t.id.equals(latest.id)))
          .write(NoteVersionsCompanion(
              title: Value(title), content: Value(content)));
      developer.log(
          'hit, 窗口内改动并入上一版不新增, noteId: $id, versionId: ${latest.id}, 距上一版ms: $latestAge, 窗口ms: $versionCoalesceWindowMs');
      return true;
    }
    final versionId = await _insertVersion(id, title, content, now);
    developer.log(
        'done, 笔记已保存并记新版, noteId: $id, versionId: $versionId, coalesce: $coalesce, 距上一版ms: $latestAge, 窗口ms: $versionCoalesceWindowMs');
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
      await (delete(syncConflicts)..where((t) => t.noteId.equals(id))).go();
      developer.log('done, 笔记已彻底删除, noteId: $id, deletedVersions: $versions');
    });
    await removeSyncState(id);
  }

  Future<void> addTombstone(String id, String kind) =>
      addTombstoneAt(id, kind, clock());

  Future<void> addTombstoneAt(String id, String kind, int deletedAt) async {
    await into(tombstones).insertOnConflictUpdate(TombstonesCompanion.insert(
        id: id, kind: kind, deletedAt: deletedAt));
    developer.log('done, 已记墓碑, id: $id, kind: $kind, deletedAt: $deletedAt');
  }

  Future<List<Tombstone>> listTombstones() => select(tombstones).get();

  Future<void> removeTombstone(String id) async {
    await (delete(tombstones)..where((t) => t.id.equals(id))).go();
    developer.log('done, 墓碑已移除(实体复活), id: $id');
  }

  Future<String> deviceId() async {
    final saved = await getSetting(syncDeviceIdKey);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    final id = _uuid.v4();
    await setSetting(syncDeviceIdKey, id);
    developer.log('done, 已生成本机同步设备 id, deviceId: $id');
    return id;
  }

  Future<Map<String, SyncStateData>> syncStateMap() async => {
        for (final row in await select(syncState).get()) row.id: row,
      };

  Future<void> setSyncState(
      String id, String kind, Map<String, dynamic> baseJson) async {
    await into(syncState).insertOnConflictUpdate(SyncStateCompanion.insert(
        id: id,
        kind: kind,
        baseJson: jsonEncode(baseJson),
        syncedAt: clock()));
  }

  Future<void> removeSyncState(String id) async {
    await (delete(syncState)..where((t) => t.id.equals(id))).go();
  }

  Future<({String title, String content})?> syncBaseContent(String id) async {
    final row = await (select(syncState)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null || row.kind != syncKindNote) {
      return null;
    }
    final parsed = jsonDecode(row.baseJson) as Map<String, dynamic>;
    return (
      title: parsed['title'] as String? ?? '',
      content: parsed['content'] as String? ?? '',
    );
  }

  Future<Map<String, dynamic>?> getConflict(String noteId) async {
    final row = await (select(syncConflicts)
          ..where((t) => t.noteId.equals(noteId)))
        .getSingleOrNull();
    return row == null
        ? null
        : jsonDecode(row.json) as Map<String, dynamic>;
  }

  Future<Set<String>> conflictNoteIds() async =>
      (await select(syncConflicts).get()).map((r) => r.noteId).toSet();

  Future<void> setConflict(String noteId, Map<String, dynamic> payload) async {
    await into(syncConflicts).insertOnConflictUpdate(
        SyncConflictsCompanion.insert(
            noteId: noteId, json: jsonEncode(payload), createAt: clock()));
    developer.log('hit, 已记录同步冲突等待裁决, noteId: $noteId');
  }

  Future<void> removeConflict(String noteId) async {
    await (delete(syncConflicts)..where((t) => t.noteId.equals(noteId))).go();
    developer.log('done, 同步冲突已裁决移除, noteId: $noteId');
  }

  Future<void> applyRemoteNote(
      String id,
      String notebookId,
      String title,
      String content,
      int? sortKey,
      int createAt,
      int updateAt,
      int? deletedAt) async {
    await transaction(() async {
      await into(notes).insertOnConflictUpdate(NotesCompanion.insert(
          id: id,
          notebookId: notebookId,
          title: title,
          content: content,
          sortKey: Value(sortKey),
          createAt: createAt,
          updateAt: updateAt,
          deletedAt: Value(deletedAt)));
      await _insertVersion(id, title, content, updateAt);
    });
    developer.log(
        'done, 远端笔记已应用本地, noteId: $id, updateAt: $updateAt, trashed: ${deletedAt != null}');
  }

  Future<void> applyRemoteNotebook(String id, String name, int color,
      int? sortKey, int createAt, int updateAt) async {
    await into(notebooks).insertOnConflictUpdate(NotebooksCompanion.insert(
        id: id,
        name: name,
        color: Value(color),
        sortKey: Value(sortKey),
        createAt: createAt,
        updateAt: updateAt));
    developer.log('done, 远端笔记本已应用本地, notebookId: $id, name: $name');
  }

  Future<void> applyRemoteHardDeleteNote(String id) async {
    await transaction(() async {
      final versions =
          await (delete(noteVersions)..where((t) => t.noteId.equals(id))).go();
      await (delete(notes)..where((t) => t.id.equals(id))).go();
      await (delete(syncConflicts)..where((t) => t.noteId.equals(id))).go();
      developer.log(
          'done, 远端删除已应用本地, noteId: $id, deletedVersions: $versions');
    });
    await removeSyncState(id);
  }

  Future<void> applyRemoteHardDeleteNotebook(String id) async {
    await (delete(notebooks)..where((t) => t.id.equals(id))).go();
    await clearLastOpenNote(id);
    await removeSyncState(id);
    developer.log('done, 远端删除笔记本已应用本地, notebookId: $id');
  }

  Future<void> wipeForRebuild() async {
    await transaction(() async {
      await delete(noteVersions).go();
      await delete(notes).go();
      await delete(notebooks).go();
      await delete(syncState).go();
      await delete(syncConflicts).go();
      await delete(tombstones).go();
      await (delete(settings)
            ..where((t) => t.key.like('$lastOpenNotePrefix%')))
          .go();
      await deleteSetting(lastViewNoteKey);
    });
    developer.log('done, 以远端为准重建: 本地笔记数据已清空');
  }

  Future<List<Note>> listNotes({String? notebookId}) async {
    final query = select(notes)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.updateAt)]);
    if (notebookId != null) {
      query.where((t) => t.notebookId.equals(notebookId));
    }
    final rows = await query.get();
    if (notebookId != null && rows.any((n) => n.sortKey != null)) {
      rows.sort((a, b) {
        final byKey = _compareSortKey(a.sortKey, b.sortKey);
        return byKey != 0 ? byKey : b.updateAt.compareTo(a.updateAt);
      });
    }
    return rows;
  }

  Future<void> moveNote(String id, int delta) async {
    final note = await getNote(id);
    final rows = await listNotes(notebookId: note.notebookId);
    final index = rows.indexWhere((n) => n.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= rows.length) {
      developer.log(
          'skip, 笔记移动越界, noteId: $id, index: $index, delta: $delta, total: ${rows.length}');
      return;
    }
    await transaction(() async {
      if (rows.any((n) => n.sortKey == null)) {
        for (var i = 0; i < rows.length; i++) {
          await (update(notes)..where((t) => t.id.equals(rows[i].id)))
              .write(NotesCompanion(sortKey: Value(i)));
        }
        final trashed = await (select(notes)
              ..where((t) =>
                  t.notebookId.equals(note.notebookId) &
                  t.deletedAt.isNotNull())
              ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
            .get();
        for (var i = 0; i < trashed.length; i++) {
          await (update(notes)..where((t) => t.id.equals(trashed[i].id)))
              .write(NotesCompanion(sortKey: Value(rows.length + i)));
        }
      }
      final aKey = rows[index].sortKey ?? index;
      final bKey = rows[target].sortKey ?? target;
      await (update(notes)..where((t) => t.id.equals(rows[index].id)))
          .write(NotesCompanion(sortKey: Value(bKey)));
      await (update(notes)..where((t) => t.id.equals(rows[target].id)))
          .write(NotesCompanion(sortKey: Value(aKey)));
    });
    developer.log(
        'done, 笔记已移动, noteId: $id, notebookId: ${note.notebookId}, from: $index, to: $target');
  }

  Future<List<Note>> listAllNotes() => select(notes).get();

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
    return saveNote(noteId, version.title, version.content, coalesce: false);
  }

  Future<String?> getSetting(String key) async =>
      (await (select(settings)..where((t) => t.key.equals(key)))
          .getSingleOrNull())
      ?.value;

  Future<void> setSetting(String key, String value) => into(settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  Future<void> deleteSetting(String key) =>
      (delete(settings)..where((t) => t.key.equals(key))).go();

  Future<void> setLastOpenNote(String scopeKey, String noteId) =>
      setSetting('$lastOpenNotePrefix$scopeKey', noteId);

  Future<void> clearLastOpenNote(String scopeKey) => (delete(settings)
        ..where((t) => t.key.equals('$lastOpenNotePrefix$scopeKey')))
      .go();

  Future<Map<String, String>> listLastOpenNotes() async {
    final rows = await (select(settings)
          ..where((t) => t.key.like('$lastOpenNotePrefix%')))
        .get();
    return {
      for (final row in rows)
        row.key.substring(lastOpenNotePrefix.length): row.value
    };
  }

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
        await addTombstone(note.id, syncKindNote);
      }
      final versions = await (delete(noteVersions)
            ..where((t) => t.createAt.isSmallerThanValue(versionCutoff)))
          .go();
      final tombstoneCutoff = now - tombstoneRetentionDays * msPerDay;
      final staleTombstones = await (delete(tombstones)
            ..where((t) => t.deletedAt.isSmallerThanValue(tombstoneCutoff)))
          .go();
      developer.log(
          'done, 过期清理完成, purgedNotes: ${expired.length}, purgedVersions: $versions, staleTombstones: $staleTombstones, trashDays: $trashDays, versionDays: $versionDays, tombstoneDays: $tombstoneRetentionDays');
    });
  }
}