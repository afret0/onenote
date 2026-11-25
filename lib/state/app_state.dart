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

  static const sidebarMinWidth = 200.0;
  static const sidebarMaxWidth = 400.0;
  static const sidebarDefaultWidth = 268.0;
  static const listMinWidth = 240.0;
  static const listMaxWidth = 480.0;
  static const listDefaultWidth = 320.0;
  static const contentMinWidth = 360.0;
  static const uiFontInter = 'inter';
  static const uiFontMiSans = 'misans';
  static const fontScaleMin = 0.85;
  static const fontScaleMax = 1.4;
  static const fontScaleDefault = 1.0;
  static const noteFontSizeMin = 14.0;
  static const noteFontSizeMax = 24.0;
  static const noteFontSizeDefault = 18.0;
  static const narrowStartupNote = 'note';
  static const narrowStartupList = 'list';
  static const _notebookScopePrefix = 'notebook:';

  final AppDb db;

  AttachmentStore? attachments;

  List<Notebook> notebooks = [];
  NoteScope scope = const NoteScope.all();
  List<Note> notes = [];
  String? openNoteId;
  Set<String> searchScope = {};
  Map<String, String> lastOpenNote = {};
  String narrowStartup = narrowStartupNote;
  bool _startupRestorePending = true;
  double sidebarWidth = sidebarDefaultWidth;
  double listWidth = listDefaultWidth;
  String uiFont = uiFontMiSans;
  double fontScale = fontScaleDefault;
  double noteFontSize = noteFontSizeDefault;

  Future<void> init() async {
    if (!kIsWeb) {
      attachments = await AttachmentStore.open();
      await purgeAttachments();
    } else {
      developer.log('skip, web 端附件存储未启用, 原因: 附件随同步阶段支持 web');
    }
    notebooks = await db.listNotebooks();
    sidebarWidth = _loadedDouble(await db.getSetting(AppDb.paneWidthSidebarKey),
        sidebarDefaultWidth, sidebarMinWidth, sidebarMaxWidth);
    listWidth = _loadedDouble(await db.getSetting(AppDb.paneWidthListKey),
        listDefaultWidth, listMinWidth, listMaxWidth);
    final savedFont = await db.getSetting(AppDb.uiFontKey);
    if (savedFont == uiFontInter || savedFont == uiFontMiSans) {
      uiFont = savedFont!;
    } else if (savedFont != null) {
      developer.log('skip, 字体设置非法回退默认, raw: $savedFont, fallback: $uiFont');
    }
    fontScale = _loadedDouble(await db.getSetting(AppDb.uiFontScaleKey),
        fontScaleDefault, fontScaleMin, fontScaleMax);
    noteFontSize = _loadedDouble(await db.getSetting(AppDb.noteFontSizeKey),
        noteFontSizeDefault, noteFontSizeMin, noteFontSizeMax);
    final saved = await db.getSetting(AppDb.searchScopeKey);
    if (saved != null && saved.isNotEmpty) {
      searchScope = saved
          .split(',')
          .where((id) => notebooks.any((n) => n.id == id))
          .toSet();
    }
    final savedStartup = await db.getSetting(AppDb.narrowStartupKey);
    if (savedStartup == narrowStartupNote ||
        savedStartup == narrowStartupList) {
      narrowStartup = savedStartup!;
    } else if (savedStartup != null) {
      developer.log(
          'skip, 窄屏启动设置非法回退默认, raw: $savedStartup, fallback: $narrowStartup');
    }
    final savedScope = _parseScope(await db.getSetting(AppDb.lastViewScopeKey));
    if (savedScope != null) {
      scope = savedScope;
      developer.log(
          'done, 启动恢复上次作用域, scope: ${scope.kind.name}, notebookId: ${scope.notebookId}');
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

  bool get startupRestorePending => _startupRestorePending;

  Future<void> resolveStartupRestore({required bool isWide}) async {
    if (!_startupRestorePending) {
      return;
    }
    _startupRestorePending = false;
    if (!isWide && narrowStartup == narrowStartupList) {
      developer.log('skip, 窄屏启动设置为先看列表, scope: ${scope.kind.name}');
      notifyListeners();
      return;
    }
    final remembered = await db.getSetting(AppDb.lastViewNoteKey);
    if (openNoteId != null) {
      return;
    }
    final hit = notes.where((n) => n.id == remembered).firstOrNull;
    if (hit == null) {
      if (remembered != null) {
        developer.log(
            'skip, 上次打开的笔记已不在当前列表, scope: ${scope.kind.name}, staleNoteId: $remembered');
      }
      notifyListeners();
      return;
    }
    openNoteId = hit.id;
    developer.log(
        'done, 启动恢复上次页面, scope: ${scope.kind.name}, notebookId: ${scope.notebookId}, noteId: ${hit.id}');
    notifyListeners();
  }

  Future<void> selectScope(NoteScope next) async {
    _startupRestorePending = false;
    scope = next;
    openNoteId = null;
    await refresh();
    await _persistView();
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
    await _persistView();
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
    _startupRestorePending = false;
    openNoteId = id;
    notifyListeners();
    final note = notes.where((n) => n.id == id).firstOrNull;
    if (note != null) {
      await _rememberOpen(note);
    }
    await _persistView();
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

  Future<void> closeNote() async {
    _startupRestorePending = false;
    openNoteId = null;
    notifyListeners();
    await _persistView();
  }

  Future<void> trashNote(String id) async {
    await db.softDeleteNote(id);
    if (openNoteId == id) {
      openNoteId = null;
    }
    await refresh();
    await _persistView();
  }

  Future<void> restoreNote(String id) async {
    await db.restoreNote(id);
    await refresh();
    await _persistView();
  }

  Future<void> hardDeleteNote(String id) async {
    await db.hardDeleteNote(id);
    if (openNoteId == id) {
      openNoteId = null;
    }
    await refresh();
    await _persistView();
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

  Future<void> setNarrowStartup(String value) async {
    if (value != narrowStartupNote && value != narrowStartupList) {
      developer.log('skip, 未知窄屏启动标识不写入, narrowStartup: $value');
      return;
    }
    if (value == narrowStartup) {
      return;
    }
    narrowStartup = value;
    await db.setSetting(AppDb.narrowStartupKey, value);
    developer.log('done, 窄屏启动页面已切换, narrowStartup: $value');
    notifyListeners();
  }

  void updateSidebarWidth(double width) {
    final next = width.clamp(sidebarMinWidth, sidebarMaxWidth).toDouble();
    if (next == sidebarWidth) {
      return;
    }
    sidebarWidth = next;
    notifyListeners();
  }

  void updateListWidth(double width) {
    final next = width.clamp(listMinWidth, listMaxWidth).toDouble();
    if (next == listWidth) {
      return;
    }
    listWidth = next;
    notifyListeners();
  }

  Future<void> setUiFont(String font) async {
    if (font != uiFontInter && font != uiFontMiSans) {
      developer.log('skip, 未知字体标识不写入, font: $font');
      return;
    }
    if (font == uiFont) {
      return;
    }
    uiFont = font;
    await db.setSetting(AppDb.uiFontKey, font);
    developer.log('done, 界面字体已切换, uiFont: $font');
    notifyListeners();
  }

  void updateFontScale(double scale) {
    final next =
        (scale.clamp(fontScaleMin, fontScaleMax) * 100).roundToDouble() / 100;
    if (next == fontScale) {
      return;
    }
    fontScale = next;
    notifyListeners();
  }

  void updateNoteFontSize(double size) {
    final next = size.clamp(noteFontSizeMin, noteFontSizeMax).roundToDouble();
    if (next == noteFontSize) {
      return;
    }
    noteFontSize = next;
    notifyListeners();
  }

  Future<void> persistFontSizes() async {
    await db.setSetting(
        AppDb.uiFontScaleKey, fontScale.toStringAsFixed(2));
    await db.setSetting(
        AppDb.noteFontSizeKey, noteFontSize.round().toString());
    developer.log(
        'done, 字号设置已持久化, fontScale: $fontScale, noteFontSize: $noteFontSize');
  }

  Future<void> persistPaneWidths() async {
    await db.setSetting(
        AppDb.paneWidthSidebarKey, sidebarWidth.round().toString());
    await db.setSetting(AppDb.paneWidthListKey, listWidth.round().toString());
    developer.log(
        'done, 栏宽已持久化, sidebar: $sidebarWidth, list: $listWidth');
  }

  double _loadedDouble(String? raw, double fallback, double min, double max) {
    final parsed = raw == null ? null : double.tryParse(raw);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      if (raw != null) {
        developer.log('skip, 数值设置非法回退默认, raw: $raw, fallback: $fallback');
      }
      return fallback;
    }
    return parsed.clamp(min, max).toDouble();
  }

  Future<void> _persistView() async {
    final encoded = switch (scope.kind) {
      NoteScopeKind.all => AppDb.allNotesScopeKey,
      NoteScopeKind.trash => AppDb.trashScopeKey,
      NoteScopeKind.notebook => '$_notebookScopePrefix${scope.notebookId}',
    };
    await db.setSetting(AppDb.lastViewScopeKey, encoded);
    final id = openNoteId;
    if (id == null) {
      await db.deleteSetting(AppDb.lastViewNoteKey);
    } else {
      await db.setSetting(AppDb.lastViewNoteKey, id);
    }
  }

  NoteScope? _parseScope(String? raw) {
    if (raw == null) {
      return null;
    }
    if (raw == AppDb.allNotesScopeKey) {
      return const NoteScope.all();
    }
    if (raw == AppDb.trashScopeKey) {
      return const NoteScope.trash();
    }
    if (raw.startsWith(_notebookScopePrefix)) {
      final id = raw.substring(_notebookScopePrefix.length);
      if (notebooks.any((n) => n.id == id)) {
        return NoteScope.notebook(id);
      }
    }
    developer.log('skip, 上次页面作用域非法或笔记本已删回退全部, raw: $raw');
    return null;
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