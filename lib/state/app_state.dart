import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../data/app_db.dart';
import '../data/attachment_store.dart';

enum NoteScopeKind { all, notebook, trash }

class NoteScope {
  const NoteScope.all() : kind = NoteScopeKind.all, notebookId = null;
  const NoteScope.trash() : kind = NoteScopeKind.trash, notebookId = null;
  const NoteScope.notebook(String this.notebookId)
      : kind = NoteScopeKind.notebook;

  final NoteScopeKind kind;
  final String? notebookId;

  bool sameAs(NoteScope other) =>
      kind == other.kind && notebookId == other.notebookId;
}

class AppState extends ChangeNotifier {
  AppState(this.db);

  final AppDb db;

  AttachmentStore? attachments;

  List<Notebook> notebooks = [];
  NoteScope scope = const NoteScope.all();
  List<Note> notes = [];
  String? openNoteId;
  Set<String> searchScope = {};
  Map<String, String> lastOpenNote = {};

  Future<void> init() async {
    if (!kIsWeb) {
      attachments = await AttachmentStore.open();
      await purgeAttachments();
    } else {
      developer.log('skip, web 端附件存储未启用, 原因: 附件随同步阶段支持 web');
    }
    notebooks = await db.listNotebooks();
    final saved = await db.getSetting(AppDb.searchScopeKey);
    if (saved != null && saved.isNotEmpty) {
      searchScope = saved
          .split(',')
          .where((id) => notebooks.any((n) => n.id == id))
          .toSet();
    }
    for (final entry in (await db.listLastOpenNotes()).entries) {
      if (entry.key == AppDb.allNotesScopeKey ||
          notebooks.any((n) => n.id == entry.key)) {
        lastOpenNote[entry.key] = entry.value;
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    notebooks = await db.listNotebooks();
    if (scope.kind == NoteScopeKind.notebook &&
        !notebooks.any((n) => n.id == scope.notebookId)) {
      developer.log('hit, 当前笔记本已不存在回到全部, notebookId: ${scope.notebookId}');
      scope = const NoteScope.all();
    }
    notes = switch (scope.kind) {
      NoteScopeKind.all => await db.listNotes(),
      NoteScopeKind.notebook =>
        await db.listNotes(notebookId: scope.notebookId),
      NoteScopeKind.trash => await db.listTrash(),
    };
    notifyListeners();
  }

  Future<void> selectScope(NoteScope next) async {
    scope = next;
    openNoteId = null;
    await refresh();
  }

  void autoOpenCurrentScope() {
    final id = _resolveAutoOpen();
    if (id == null || id == openNoteId) {
      return;
    }
    openNoteId = id;
    developer.log(
        'hit, 宽屏自动打开笔记, scope: ${scope.kind.name}, notebookId: ${scope.notebookId}, noteId: $id');
    notifyListeners();
  }

  Future<Notebook> createNotebook(String name) async {
    final notebook = await db.createNotebook(name);
    await refresh();
    return notebook;
  }

  Future<void> renameNotebook(String id, String name) async {
    await db.renameNotebook(id, name);
    await refresh();
  }

  Future<void> deleteNotebook(String id) async {
    await db.deleteNotebook(id);
    lastOpenNote.remove(id);
    await db.clearLastOpenNote(id);
    await refresh();
  }

  Future<Note?> createNote() async {
    if (notebooks.isEmpty) {
      developer.log('skip, 没有笔记本无法新建笔记, notebookCount: 0');
      return null;
    }
    final target = scope.kind == NoteScopeKind.notebook
        ? scope.notebookId!
        : notebooks.first.id;
    final note = await db.createNote(target);
    await refresh();
    await openNote(note.id);
    return note;
  }

  Future<void> openNote(String id) async {
    openNoteId = id;
    notifyListeners();
    final note = notes.where((n) => n.id == id).firstOrNull;
    if (note != null) {
      await _rememberOpen(note);
    }
  }

  Future<void> _rememberOpen(Note note) async {
    developer.log(
        'done, 记录作用域最近打开, notebookId: ${note.notebookId}, noteId: ${note.id}');
    lastOpenNote[note.notebookId] = note.id;
    await db.setLastOpenNote(note.notebookId, note.id);
    if (scope.kind == NoteScopeKind.all) {
      lastOpenNote[AppDb.allNotesScopeKey] = note.id;
      await db.setLastOpenNote(AppDb.allNotesScopeKey, note.id);
    }
  }

  void closeNote() {
    openNoteId = null;
    notifyListeners();
  }

  Future<void> trashNote(String id) async {
    await db.softDeleteNote(id);
    if (openNoteId == id) {
      openNoteId = null;
    }
    await refresh();
  }

  Future<void> restoreNote(String id) async {
    await db.restoreNote(id);
    await refresh();
  }

  Future<void> hardDeleteNote(String id) async {
    await db.hardDeleteNote(id);
    if (openNoteId == id) {
      openNoteId = null;
    }
    await refresh();
  }

  Future<void> purgeAttachments() async {
    final store = attachments;
    if (store == null) {
      return;
    }
    await store.purgeUnreferenced(await db.allAttachmentRefs());
  }

  Future<List<Note>> search(String query) => db.searchNotes(query, searchScope);

  Future<void> setSearchScope(Set<String> ids) async {
    searchScope = ids;
    await db.setSetting(AppDb.searchScopeKey, ids.join(','));
    notifyListeners();
  }

  String? _resolveAutoOpen() {
    if (scope.kind == NoteScopeKind.trash || notes.isEmpty) {
      return null;
    }
    final remembered = lastOpenNote[_lastOpenKey];
    final hit = notes.where((n) => n.id == remembered).firstOrNull;
    if (hit != null) {
      return hit.id;
    }
    if (remembered != null) {
      developer.log(
          'skip, 记忆的笔记已不在列表回退第一篇, scopeKey: $_lastOpenKey, staleNoteId: $remembered');
    }
    return notes.first.id;
  }

  String get _lastOpenKey => scope.kind == NoteScopeKind.notebook
      ? scope.notebookId!
      : AppDb.allNotesScopeKey;

  Notebook? _notebook(String notebookId) =>
      notebooks.where((n) => n.id == notebookId).firstOrNull;

  String notebookName(String notebookId) =>
      _notebook(notebookId)?.name ?? '?';

  int notebookColor(String notebookId) =>
      _notebook(notebookId)?.color ?? notebookPalette.first;
}