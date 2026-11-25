import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart'
    show MarkdownHighlightController;
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';

import '../data/app_db.dart';
import '../data/attachment_store.dart';
import '../data/markdown_tasks.dart';
import '../state/app_state.dart';
import 'dialogs.dart';
import 'markdown_view.dart';
import 'theme.dart';
import 'widgets.dart';

const _noteColumnWidth = 760.0;
const _navPosSettingKey = 'searchNavPos';

class NoteView extends StatefulWidget {
  const NoteView({
    super.key,
    required this.state,
    required this.noteId,
    required this.showBack,
    required this.onBack,
    this.highlightQuery,
  });

  final AppState state;
  final String noteId;
  final bool showBack;
  final VoidCallback onBack;
  final String? highlightQuery;

  @override
  State<NoteView> createState() => _NoteViewState();
}

class _NoteViewState extends State<NoteView> {
  Note? _note;
  bool _editing = false;
  bool _dirty = false;
  String _saveStatus = '';
  Timer? _autosave;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final ScrollController _renderScroll = ScrollController();
  final ScrollController _editScroll = ScrollController();
  bool _showScrollTop = false;
  final MarkdownHighlightController _highlight = MarkdownHighlightController();
  final GlobalKey _renderViewportKey = GlobalKey();
  final GlobalKey _navKey = GlobalKey();
  Size _navSize = const Size(200, 52);
  Offset? _navPos;
  int _matchIndex = 0;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _renderScroll.addListener(_onRenderScroll);
    _highlight.addListener(_onHighlightChanged);
    state.addListener(_reloadIfIdle);
    _load();
    _loadNavPos();
  }

  Future<void> _loadNavPos() async {
    final raw = await state.db.getSetting(_navPosSettingKey);
    if (!mounted || raw == null) {
      return;
    }
    final parts = raw.split(',');
    if (parts.length != 2) {
      return;
    }
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    if (x == null || y == null) {
      return;
    }
    setState(() => _navPos = Offset(x, y));
  }

  Offset _defaultNavPos(Size area, Size bar) => Offset(
        math.max(0.0, area.width - bar.width - spaceSm),
        math.max(0.0, area.height - bar.height - spaceLg - 52),
      );

  Offset _clampNav(Offset pos, Size area, Size bar) {
    final maxX = math.max(0.0, area.width - bar.width - spaceSm);
    final maxY = math.max(0.0, area.height - bar.height - spaceSm);
    return Offset(pos.dx.clamp(0.0, maxX), pos.dy.clamp(0.0, maxY));
  }

  void _dragNav(Offset delta) {
    final bar = _navKey.currentContext?.findRenderObject() as RenderBox?;
    final area =
        _renderViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (bar == null || area == null) {
      return;
    }
    final base = _navPos ?? _defaultNavPos(area.size, bar.size);
    setState(() {
      _navPos = _clampNav(base + delta, area.size, bar.size);
    });
  }

  Future<void> _saveNavPos() async {
    final pos = _navPos;
    if (pos == null) {
      return;
    }
    await state.db
        .setSetting(_navPosSettingKey, '${pos.dx.round()},${pos.dy.round()}');
  }

  void _onHighlightChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        final count = _highlight.matches.length;
        _matchIndex = count == 0 ? 0 : _matchIndex.clamp(0, count - 1);
      });
    });
  }

  Future<void> _load() async {
    final note = await state.db.getNote(widget.noteId);
    if (!mounted) {
      return;
    }
    setState(() {
      _note = note;
      _titleController.text = note.title;
      _contentController.text = note.content;
    });
    _scheduleFirstMatch();
  }

  @override
  void didUpdateWidget(covariant NoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId ||
        oldWidget.highlightQuery != widget.highlightQuery) {
      _matchIndex = 0;
      _scheduleFirstMatch();
    }
  }

  void _scheduleFirstMatch() {
    if ((widget.highlightQuery ?? '').isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editing || _highlight.matches.isEmpty) {
        return;
      }
      _jumpToMatch(0);
    });
  }

  void _jumpToMatch(int index) {
    final count = _highlight.matches.length;
    if (count == 0) {
      return;
    }
    final i = index.clamp(0, count - 1);
    setState(() => _matchIndex = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_renderScroll.hasClients) {
        return;
      }
      final viewport =
          _renderViewportKey.currentContext?.findRenderObject() as RenderBox?;
      final global = _highlight.globalOffset(i);
      if (viewport == null || global == null) {
        return;
      }
      final top = viewport.localToGlobal(Offset.zero).dy;
      final target = (_renderScroll.position.pixels + global.dy - top - 96)
          .clamp(0.0, _renderScroll.position.maxScrollExtent);
      _renderScroll.animateTo(target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _autosave?.cancel();
    state.removeListener(_reloadIfIdle);
    _titleController.dispose();
    _contentController.dispose();
    _renderScroll.dispose();
    _editScroll.dispose();
    _highlight.removeListener(_onHighlightChanged);
    super.dispose();
  }

  void _reloadIfIdle() {
    if (_editing || _dirty || _note == null) {
      return;
    }
    _load();
  }

  void _enterEdit() {
    final fraction = _renderScroll.hasClients &&
            _renderScroll.position.maxScrollExtent > 0
        ? (_renderScroll.position.pixels /
                _renderScroll.position.maxScrollExtent)
            .clamp(0.0, 1.0)
        : 0.0;
    final text = _contentController.text;
    _contentController.selection = TextSelection.collapsed(
        offset: (fraction * text.length).round().clamp(0, text.length));
    setState(() {
      _editing = true;
      _dirty = false;
      _saveStatus = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing || !_editScroll.hasClients) {
        return;
      }
      _editScroll.jumpTo(fraction * _editScroll.position.maxScrollExtent);
    });
  }

  void _onRenderScroll() {
    final show = _renderScroll.hasClients && _renderScroll.position.pixels > 0;
    if (show != _showScrollTop) {
      setState(() => _showScrollTop = show);
    }
  }

  void _scrollToTop() {
    if (!_renderScroll.hasClients) {
      return;
    }
    _renderScroll.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _changed() {
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 800), () => _save(silent: true));
    setState(() => _saveStatus = '未保存');
  }

  Future<void> _save({bool silent = false}) async {
    _autosave?.cancel();
    final note = _note;
    if (note == null || !_dirty) {
      return;
    }
    final title = _titleController.text;
    final content = _contentController.text;
    final changed = await state.db.saveNote(note.id, title, content);
    await state.refresh();
    if (!mounted) {
      return;
    }
    final fresh = await state.db.getNote(note.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _note = fresh;
      _dirty = false;
      _saveStatus = changed
          ? '已保存 ${formatHm(fresh.updateAt)}'
          : '无变更';
    });
    if (!silent && !changed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('内容没有变化')));
    }
  }

  Future<void> _exitEdit() async {
    await _save(silent: true);
    if (!mounted) {
      return;
    }
    setState(() => _editing = false);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleTask(int ordinal) {
    final note = _note;
    if (note == null) {
      return;
    }
    final content = _contentController.text;
    final position = markdownTaskMarkerPosition(content, ordinal);
    if (position == null) {
      return;
    }
    final updated = toggleMarkdownTaskAt(content, position);
    setState(() {
      _note = note.copyWith(content: updated);
      _contentController.text = updated;
    });
    _changed();
  }

  void _insertText(String text) {
    final value = _contentController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _contentController.value = TextEditingValue(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _changed();
  }

  Future<void> _saveAttachment(Uint8List bytes, String name,
      {required bool asImage}) async {
    final store = state.attachments;
    if (store == null) {
      _snack('Web 端附件将随同步阶段支持');
      return;
    }
    try {
      final id = await store.save(bytes, name);
      if (!mounted) {
        return;
      }
      _insertText(asImage
          ? AttachmentStore.imageMarkdown(id, name)
          : AttachmentStore.fileMarkdown(id, name));
    } on AttachmentTooLargeException {
      _snack('文件超过 20MB 上限');
    }
  }

  Future<void> _pickFiles({required bool image}) async {
    final result = await FilePicker.platform.pickFiles(
      type: image ? FileType.image : FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) {
      return;
    }
    for (final file in result.files) {
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) {
        continue;
      }
      final isImage =
          image || (lookupMimeType(file.name) ?? '').startsWith('image/');
      await _saveAttachment(bytes, file.name, asImage: isImage);
    }
  }

  Future<void> _handlePaste() async {
    final store = state.attachments;
    if (store != null) {
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) {
        await _saveAttachment(
            bytes, 'pasted_${DateTime.now().millisecondsSinceEpoch}.png',
            asImage: true);
        return;
      }
    }
    final text = await Pasteboard.text;
    if (text != null && text.isNotEmpty) {
      _insertText(text);
    }
  }

  Future<void> _onDrop(DropDetails details) async {
    for (final item in details.items) {
      if (item is DropFileItem) {
        final bytes = await item.file.readAsBytes();
        await _saveAttachment(bytes, item.name,
            asImage: (item.mimeType ?? '').startsWith('image/'));
      }
    }
  }

  Future<void> _openAttachment(String id) async {
    final store = state.attachments;
    if (store == null) {
      return;
    }
    final bytes = await store.read(id);
    if (bytes == null) {
      _snack('附件文件不存在');
      return;
    }
    final name = (await store.nameOf(id) ?? id).replaceAll(RegExp(r'[/\\]'), '_');
    final dir = await Directory.systemTemp.createTemp('onenote_open');
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    if (Platform.isMacOS) {
      await Process.run('open', [file.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', file.path]);
    }
  }

  Widget _editorArea() {
    final t = inkOf(context);
    final editor = Container(
      color: t.paper,
      padding: const EdgeInsets.symmetric(horizontal: spaceSm),
      child: TextField(
        controller: _contentController,
        scrollController: _editScroll,
        onChanged: (_) => _changed(),
        autofocus: true,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontFamily: t.sans,
          fontFamilyFallback: cjkSansFallback,
          fontSize: t.noteFontSize * t.fontScale,
          height: 1.75,
          color: t.ink,
        ),
        decoration: const InputDecoration(
          hintText: '用 Markdown 书写…',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.all(spaceMd),
        ),
      ),
    );
    final area = Column(
      children: [
        Container(
          color: t.paper,
          padding:
              const EdgeInsets.fromLTRB(spaceLg, spaceLg, spaceLg, spaceLg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _noteColumnWidth),
              child: _metaRow(
                _note!,
                Padding(
                  padding: const EdgeInsets.only(right: spaceXs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _pickFiles(image: true),
                        icon: const Icon(Icons.image_outlined),
                      ),
                      IconButton(
                        onPressed: () => _pickFiles(image: false),
                        icon: const Icon(Icons.attach_file),
                      ),
                      FilledButton.icon(
                        onPressed: _exitEdit,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('完成'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: editor),
      ],
    );
    if (kIsWeb) {
      return area;
    }
    return DropTarget(
      onDrop: _onDrop,
      acceptedKinds: const {DropItemKind.file},
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
            _handlePaste();
          },
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
            _handlePaste();
          },
        },
        child: area,
      ),
    );
  }

  Future<void> _showHistory() async {
    final note = _note;
    if (note == null) {
      return;
    }
    await showNoteHistory(
      context,
      state: state,
      noteId: note.id,
      onRestored: () async {
        setState(() => _editing = false);
        await _load();
      },
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _trash() async {
    final note = _note;
    if (note == null) {
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final note = _note;
    if (note == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline)),
          ),
          padding: const EdgeInsets.fromLTRB(spaceSm, spaceSm, spaceMd, spaceSm),
          child: Row(
            children: [
              if (widget.showBack)
                IconButton(
                  onPressed: () async {
                    await _save(silent: true);
                    widget.onBack();
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: _editing
                    ? TextField(
                        controller: _titleController,
                        onChanged: (_) => _changed(),
                        style: _titleStyle(context),
                        decoration: const InputDecoration(
                          hintText: '标题',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: spaceSm, vertical: spaceSm),
                        ),
                      )
                    : GestureDetector(
                        onSecondaryTapUp: (d) =>
                            _showNoteMenu(d.globalPosition),
                        onLongPressStart: (d) =>
                            _showNoteMenu(d.globalPosition),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: spaceSm),
                          child: HighlightText(
                            text: noteDisplayTitle(note),
                            needle: _editing ? null : widget.highlightQuery,
                            maxLines: 1,
                            style: _titleStyle(context),
                          ),
                        ),
                      ),
              ),
              if (_editing && _saveStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: spaceSm),
                  child: Text(_saveStatus,
                      style: Theme.of(context).textTheme.labelSmall),
                ),
            ],
          ),
        ),
        Expanded(
          child: _editing
              ? _editorArea()
              : Stack(
                  key: _renderViewportKey,
                  fit: StackFit.expand,
                  children: [
                    SingleChildScrollView(
                      key:
                          PageStorageKey<String>('noteScroll:${widget.noteId}'),
                      controller: _renderScroll,
                      padding: const EdgeInsets.fromLTRB(
                          spaceLg, spaceLg, spaceLg, spaceXxl),
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: _noteColumnWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: spaceLg),
                                child: _metaRow(note),
                              ),
                              MarkdownView(
                                content: note.content,
                                attachments: state.attachments,
                                onAttachmentLink: _openAttachment,
                                onToggleTask: _toggleTask,
                                highlightQuery: widget.highlightQuery,
                                highlightActiveIndex: _matchIndex,
                                highlightController: _highlight,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: _readingColumnOverlay(
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: spaceLg),
                            child: _editButton(t),
                          ),
                        ),
                      ),
                    ),
                    if (_showScrollTop)
                      Positioned.fill(
                        child: _readingColumnOverlay(
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  right: spaceXs, bottom: spaceLg),
                              child: _scrollTopButton(t),
                            ),
                          ),
                        ),
                      ),
                    if (!_editing && _highlight.matches.isNotEmpty)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final area = constraints.biggest;
                            final bar = _navSize;
                            final pos = _clampNav(
                                _navPos ?? _defaultNavPos(area, bar), area, bar);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) {
                                return;
                              }
                              final size = _navKey.currentContext?.size;
                              if (size != null && size != _navSize) {
                                setState(() => _navSize = size);
                              }
                            });
                            return Stack(
                              children: [
                                Positioned(
                                  left: pos.dx,
                                  top: pos.dy,
                                  child: _matchNav(t),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _editButton(InkTokens t) {
    return Padding(
      padding: const EdgeInsets.only(right: spaceXs),
      child: SizedBox(
        height: 40,
        width: 48,
        child: OutlinedButton(
          onPressed: _enterEdit,
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            mouseCursor: const WidgetStatePropertyAll(
              SystemMouseCursors.click,
            ),
            backgroundColor: WidgetStatePropertyAll(t.paper),
            foregroundColor: WidgetStatePropertyAll(t.accentText),
            overlayColor: WidgetStatePropertyAll(t.accentSoft),
            side: WidgetStatePropertyAll(
              BorderSide(color: t.hairline),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radiusMd),
              ),
            ),
          ),
          child: const Icon(Icons.edit_outlined, size: 18),
        ),
      ),
    );
  }

  Widget _metaRow(Note note, [Widget? trailing]) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: Color(state.notebookColor(note.notebookId)),
              shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(state.notebookName(note.notebookId),
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: spaceMd),
        Text(formatDateTime(note.updateAt),
            style: Theme.of(context).textTheme.labelSmall),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  Widget _readingColumnOverlay(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: spaceLg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _noteColumnWidth),
          child: child,
        ),
      ),
    );
  }

  Future<void> _showNoteMenu(Offset pos) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'history', child: Text('版本历史')),
        PopupMenuItem(value: 'trash', child: Text('移入回收站')),
      ],
    );
    if (!mounted) {
      return;
    }
    if (value == 'history') {
      _showHistory();
    } else if (value == 'trash') {
      _trash();
    }
  }

  Widget _matchNav(InkTokens t) {
    final count = _highlight.matches.length;
    return MouseRegion(
      key: _navKey,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onPanUpdate: (d) => _dragNav(d.delta),
        onPanEnd: (_) => _saveNavPos(),
        child: Material(
          key: const ValueKey('matchNav'),
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(radiusMd),
          elevation: 4,
          shadowColor: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: spaceSm, vertical: spaceXs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.only(left: spaceXs, right: spaceSm),
                  child: Icon(Icons.drag_indicator, size: 16, color: t.inkMuted),
                ),
                Text('${_matchIndex + 1}/$count',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: t.ink,
                          fontSize: 14 * t.fontScale,
                          fontWeight: FontWeight.w600,
                        )),
                const SizedBox(width: spaceSm),
                Semantics(
                  button: true,
                  label: '上一个命中',
                  child: IconButton(
                    onPressed: _matchIndex > 0
                        ? () => _jumpToMatch(_matchIndex - 1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  ),
                ),
                Semantics(
                  button: true,
                  label: '下一个命中',
                  child: IconButton(
                    onPressed: _matchIndex < count - 1
                        ? () => _jumpToMatch(_matchIndex + 1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrollTopButton(InkTokens t) {
    return Semantics(
      button: true,
      label: '回到顶部',
      child: Material(
        color: t.surfaceAlt,
        shape: CircleBorder(side: BorderSide(color: t.hairline)),
        elevation: 4,
        shadowColor: Colors.black54,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _scrollToTop,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.keyboard_arrow_up, color: t.inkMuted),
          ),
        ),
      ),
    );
  }

  TextStyle? _titleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge?.copyWith(
            fontFamily: serifFamily,
            fontFamilyFallback: cjkSerifFallback,
            fontSize: 22 * inkOf(context).fontScale,
          );
}

String formatHm(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}';
}

Future<void> showNoteHistory(
  BuildContext context, {
  required AppState state,
  required String noteId,
  Future<void> Function()? onRestored,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: inkOf(context).surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _HistorySheet(
      state: state,
      noteId: noteId,
      onRestored: () async {
        Navigator.of(sheetContext).pop();
        await onRestored?.call();
      },
    ),
  );
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({
    required this.state,
    required this.noteId,
    required this.onRestored,
  });

  final AppState state;
  final String noteId;
  final Future<void> Function() onRestored;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<NoteVersion>? _versions;

  @override
  void initState() {
    super.initState();
    widget.state.db.listVersions(widget.noteId).then((v) {
      if (mounted) {
        setState(() => _versions = v);
      }
    });
  }

  Future<void> _restore(NoteVersion version) async {
    final ok = await confirm(context,
        title: '恢复此版本',
        message: '当前内容会先自动存为一个新版本，然后恢复 ${formatDateTime(version.createAt)} 的内容。',
        confirmLabel: '恢复');
    if (!ok) {
      return;
    }
    final changed =
        await widget.state.db.restoreVersion(widget.noteId, version.id);
    await widget.state.refresh();
    if (!mounted) {
      return;
    }
    if (!changed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('与当前内容一致，无需恢复')));
      return;
    }
    await widget.onRestored();
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final versions = _versions;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => versions == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(spaceLg, 0, spaceLg, spaceSm),
                  child: Row(
                    children: [
                      Text('版本历史',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: spaceSm),
                      Text('${versions.length}',
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(
                        spaceMd, spaceSm, spaceMd, spaceLg),
                    itemCount: versions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: spaceSm),
                    itemBuilder: (context, index) {
                      final version = versions[index];
                      final preview = notePreview(version.content);
                      return Container(
                        decoration: BoxDecoration(
                          color: index == 0 ? t.accentSoft : t.paper,
                          borderRadius: BorderRadius.circular(radiusMd),
                          border: Border.all(
                              color: index == 0 ? t.accent : t.hairline,
                              width: index == 0 ? 1.2 : 1),
                        ),
                        padding: const EdgeInsets.all(spaceMd),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(formatDateTime(version.createAt),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: t.ink)),
                                      if (index == 0) ...[
                                        const SizedBox(width: spaceSm),
                                        Text('当前',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(color: t.accentText)),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: spaceXs),
                                  Text(
                                    version.title.trim().isEmpty
                                        ? '无标题'
                                        : version.title.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  if (preview.isNotEmpty)
                                    Text(
                                      preview,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: t.inkMuted),
                                    ),
                                ],
                              ),
                            ),
                            if (index != 0)
                              TextButton(
                                onPressed: () => _restore(version),
                                child: const Text('恢复'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}