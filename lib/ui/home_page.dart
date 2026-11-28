import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_db.dart';
import '../lock/biometrics.dart';
import '../richtext/markdown_codec.dart';
import '../state/app_state.dart';
import '../sync/sync_engine.dart';
import '../window_setup.dart';
import 'dialogs.dart';
import 'note_view.dart';
import 'notebook_color_picker.dart';
import 'password_prompts.dart';
import 'settings_page.dart';
import 'shell_background.dart';
import 'theme.dart';
import 'widgets.dart';

String syncResultMessage(SyncOutcome outcome, int remoteNotes) {
  if (!outcome.ran) {
    return '未配置同步，去设置页开启';
  }
  if (outcome.error != null) {
    return '同步失败：${outcome.error}';
  }
  final changed = outcome.uploadedNotes +
      outcome.downloadedNotes +
      outcome.uploadedAssets +
      outcome.downloadedAssets;
  final base = changed == 0
      ? '同步完成 · 无增量变化 · 远端 $remoteNotes 篇笔记与本地一致'
      : '同步完成 · 上传 ${outcome.uploadedNotes} · 下载 ${outcome.downloadedNotes}';
  return outcome.conflicts > 0
      ? '$base · ${outcome.conflicts} 处冲突待裁决'
      : base;
}

String formatSyncCaption(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final hm = formatHm(ms);
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return hm;
  }
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.month)}-${two(dt.day)} $hm';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _homeFocus = FocusNode();
  GlobalKey<NoteViewState> _noteViewKey = GlobalKey<NoteViewState>();
  String? _noteViewKeyId;
  List<Note>? _searchHits;
  int _searchSeq = 0;
  bool _refreshingHits = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.onAppLocking = _flushOpenEdits;
    state.addListener(_refreshSearchHits);
    HardwareKeyboard.instance.addHandler(_renewAppLeaseOnKey);
    GestureBinding.instance.pointerRouter
        .addGlobalRoute(_renewAppLeaseOnPointer);
  }

  bool _renewAppLeaseOnKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      state.touchAppActivity();
    }
    return false;
  }

  void _renewAppLeaseOnPointer(PointerEvent event) {
    if (event is PointerSignalEvent) {
      state.touchAppActivity();
    }
  }

  Future<void> _flushOpenEdits() async {
    await _noteViewKey.currentState?.flushEdits();
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_renewAppLeaseOnPointer);
    HardwareKeyboard.instance.removeHandler(_renewAppLeaseOnKey);
    if (state.onAppLocking == _flushOpenEdits) {
      state.onAppLocking = null;
    }
    state.removeListener(_refreshSearchHits);
    _searchController.dispose();
    _searchFocus.dispose();
    _homeFocus.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _newNotebook() async {
    final name = await promptText(
      context,
      title: '新建笔记本',
      label: '名称',
      hint: '例如：工作随笔',
    );
    if (name != null && name.isNotEmpty) {
      await state.createNotebook(name);
    }
  }

  Future<void> _notebookContext(Notebook notebook, Offset position) async {
    final index = state.notebooks.indexWhere((n) => n.id == notebook.id);
    final locked = state.isNotebookLocked(notebook.id);
    final hasPassword = state.notebookLock(notebook.id)?.active == true;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & MediaQuery.sizeOf(context),
      ),
      items: [
        if (locked)
          const PopupMenuItem(value: 'unlock', child: Text('输入密码解锁')),
        PopupMenuItem(
            value: 'up',
            enabled: !locked && index > 0,
            child: const Text('上移')),
        PopupMenuItem(
            value: 'down',
            enabled:
                !locked && index >= 0 && index < state.notebooks.length - 1,
            child: const Text('下移')),
        PopupMenuItem(
            value: 'rename',
            enabled: !locked,
            child: const Text('重命名')),
        PopupMenuItem(
            value: 'color',
            enabled: !locked,
            child: const Text('自定义背景色')),
        PopupMenuItem(
            value: 'password',
            child: Text(hasPassword ? '修改密码' : '设置密码')),
        if (hasPassword)
          const PopupMenuItem(value: 'removePassword', child: Text('移除密码')),
        PopupMenuItem(
            value: 'delete',
            enabled: !locked,
            child: const Text('删除')),
      ],
    );
    if (!mounted || value == null) {
      return;
    }
    if (value == 'unlock') {
      await unlockNotebookDialog(context, state, notebook.id);
    } else if (value == 'up') {
      await state.moveNotebook(notebook.id, -1);
    } else if (value == 'down') {
      await state.moveNotebook(notebook.id, 1);
    } else if (value == 'rename') {
      await _renameNotebook(notebook);
    } else if (value == 'color') {
      await _customizeNotebookColor(notebook);
    } else if (value == 'password') {
      await setNotebookPasswordFlow(context, state, notebook.id);
    } else if (value == 'removePassword') {
      await removeNotebookPasswordFlow(context, state, notebook.id);
    } else if (value == 'delete') {
      await _deleteNotebook(notebook);
    }
  }

  Future<void> _customizeNotebookColor(Notebook notebook) async {
    final color = await pickNotebookColor(context, initial: notebook.color);
    if (color != null) {
      await state.setNotebookColor(notebook.id, color);
    }
  }

  Future<void> _renameNotebook(Notebook notebook) async {
    final name = await promptText(
      context,
      title: '重命名笔记本',
      label: '名称',
      initial: notebook.name,
    );
    if (name != null && name.isNotEmpty) {
      await state.renameNotebook(notebook.id, name);
    }
  }

  Future<void> _deleteNotebook(Notebook notebook) async {
    final ok = await confirm(
      context,
      title: '删除笔记本',
      message: '删除「${notebook.name}」？',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok) {
      return;
    }
    try {
      await state.deleteNotebook(notebook.id);
    } on NotebookNotEmptyException catch (err) {
      _snack('Notebook is not empty (${err.noteCount} notes, trash included).');
    }
  }

  Future<void> _newNote() async {
    if (state.notebooks.isEmpty) {
      _snack('请先创建一个笔记本');
      return;
    }
    final target = state.scope.kind == NoteScopeKind.notebook
        ? state.scope.notebookId!
        : state.notebooks.first.id;
    if (state.isNotebookLocked(target)) {
      final ok = await unlockNotebookDialog(context, state, target);
      if (!ok || !mounted) {
        return;
      }
    }
    final note = await state.createNote();
    if (note == null && mounted) {
      _snack('请先创建一个笔记本');
    }
  }

  Future<void> _noteContext(Note note, Offset position,
      {bool canReorder = false}) async {
    final index = state.notes.indexWhere((n) => n.id == note.id);
    final locked = state.isNoteLocked(note.id);
    final hasPassword = state.noteLock(note.id)?.active == true;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & MediaQuery.sizeOf(context),
      ),
      items: [
        if (locked)
          const PopupMenuItem(value: 'unlock', child: Text('输入密码解锁')),
        PopupMenuItem(
            value: 'up',
            enabled: !locked && canReorder && index > 0,
            child: const Text('上移')),
        PopupMenuItem(
            value: 'down',
            enabled: !locked &&
                canReorder &&
                index >= 0 &&
                index < state.notes.length - 1,
            child: const Text('下移')),
        PopupMenuItem(
            value: 'history',
            enabled: !locked,
            child: const Text('版本历史')),
        PopupMenuItem(
            value: 'format',
            enabled: !locked,
            child: Text(note.format == AppDb.noteFormatRichtext
                ? '转为 Markdown'
                : '转为富文本')),
        PopupMenuItem(
            value: 'password',
            child: Text(hasPassword ? '修改密码' : '设置密码')),
        if (hasPassword)
          const PopupMenuItem(value: 'removePassword', child: Text('移除密码')),
        PopupMenuItem(
            value: 'trash',
            enabled: !locked,
            child: const Text('删除')),
      ],
    );
    if (!mounted || value == null) {
      return;
    }
    if (value == 'unlock') {
      await unlockNoteDialog(context, state, note.id);
    } else if (value == 'up') {
      await state.moveNote(note.id, -1);
    } else if (value == 'down') {
      await state.moveNote(note.id, 1);
    } else if (value == 'history') {
      await showNoteHistory(context, state: state, noteId: note.id);
    } else if (value == 'format') {
      await _switchNoteFormat(note);
    } else if (value == 'password') {
      await setNotePasswordFlow(context, state, note.id);
    } else if (value == 'removePassword') {
      await removeNotePasswordFlow(context, state, note.id);
    } else if (value == 'trash') {
      await _trashFromList(note);
    }
  }

  Future<void> _switchNoteFormat(Note note) async {
    final toRichtext = note.format != AppDb.noteFormatRichtext;
    final target =
        toRichtext ? AppDb.noteFormatRichtext : AppDb.noteFormatMarkdown;
    if (state.openNoteId == note.id) {
      await _noteViewKey.currentState?.flushEdits();
      if (!mounted) {
        return;
      }
    }
    if (toRichtext) {
      final fresh = await state.db.getNote(note.id);
      final lossy = richtextLossyParts(fresh.content);
      if (lossy.isNotEmpty) {
        if (!mounted) {
          return;
        }
        final ok = await confirm(context,
            title: '转为富文本',
            message: '以下内容无法在富文本中完整保留，转换后可能丢失：\n'
                '${lossy.join('、')}\n仍要转换吗？',
            confirmLabel: '仍要转换',
            danger: true);
        if (!ok || !mounted) {
          return;
        }
      }
    }
    await state.setNoteFormat(note.id, target);
  }

  Future<void> _trashFromList(Note note) async {
    final days = await state.db.retentionDays(AppDb.trashRetentionKey);
    if (!mounted) {
      return;
    }
    final ok = await confirm(context,
        title: '移入回收站',
        message: '「${noteDisplayTitle(note)}」将保留 $days 天，可随时恢复。');
    if (ok) {
      await state.trashNote(note.id);
    }
  }

  Future<void> _activateSearch() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    final width = MediaQuery.sizeOf(context).width;
    if (width < 900 && state.openNoteId != null) {
      await _noteViewKey.currentState?.flushEdits();
      if (!mounted) {
        return;
      }
      await state.closeNote();
    }
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocus.requestFocus();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openSettings() async {
    final lock = state.appLock;
    if (!state.systemLockTrusted && lock != null && lock.active) {
      var bioUnlocked = false;
      final password = await promptPassword(
        context,
        title: '验证应用密码',
        subtitle: '进入设置前验证',
        attempts: state.attempts,
        lock: lock,
        confirmLabel: '验证',
        onBiometric: state.lockBio
            ? () async {
                final ok = await Biometrics.authenticate('进入设置');
                if (ok) {
                  await state.attempts.succeed();
                  bioUnlocked = true;
                }
                return ok;
              }
            : null,
      );
      if (!mounted || (!bioUnlocked && password == null)) {
        developer.log('skip, 设置页密码验证未通过不进入');
        return;
      }
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsPage(state: state)),
    );
  }

  Future<void> _backToList() async {
    developer.log('hit, 系统返回拦截, 笔记页回列表, noteId: ${state.openNoteId}');
    await _flushOpenEdits();
    if (!mounted) {
      return;
    }
    await state.closeNote();
  }

  void _exitSearch() {
    if (_searchHits == null &&
        _searchController.text.isEmpty &&
        !_searchFocus.hasFocus) {
      return;
    }
    developer.log('hit, Esc 退出搜索模式');
    _searchSeq++;
    _searchController.clear();
    _searchFocus.unfocus();
    if (_homeFocus.context != null) {
      _homeFocus.requestFocus();
    }
    setState(() => _searchHits = null);
  }

  Future<void> _searchChanged(String value) async {
    final query = value.trim();
    final seq = ++_searchSeq;
    final hits = query.isEmpty ? null : await state.search(query);
    if (!mounted || seq != _searchSeq) {
      return;
    }
    setState(() => _searchHits = hits);
  }

  void _refreshSearchHits() {
    if (_searchHits == null || _refreshingHits) {
      return;
    }
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return;
    }
    final seq = _searchSeq;
    _refreshingHits = true;
    state.search(query).then((hits) {
      _refreshingHits = false;
      if (!mounted || seq != _searchSeq || _searchHits == null) {
        return;
      }
      if (_sameHits(_searchHits!, hits)) {
        return;
      }
      developer.log(
          'done, 数据变化后重建搜索结果, query: $query, ${_searchHits!.length} -> ${hits.length}');
      setState(() => _searchHits = hits);
    });
  }

  bool _sameHits(List<Note> a, List<Note> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _openHit(Note hit) async {
    if (state.isNoteLocked(hit.id)) {
      final ok = await unlockNoteDialog(context, state, hit.id);
      if (!ok || !mounted) {
        return;
      }
    }
    final scope = state.scope;
    if (scope.kind == NoteScopeKind.trash ||
        (scope.kind == NoteScopeKind.notebook &&
            scope.notebookId != hit.notebookId)) {
      await state.selectScope(const NoteScope.all());
      if (!mounted) {
        return;
      }
    }
    await state.openNote(hit.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final openId = state.openNoteId;
        if (openId != _noteViewKeyId) {
          _noteViewKey = GlobalKey<NoteViewState>();
          _noteViewKeyId = openId;
        }
        final windowWidth = MediaQuery.sizeOf(context).width;
        final isWide = windowWidth >= 900;
        final panes = isWide ? _paneWidths(windowWidth) : (0.0, 0.0);
        final drawerNeeded = !isWide && openId != null;
        final searching = _searchHits != null;
        if (state.startupRestorePending) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              state.resolveStartupRestore(isWide: isWide);
            }
          });
        } else if (isWide &&
            openId == null &&
            !searching &&
            state.scope.kind != NoteScopeKind.trash &&
            state.notes.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              state.autoOpenCurrentScope();
            }
          });
        }
        final scaffold = Scaffold(
          key: _scaffoldKey,
          drawer: isWide
              ? null
              : Drawer(
                  backgroundColor: inkOf(context).surface,
                  child: SafeArea(child: _sidebar(compact: true)),
                ),
          floatingActionButton:
              !isWide &&
                  openId == null &&
                  !searching &&
                  state.scope.kind != NoteScopeKind.trash
              ? FloatingActionButton(
                  backgroundColor: inkOf(context).accent,
                  foregroundColor: inkOf(context).onAccent,
                  onPressed: _newNote,
                  child: const Icon(Icons.edit_note),
                )
              : null,
          body: _withBackground(SafeArea(
            child: Row(
              children: [
                if (isWide)
                  SizedBox(
                      width: panes.$1,
                      child: _paneFill(
                          _sidebar(compact: false),
                          state.bgScope == AppState.bgScopeEmpty)),
                if (isWide)
                  _PaneDivider(
                    key: const Key('paneDivider:sidebar'),
                    onDelta: (delta) => state.updateSidebarWidth(
                      (panes.$1 + delta).clamp(
                        AppState.sidebarMinWidth,
                        math.min(
                          AppState.sidebarMaxWidth,
                          windowWidth -
                              _PaneDivider.hitWidth * 2 -
                              AppState.contentMinWidth -
                              panes.$2,
                        ),
                      ),
                    ),
                    onDragEnd: state.persistPaneWidths,
                  ),
                if (isWide)
                  SizedBox(
                      width: panes.$2,
                      child: _paneFill(_listPane(dense: true),
                          state.bgScope == AppState.bgScopeEmpty))
                else if (openId == null)
                  Expanded(
                      child: _paneFill(_listPane(),
                          state.bgScope == AppState.bgScopeEmpty)),
                if (isWide)
                  _PaneDivider(
                    key: const Key('paneDivider:list'),
                    onDelta: (delta) => state.updateListWidth(
                      (panes.$2 + delta).clamp(
                        AppState.listMinWidth,
                        math.min(
                          AppState.listMaxWidth,
                          windowWidth -
                              _PaneDivider.hitWidth * 2 -
                              AppState.contentMinWidth -
                              panes.$1,
                        ),
                      ),
                    ),
                    onDragEnd: state.persistPaneWidths,
                  ),
                if (isWide || openId != null)
                  Expanded(
                    child: openId != null
                        ? _paneFill(
                            NoteView(
                              key: _noteViewKey,
                              state: state,
                              noteId: openId,
                              showBack: drawerNeeded,
                              onBack: state.closeNote,
                              highlightQuery: searching
                                  ? _searchController.text.trim()
                                  : null,
                            ),
                            state.bgScope != AppState.bgScopeFull)
                        : _contentPlaceholder(),
                  ),
              ],
            ),
          )),
        );
        final guarded = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _exitSearch,
          },
          child: PopScope(
            canPop: isWide || openId == null,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) {
                return;
              }
              if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
                Navigator.of(context).pop();
                return;
              }
              _backToList();
            },
            child: scaffold,
          ),
        );
        Widget wrapped = guarded;
        if (isDesktopWindow) {
          wrapped = CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                  _activateSearch,
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _activateSearch,
              const SingleActivator(LogicalKeyboardKey.comma, meta: true):
                  _openSettings,
              const SingleActivator(LogicalKeyboardKey.comma, control: true):
                  _openSettings,
            },
            child: Focus(autofocus: true, focusNode: _homeFocus, child: wrapped),
          );
        }
        // 滚轮 PointerSignal 派发到最深的 Scrollable 即被 resolve，外层 Listener
        // 永远收不到；续租必须挂在 GestureBinding 的派发源头观测（不消费事件）
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => state.touchAppActivity(),
          child: wrapped,
        );
      },
    );
  }

  Widget _withBackground(Widget child) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
            child: ShellBackground(
                theme: state.bgThemeData, enabled: state.bgShapes)),
        child,
      ],
    );
  }

  Widget _paneFill(Widget child, bool opaque) {
    if (!opaque) {
      return child;
    }
    return ColoredBox(color: inkOf(context).paper, child: child);
  }

  (double, double) _paneWidths(double windowWidth) {
    final available =
        windowWidth - _PaneDivider.hitWidth * 2 - AppState.contentMinWidth;
    final sidebar = state.sidebarWidth.clamp(
      AppState.sidebarMinWidth,
      math.min(AppState.sidebarMaxWidth, available - AppState.listMinWidth),
    );
    final list = state.listWidth.clamp(
      AppState.listMinWidth,
      math.min(AppState.listMaxWidth, available - sidebar),
    );
    return (sidebar.toDouble(), list.toDouble());
  }

  Widget _syncButton() {
    final engine = state.sync;
    final hasError = engine.lastError != null;
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        tooltip: hasError ? '同步失败：${engine.lastError}' : '立即同步',
        onPressed: engine.syncing ? null : _manualSync,
        icon: engine.syncing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.sync,
                color: hasError ? inkOf(context).danger : null),
      ),
    );
  }

  Future<void> _manualSync() async {
    final outcome = await state.syncNow('manual');
    if (!mounted) {
      return;
    }
    final message = syncResultMessage(outcome, state.sync.remoteNoteCount);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sidebar({required bool compact}) {
    final scope = state.scope;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            spaceMd,
            spaceMd,
            spaceMd,
            spaceSm,
          ),
          child: Row(
            children: [
              const BrandMark(),
              const SizedBox(width: 10),
              Text(
                'onenote',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(letterSpacing: -0.2),
              ),
              const Spacer(),
              _syncButton(),
              const SizedBox(width: 4),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onPressed: _openSettings,
                  icon: const Icon(Icons.tune),
                ),
              ),
            ],
          ),
        ),
        if (state.sync.lastSyncAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(spaceMd, 0, spaceMd, spaceSm),
            child: Text(
              '上次同步 ${formatSyncCaption(state.sync.lastSyncAt!)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: inkOf(context).inkMuted),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: spaceSm),
            children: [
              ScopeTile(
                icon: Icons.notes,
                label: '全部',
                selected: scope.kind == NoteScopeKind.all,
                onTap: () {
                  state.selectScope(const NoteScope.all());
                  if (compact) Navigator.of(context).pop();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  spaceMd,
                  spaceMd,
                  spaceSm,
                  spaceXs,
                ),
                child: Row(
                  children: [
                    Text('笔记本', style: Theme.of(context).textTheme.labelSmall),
                    const Spacer(),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        onPressed: _newNotebook,
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  ],
                ),
              ),
              for (final notebook in state.notebooks)
                ScopeTile(
                  dotColor: Color(notebook.color),
                  label: notebook.name,
                  locked: state.isNotebookLocked(notebook.id),
                  selected:
                      scope.kind == NoteScopeKind.notebook &&
                      scope.notebookId == notebook.id,
                  onTap: () async {
                    if (state.isNotebookLocked(notebook.id)) {
                      final ok = await unlockNotebookDialog(
                          context, state, notebook.id);
                      if (!ok || !mounted) {
                        return;
                      }
                    }
                    await state.selectScope(NoteScope.notebook(notebook.id));
                    if (compact && mounted) Navigator.of(context).pop();
                  },
                  onContext: (position) => _notebookContext(notebook, position),
                ),
              const SizedBox(height: spaceSm),
              ScopeTile(
                icon: Icons.delete_outline,
                label: '回收站',
                selected: scope.kind == NoteScopeKind.trash,
                onTap: () {
                  state.selectScope(const NoteScope.trash());
                  if (compact) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _contentPlaceholder() {
    final t = inkOf(context);
    final isTrash = state.scope.kind == NoteScopeKind.trash;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.9,
            child: Image.asset(
              'assets/images/logo.png',
              width: 72,
              height: 72,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(height: spaceMd),
          Text(
            isTrash ? '回收站中的笔记可恢复或彻底删除' : '没有可显示的笔记',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: t.inkMuted),
          ),
          if (!isTrash && _searchHits == null) ...[
            const SizedBox(height: spaceMd),
            FilledButton.icon(
              onPressed: _newNote,
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('新建笔记'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _listPane({bool dense = false}) {
    final t = inkOf(context);
    final isTrash = state.scope.kind == NoteScopeKind.trash;
    final searching = _searchHits != null;
    final list = searching ? _searchHits! : state.notes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            spaceMd,
            spaceMd,
            spaceMd,
            spaceSm,
          ),
          child: Row(
            children: [
              if (!dense && MediaQuery.sizeOf(context).width < 900)
                IconButton(
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: _searchChanged,
                      decoration: InputDecoration(
                        prefixIcon: searching
                            ? Icon(Icons.search, color: t.inkFaint, size: 20)
                            : null,
                        suffixIcon: searching
                            ? IconButton(
                                onPressed: () {
                                  _searchSeq++;
                                  _searchController.clear();
                                  setState(() => _searchHits = null);
                                },
                                icon: const Icon(Icons.close, size: 18),
                              )
                            : null,
                      ),
                    ),
                    if (!searching)
                      IgnorePointer(
                        child: Icon(Icons.search, color: t.inkFaint, size: 20),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            spaceLg,
            spaceXs,
            spaceMd,
            spaceSm,
          ),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  searching ? '搜索结果' : _scopeTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(letterSpacing: -0.3),
                ),
              ),
              const SizedBox(width: spaceSm),
              Text(
                '${list.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  searching: searching,
                  isTrash: isTrash,
                  onNew: _newNote,
                )
              : searching
                  ? _searchList(list, dense: dense)
                  : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(spaceMd, 0, spaceMd, 96),
                  itemCount: list.length + (isTrash ? 0 : 1),
                  separatorBuilder: (_, _) => const SizedBox(height: spaceSm),
                  itemBuilder: (context, index) {
                    if (index == list.length) {
                      return Tooltip(
                        message: '新建笔记',
                        child: OutlinedButton(
                        onPressed: _newNote,
                        style: ButtonStyle(
                          mouseCursor: const WidgetStatePropertyAll(
                            SystemMouseCursors.click,
                          ),
                          foregroundColor: WidgetStatePropertyAll(
                            t.accentText,
                          ),
                          overlayColor: WidgetStatePropertyAll(t.accentSoft),
                          side: WidgetStatePropertyAll(
                            BorderSide(color: t.hairline),
                          ),
                          minimumSize: const WidgetStatePropertyAll(
                            Size(0, 44),
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(radiusMd),
                            ),
                          ),
                        ),
                        child: const Icon(Icons.add, size: 18),
                        ),
                      );
                    }
                    final note = list[index];
                    if (isTrash) {
                      return _trashCard(note);
                    }
                    return NoteCard(
                      note: note,
                      conflicted: state.sync.conflictIds.contains(note.id),
                      locked: state.isNoteLocked(note.id),
                      tintColor: Color(state.notebookColor(note.notebookId)),
                      striped: state.scope.kind != NoteScopeKind.notebook,
                      highlight: searching
                          ? _searchController.text.trim()
                          : null,
                      selected: dense && note.id == state.openNoteId,
                      dense: dense,
                      recessed: dense && state.openNoteId != null,
                      onTap: () async {
                        if (searching) {
                          await _openHit(note);
                          return;
                        }
                        if (state.isNoteLocked(note.id)) {
                          final ok =
                              await unlockNoteDialog(context, state, note.id);
                          if (!ok || !mounted) {
                            return;
                          }
                        }
                        await state.openNote(note.id);
                      },
                      onContext: (position) => _noteContext(note, position,
                          canReorder:
                              state.scope.kind == NoteScopeKind.notebook),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _searchList(List<Note> hits, {required bool dense}) {
    final t = inkOf(context);
    final entries = <_SearchEntry>[];
    for (final notebook in state.notebooks) {
      final group = hits.where((n) => n.notebookId == notebook.id).toList();
      if (group.isEmpty) {
        continue;
      }
      entries.add(_SearchEntry.header(notebook, group.length));
      for (final note in group) {
        entries.add(_SearchEntry.note(note));
      }
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(spaceMd, 0, spaceMd, 96),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: spaceSm),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final notebook = entry.notebook;
        if (notebook != null) {
          return Padding(
            key: ValueKey('searchGroup:${notebook.id}'),
            padding: EdgeInsets.only(top: index == 0 ? 0 : spaceMd),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Color(notebook.color),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notebook.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: t.inkMuted,
                    ),
                  ),
                ),
                Text(
                  '${entry.count}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          );
        }
        final note = entry.note!;
        return NoteCard(
          note: note,
          conflicted: state.sync.conflictIds.contains(note.id),
          locked: state.isNoteLocked(note.id),
          tintColor: Color(state.notebookColor(note.notebookId)),
          highlight: _searchController.text.trim(),
          selected: dense && note.id == state.openNoteId,
          dense: dense,
          recessed: dense && state.openNoteId != null,
          onTap: () => _openHit(note),
          onContext: (position) => _noteContext(note, position),
        );
      },
    );
  }

  String _scopeTitle() => switch (state.scope.kind) {
    NoteScopeKind.all => '全部',
    NoteScopeKind.trash => '回收站',
    NoteScopeKind.notebook => state.notebookName(state.scope.notebookId!),
  };

  Widget _trashCard(Note note) {
    final t = inkOf(context);
    final locked = state.isNoteLocked(note.id);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: t.hairline),
      ),
      padding: const EdgeInsets.fromLTRB(spaceMd, spaceMd, spaceSm, spaceMd),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        noteDisplayTitle(note),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: t.inkMuted),
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: spaceXs),
                      Icon(Icons.lock_outline, size: 16, color: t.inkMuted),
                    ],
                  ],
                ),
                const SizedBox(height: spaceXs),
                Text(
                  '${state.notebookName(note.notebookId)} · ${note.deletedAt == null ? '' : formatDateTime(note.deletedAt!)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              if (locked) {
                final ok = await unlockNoteDialog(context, state, note.id);
                if (!ok || !mounted) {
                  return;
                }
              }
              await state.restoreNote(note.id);
            },
            child: const Text('恢复'),
          ),
          TextButton(
            onPressed: () async {
              if (locked) {
                final unlocked =
                    await unlockNoteDialog(context, state, note.id);
                if (!unlocked || !mounted) {
                  return;
                }
              }
              final ok = await confirm(
                context,
                title: '彻底删除',
                message: '「${noteDisplayTitle(note)}」及其全部版本将被删除，不可恢复。',
                confirmLabel: '彻底删除',
                danger: true,
              );
              if (ok) {
                await state.hardDeleteNote(note.id);
              }
            },
            style: TextButton.styleFrom(foregroundColor: t.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _SearchEntry {
  const _SearchEntry.header(this.notebook, this.count) : note = null;
  const _SearchEntry.note(this.note)
    : notebook = null,
      count = 0;

  final Notebook? notebook;
  final Note? note;
  final int count;
}

class _PaneDivider extends StatefulWidget {
  const _PaneDivider({
    super.key,
    required this.onDelta,
    required this.onDragEnd,
  });

  static const hitWidth = 8.0;

  final void Function(double delta) onDelta;
  final Future<void> Function() onDragEnd;

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _hovering = false;
  bool _dragging = false;

  void _endDrag() {
    setState(() => _dragging = false);
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final active = _hovering || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onDelta(details.delta.dx),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: SizedBox(
          width: _PaneDivider.hitWidth,
          child: Center(
            child: Container(width: 1, color: active ? t.accent : t.hairline),
          ),
        ),
      ),
    );
  }
}
