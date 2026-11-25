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
}