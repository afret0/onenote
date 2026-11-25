import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../state/app_state.dart';
import 'dialogs.dart';
import 'note_view.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  List<Note>? _searchHits;

  AppState get state => widget.state;

  @override
  void dispose() {
    _searchController.dispose();
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
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & MediaQuery.sizeOf(context),
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (!mounted || value == null) {
      return;
    }
    if (value == 'rename') {
      await _renameNotebook(notebook);
    } else if (value == 'delete') {
      await _deleteNotebook(notebook);
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
    final note = await state.createNote();
    if (note == null) {
      _snack('请先创建一个笔记本');
    }
  }

  Future<void> _searchChanged(String value) async {
    final query = value.trim();
    final hits = query.isEmpty ? null : await state.search(query);
    if (!mounted) {
      return;
    }
    setState(() => _searchHits = hits);
  }

  Future<void> _openHit(Note hit) async {
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
        return Scaffold(
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
                  tooltip: '新建笔记',
                  child: const Icon(Icons.edit_note),
                )
              : null,
          body: SafeArea(
            child: Row(
              children: [
                if (isWide)
                  SizedBox(width: panes.$1, child: _sidebar(compact: false)),
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
                  SizedBox(width: panes.$2, child: _listPane(dense: true))
                else if (openId == null)
                  Expanded(child: _listPane()),
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
                        ? NoteView(
                            key: ValueKey(openId),
                            state: state,
                            noteId: openId,
                            showBack: drawerNeeded,
                            onBack: state.closeNote,
                          )
                        : _contentPlaceholder(),
                  ),
              ],
            ),
          ),
        );
      },
    );
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
              IconButton(
                tooltip: '设置',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SettingsPage(state: state)),
                ),
                icon: const Icon(Icons.tune),
              ),
            ],
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
                        tooltip: '新建笔记本',
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
                  selected:
                      scope.kind == NoteScopeKind.notebook &&
                      scope.notebookId == notebook.id,
                  onTap: () {
                    state.selectScope(NoteScope.notebook(notebook.id));
                    if (compact) Navigator.of(context).pop();
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
                  tooltip: '菜单',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _searchChanged,
                  decoration: InputDecoration(
                    hintText: '搜索标题与正文',
                    prefixIcon: Icon(Icons.search, color: t.inkFaint, size: 20),
                    suffixIcon: searching
                        ? IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchHits = null);
                            },
                            icon: const Icon(Icons.close, size: 18),
                          )
                        : null,
                  ),
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(spaceMd, 0, spaceMd, 96),
                  itemCount: list.length + (!searching && !isTrash ? 1 : 0),
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
                      highlight: searching
                          ? _searchController.text.trim()
                          : null,
                      selected: dense && note.id == state.openNoteId,
                      dense: dense,
                      onTap: () =>
                          searching ? _openHit(note) : state.openNote(note.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _scopeTitle() => switch (state.scope.kind) {
    NoteScopeKind.all => '全部',
    NoteScopeKind.trash => '回收站',
    NoteScopeKind.notebook => state.notebookName(state.scope.notebookId!),
  };

  Widget _trashCard(Note note) {
    final t = inkOf(context);
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
                Text(
                  noteDisplayTitle(note),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: t.inkMuted),
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
            onPressed: () => state.restoreNote(note.id),
            child: const Text('恢复'),
          ),
          TextButton(
            onPressed: () async {
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
