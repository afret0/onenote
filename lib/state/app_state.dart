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
    openNoteId = note.id;
    notifyListeners();
    return note;
  }

  void openNote(String id) {
    openNoteId = id;
    notifyListeners();
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

  Notebook? _notebook(String notebookId) =>
      notebooks.where((n) => n.id == notebookId).firstOrNull;

  String notebookName(String notebookId) =>
      _notebook(notebookId)?.name ?? '?';

  int notebookColor(String notebookId) =>
      _notebook(notebookId)?.color ?? notebookPalette.first;
}