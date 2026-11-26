import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  late AppDb db;
  late AppState state;
  var now = 1700000000000;

  setUp(() async {
    now = 1700000000000;
    supportDir = await Directory.systemTemp.createTemp('onenote_state_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    db = AppDb(NativeDatabase.memory(), clock: () => now);
    state = AppState(db);
  });

  tearDown(() async {
    state.dispose();
    await db.close();
    await supportDir.delete(recursive: true);
  });

  Future<Note> seed(Notebook notebook, String title) async {
    now += 1000;
    return db.createNote(notebook.id, title: title, content: '$title body');
  }

  Future<AppState> restartedState() async {
    final fresh = AppState(db);
    addTearDown(fresh.dispose);
    await fresh.init();
    return fresh;
  }

  test('search scope 全选归一为全部且新笔记本自动纳入', () async {
    final work = await db.createNotebook('work');
    now += 1000;
    final notes = await db.createNotebook('notes');
    await state.init();
    await state.setSearchScope({work.id, notes.id});
    expect(state.searchScope, isEmpty);
    expect(await db.getSetting(AppDb.searchScopeKey), '');
    final restarted = await restartedState();
    expect(restarted.searchScope, isEmpty);

    now += 1000;
    final fresh = await db.createNotebook('fresh');
    await state.refresh();
    await seed(fresh, 'hidden');
    expect((await state.search('hidden')).map((n) => n.title), ['hidden']);
  });

  test('search scope 全不选为全部, 部分勾选只搜所选且重启保留', () async {
    await state.init();
    final work = await db.createNotebook('work');
    now += 1000;
    final life = await db.createNotebook('life');
    await state.refresh();
    final workNote = await seed(work, 'shared');
    await seed(life, 'shared');

    await state.setSearchScope({});
    expect(await state.search('shared'), hasLength(2));

    await state.setSearchScope({work.id});
    expect(state.searchScope, {work.id});
    final hits = await state.search('shared');
    expect(hits.map((n) => n.id), [workNote.id]);
    final restarted = await restartedState();
    expect(restarted.searchScope, {work.id});
  });

  test('startup auto-opens remembered note across restart', () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    final second = await seed(work, 'second');
    await state.init();
    state.autoOpenCurrentScope();
    expect(state.openNoteId, second.id);
    await state.openNote(first.id);

    final restarted = await restartedState();
    expect(restarted.scope.kind, NoteScopeKind.all);
    expect(restarted.openNoteId, isNull);
    restarted.autoOpenCurrentScope();
    expect(restarted.openNoteId, first.id);
  });

  test('notebook scope falls back to first then keeps its own memory',
      () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    final second = await seed(work, 'second');
    final life = await db.createNotebook('life');
    final lifeNote = await seed(life, 'life-note');
    await state.init();

    await state.selectScope(NoteScope.notebook(work.id));
    expect(state.openNoteId, isNull);
    state.autoOpenCurrentScope();
    expect(state.openNoteId, second.id);
    await state.openNote(first.id);

    await state.selectScope(NoteScope.notebook(life.id));
    state.autoOpenCurrentScope();
    expect(state.openNoteId, lifeNote.id);

    await state.selectScope(NoteScope.notebook(work.id));
    state.autoOpenCurrentScope();
    expect(state.openNoteId, first.id);
  });

  test('all scope remembers last opened over newest-first order', () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    await seed(work, 'second');
    await state.init();
    state.autoOpenCurrentScope();
    await state.openNote(first.id);

    await state.selectScope(NoteScope.notebook(work.id));
    state.autoOpenCurrentScope();
    expect(state.openNoteId, first.id);
    await state.selectScope(const NoteScope.all());
    state.autoOpenCurrentScope();
    expect(state.openNoteId, first.id);
  });

  test('trashing remembered note falls back without reopening stale memory',
      () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    final second = await seed(work, 'second');
    await state.init();
    state.autoOpenCurrentScope();
    await state.openNote(first.id);

    await state.trashNote(first.id);
    expect(state.openNoteId, isNull);
    state.autoOpenCurrentScope();
    expect(state.openNoteId, second.id);

    await state.selectScope(NoteScope.notebook(work.id));
    state.autoOpenCurrentScope();
    expect(state.openNoteId, second.id);

    final restarted = await restartedState();
    restarted.autoOpenCurrentScope();
    expect(restarted.openNoteId, second.id);
  });

  test('trash scope never auto-opens', () async {
    final work = await db.createNotebook('work');
    final note = await seed(work, 'only');
    await db.softDeleteNote(note.id);
    await state.init();
    state.autoOpenCurrentScope();
    expect(state.openNoteId, isNull);
    await state.selectScope(const NoteScope.trash());
    state.autoOpenCurrentScope();
    expect(state.notes, hasLength(1));
    expect(state.openNoteId, isNull);
  });

  test('empty notebook stays blank until a note is created', () async {
    final temp = await db.createNotebook('temp');
    await state.init();
    await state.selectScope(NoteScope.notebook(temp.id));
    state.autoOpenCurrentScope();
    expect(state.openNoteId, isNull);

    final note = await state.createNote();
    expect(state.openNoteId, note!.id);
    expect(
        await db.getSetting('${AppDb.lastOpenNotePrefix}${temp.id}'), note.id);

    await state.trashNote(note.id);
    await state.hardDeleteNote(note.id);
    await state.deleteNotebook(temp.id);
    expect(await db.getSetting('${AppDb.lastOpenNotePrefix}${temp.id}'), isNull);
    expect(state.lastOpenNote.containsKey(temp.id), isFalse);
  });

  test('opening a search hit from another notebook records both memories',
      () async {
    final work = await db.createNotebook('work');
    await seed(work, 'first');
    final life = await db.createNotebook('life');
    final other = await seed(life, 'flutter recipe');
    await state.init();
    await state.selectScope(NoteScope.notebook(work.id));

    final hits = await state.search('recipe');
    expect(hits.single.id, other.id);
    await state.selectScope(const NoteScope.all());
    await state.openNote(other.id);

    await state.selectScope(NoteScope.notebook(work.id));
    await state.selectScope(NoteScope.notebook(life.id));
    state.autoOpenCurrentScope();
    expect(state.openNoteId, other.id);
    await state.selectScope(const NoteScope.all());
    state.autoOpenCurrentScope();
    expect(state.openNoteId, other.id);
  });

  test('pane widths persist across restart and clamp out-of-range values',
      () async {
    await state.init();
    expect(state.sidebarWidth, AppState.sidebarDefaultWidth);
    expect(state.listWidth, AppState.listDefaultWidth);

    state.updateSidebarWidth(320.4);
    state.updateListWidth(9000);
    expect(state.listWidth, AppState.listMaxWidth);
    await state.persistPaneWidths();

    final restarted = await restartedState();
    expect(restarted.sidebarWidth, 320);
    expect(restarted.listWidth, AppState.listMaxWidth);
  });

  test('invalid persisted pane widths fall back to defaults', () async {
    await db.setSetting(AppDb.paneWidthSidebarKey, 'oops');
    await db.setSetting(AppDb.paneWidthListKey, '-5');
    await state.init();
    expect(state.sidebarWidth, AppState.sidebarDefaultWidth);
    expect(state.listWidth, AppState.listMinWidth);
  });

  test('typography defaults to MiSans 100% and 18px', () async {
    await state.init();
    expect(state.uiFont, AppState.uiFontMiSans);
    expect(state.fontScale, AppState.fontScaleDefault);
    expect(state.noteFontSize, AppState.noteFontSizeDefault);
  });

  test('typography settings persist across restart and clamp updates',
      () async {
    await state.init();
    await state.setUiFont(AppState.uiFontInter);
    state.updateFontScale(1.2);
    state.updateNoteFontSize(20.4);
    expect(state.noteFontSize, 20);
    state.updateFontScale(9);
    expect(state.fontScale, AppState.fontScaleMax);
    state.updateNoteFontSize(1);
    expect(state.noteFontSize, AppState.noteFontSizeMin);
    await state.persistFontSizes();

    final restarted = await restartedState();
    expect(restarted.uiFont, AppState.uiFontInter);
    expect(restarted.fontScale, AppState.fontScaleMax);
    expect(restarted.noteFontSize, AppState.noteFontSizeMin);
  });

  test('invalid persisted typography falls back or clamps', () async {
    await db.setSetting(AppDb.uiFontKey, 'comic-sans');
    await db.setSetting(AppDb.uiFontScaleKey, 'oops');
    await db.setSetting(AppDb.noteFontSizeKey, '99');
    await state.init();
    expect(state.uiFont, AppState.uiFontMiSans);
    expect(state.fontScale, AppState.fontScaleDefault);
    expect(state.noteFontSize, AppState.noteFontSizeMax);
  });

  test('setUiFont rejects unknown ids without touching state', () async {
    await state.init();
    await state.setUiFont('bogus');
    expect(state.uiFont, AppState.uiFontMiSans);
    expect(await db.getSetting(AppDb.uiFontKey), isNull);
  });

  test('restart restores last view scope and note', () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    final life = await db.createNotebook('life');
    await seed(life, 'life-note');
    await state.init();
    await state.selectScope(NoteScope.notebook(work.id));
    await state.openNote(first.id);

    final restarted = await restartedState();
    expect(restarted.scope.kind, NoteScopeKind.notebook);
    expect(restarted.scope.notebookId, work.id);
    expect(restarted.openNoteId, isNull);
    expect(restarted.startupRestorePending, isTrue);
    await restarted.resolveStartupRestore(isWide: false);
    expect(restarted.openNoteId, first.id);
    expect(restarted.startupRestorePending, isFalse);
  });

  test('narrow list setting skips restore but keeps scope and auto-open',
      () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    await state.init();
    await state.setNarrowStartup(AppState.narrowStartupList);
    await state.selectScope(NoteScope.notebook(work.id));
    await state.openNote(first.id);

    final restarted = await restartedState();
    expect(restarted.narrowStartup, AppState.narrowStartupList);
    expect(restarted.scope.notebookId, work.id);
    await restarted.resolveStartupRestore(isWide: false);
    expect(restarted.openNoteId, isNull);
    expect(restarted.startupRestorePending, isFalse);
    restarted.autoOpenCurrentScope();
    expect(restarted.openNoteId, first.id);
  });

  test('wide startup ignores narrow list setting', () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    await state.init();
    await state.setNarrowStartup(AppState.narrowStartupList);
    await state.openNote(first.id);

    final restarted = await restartedState();
    await restarted.resolveStartupRestore(isWide: true);
    expect(restarted.openNoteId, first.id);
  });

  test('trash view restores scope and open trash note', () async {
    final work = await db.createNotebook('work');
    final note = await seed(work, 'trashed');
    await state.init();
    await state.trashNote(note.id);
    await state.selectScope(const NoteScope.trash());
    await state.openNote(note.id);

    final restarted = await restartedState();
    expect(restarted.scope.kind, NoteScopeKind.trash);
    await restarted.resolveStartupRestore(isWide: true);
    expect(restarted.openNoteId, note.id);
  });

  test('closing note persists list-only view', () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    await state.init();
    await state.openNote(first.id);
    expect(await db.getSetting(AppDb.lastViewNoteKey), first.id);
    await state.closeNote();
    expect(await db.getSetting(AppDb.lastViewNoteKey), isNull);

    final restarted = await restartedState();
    await restarted.resolveStartupRestore(isWide: false);
    expect(restarted.openNoteId, isNull);
  });

  test('deleting scope notebook rewrites view to all', () async {
    final work = await db.createNotebook('work');
    await seed(work, 'keeper');
    final temp = await db.createNotebook('temp');
    await state.init();
    await state.selectScope(NoteScope.notebook(temp.id));
    await state.deleteNotebook(temp.id);
    expect(state.scope.kind, NoteScopeKind.all);
    expect(await db.getSetting(AppDb.lastViewScopeKey), AppDb.allNotesScopeKey);
  });

  test('invalid persisted view scope and startup value fall back', () async {
    await db.setSetting(AppDb.lastViewScopeKey, 'notebook:missing');
    await db.setSetting(AppDb.lastViewNoteKey, 'gone-note');
    await db.setSetting(AppDb.narrowStartupKey, 'oops');
    await state.init();
    expect(state.scope.kind, NoteScopeKind.all);
    expect(state.narrowStartup, AppState.narrowStartupNote);
    await state.resolveStartupRestore(isWide: true);
    expect(state.openNoteId, isNull);
  });

  test('user action before resolve wins over pending restore', () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    final second = await seed(work, 'second');
    await state.init();
    await state.openNote(first.id);

    final restarted = await restartedState();
    await restarted.openNote(second.id);
    await restarted.resolveStartupRestore(isWide: true);
    expect(restarted.openNoteId, second.id);
  });

  test('trashing open note clears persisted view note', () async {
    final work = await db.createNotebook('work');
    final first = await seed(work, 'first');
    await state.init();
    await state.openNote(first.id);
    await state.trashNote(first.id);
    expect(await db.getSetting(AppDb.lastViewNoteKey), isNull);
  });

  test('setNarrowStartup rejects unknown ids without touching state',
      () async {
    await state.init();
    await state.setNarrowStartup('bogus');
    expect(state.narrowStartup, AppState.narrowStartupNote);
    expect(await db.getSetting(AppDb.narrowStartupKey), isNull);
  });

  test('setNotebookColor refreshes notebook list and lookup', () async {
    final work = await db.createNotebook('work');
    await state.init();
    var notified = 0;
    state.addListener(() => notified++);
    await state.setNotebookColor(work.id, 0xFF16A34A);
    expect(state.notebookColor(work.id), 0xFF16A34A);
    expect(state.notebooks.single.color, 0xFF16A34A);
    expect(notified, greaterThan(0));
    expect((await db.listNotebooks()).single.color, 0xFF16A34A);
  });
}