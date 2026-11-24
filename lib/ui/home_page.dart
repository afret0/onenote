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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _newNotebook() async {
    final name = await promptText(context,
        title: '新建笔记本', label: '名称', hint: '例如：工作随笔');
    if (name != null && name.isNotEmpty) {
      await state.createNotebook(name);
    }
  }

  Future<void> _renameNotebook(Notebook notebook) async {
    final name = await promptText(context,
        title: '重命名笔记本', label: '名称', initial: notebook.name);
    if (name != null && name.isNotEmpty) {
      await state.renameNotebook(notebook.id, name);
    }
  }

  Future<void> _deleteNotebook(Notebook notebook) async {
    final ok = await confirm(context,
        title: '删除笔记本',
        message: '删除「${notebook.name}」？',
        confirmLabel: '删除',
        danger: true);
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

  void _openHit(Note hit) {
    final scope = state.scope;
    if (scope.kind == NoteScopeKind.trash ||
        (scope.kind == NoteScopeKind.notebook &&
            scope.notebookId != hit.notebookId)) {
      state.selectScope(const NoteScope.all());
    }
    state.openNote(hit.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final openId = state.openNoteId;
        final isWide = MediaQuery.sizeOf(context).width >= 900;
        final drawerNeeded = !isWide && openId != null;
        return Scaffold(
          key: _scaffoldKey,
          drawer: isWide
              ? null
              : Drawer(
                  backgroundColor: inkOf(context).surface,
                  child: SafeArea(child: _sidebar(compact: true)),
                ),
          floatingActionButton: openId == null && state.scope.kind != NoteScopeKind.trash
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
                  SizedBox(
                    width: 268,
                    child: _sidebar(compact: false),
                  ),
                if (isWide) const VerticalDivider(width: 1),
                Expanded(
                  child: openId != null
                      ? NoteView(
                          key: ValueKey(openId),
                          state: state,
                          noteId: openId,
                          showBack: drawerNeeded,
                          onBack: state.closeNote,
                        )
                      : _listPane(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sidebar({required bool compact}) {
    final t = inkOf(context);
    final scope = state.scope;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(spaceMd, spaceMd, spaceMd, spaceSm),
          child: Row(
            children: [
              const BrandMark(),
              const SizedBox(width: 10),
              Text('onenote',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(letterSpacing: -0.2)),
              const Spacer(),
              IconButton(
                tooltip: '设置',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(state: state),
                  ),
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
                label: '全部笔记',
                selected: scope.kind == NoteScopeKind.all,
                onTap: () {
                  state.selectScope(const NoteScope.all());
                  if (compact) Navigator.of(context).pop();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(spaceMd, spaceMd, spaceSm, spaceXs),
                child: Row(
                  children: [
                    Text('笔记本',
                        style: Theme.of(context).textTheme.labelSmall),
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
                  selected: scope.kind == NoteScopeKind.notebook &&
                      scope.notebookId == notebook.id,
                  onTap: () {
                    state.selectScope(NoteScope.notebook(notebook.id));
                    if (compact) Navigator.of(context).pop();
                  },
                  trailing: PopupMenuButton<String>(
                    tooltip: '笔记本操作',
                    icon: Icon(Icons.more_horiz, size: 18, color: t.inkFaint),
                    onSelected: (value) {
                      if (value == 'rename') {
                        _renameNotebook(notebook);
                      } else if (value == 'delete') {
                        _deleteNotebook(notebook);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
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

  Widget _listPane() {
    final t = inkOf(context);
    final isTrash = state.scope.kind == NoteScopeKind.trash;
    final searching = _searchHits != null;
    final list = searching ? _searchHits! : state.notes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(spaceMd, spaceMd, spaceMd, spaceSm),
          child: Row(
            children: [
              if (MediaQuery.sizeOf(context).width < 900)
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
          padding: const EdgeInsets.fromLTRB(spaceLg, spaceXs, spaceMd, spaceSm),
          child: Row(
            children: [
              Text(
                searching ? '搜索结果' : _scopeTitle(),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(letterSpacing: -0.3),
              ),
              const SizedBox(width: spaceSm),
              Text('${list.length}',
                  style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              if (!searching && !isTrash)
                FilledButton.icon(
                  onPressed: _newNote,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('笔记'),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  searching: searching, isTrash: isTrash, onNew: _newNote)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(spaceMd, 0, spaceMd, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: spaceSm),
                  itemBuilder: (context, index) {
                    final note = list[index];
                    if (isTrash) {
                      return _trashCard(note);
                    }
                    return NoteCard(
                      note: note,
                      notebookName: state.notebookName(note.notebookId),
                      notebookColor: Color(state.notebookColor(note.notebookId)),
                      highlight: searching ? _searchController.text.trim() : null,
                      onTap: () => searching ? _openHit(note) : state.openNote(note.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _scopeTitle() => switch (state.scope.kind) {
        NoteScopeKind.all => '全部笔记',
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
                Text(noteDisplayTitle(note),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: t.inkMuted)),
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
              final ok = await confirm(context,
                  title: '彻底删除',
                  message: '「${noteDisplayTitle(note)}」及其全部版本将被删除，不可恢复。',
                  confirmLabel: '彻底删除',
                  danger: true);
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