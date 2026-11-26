import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart'
    show MarkdownHighlightController, MarkdownTocController, MarkdownTocEntry;
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';

import '../data/app_db.dart';
import '../data/attachment_refs.dart';
import '../data/attachment_store.dart';
import '../data/markdown_tasks.dart';
import '../state/app_state.dart';
import '../window_setup.dart';
import 'attachment_viewer.dart';
import 'conflict_panel.dart';
import 'dialogs.dart';
import 'markdown_view.dart';
import 'note_toc.dart';
import 'password_prompts.dart';
import 'richtext_note_view.dart';
import 'theme.dart';
import 'widgets.dart';

const _noteColumnWidth = 684.0;
const _tocColumnMinWidth = 600.0;
const _navPosSettingKey = 'searchNavPos';
const _tocVisibleSettingKey = 'tocVisible';

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
  State<NoteView> createState() => NoteViewState();
}

class NoteViewState extends State<NoteView> {
  Note? _note;
  bool _editing = false;
  bool _dirty = false;
  String _saveStatus = '';
  Timer? _autosave;
  int _lastLeaseTouch = 0;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final ScrollController _renderScroll = ScrollController();
  final ScrollController _editScroll = ScrollController();
  bool _showScrollTop = false;
  final MarkdownHighlightController _highlight = MarkdownHighlightController();
  bool _pendingFirstMatch = false;
  int _editorButtons = 0;
  final MarkdownTocController _toc = MarkdownTocController();
  bool _tocVisible = true;
  int _tocActive = -1;
  final GlobalKey _renderViewportKey = GlobalKey();
  final GlobalKey _navAreaKey = GlobalKey();
  final GlobalKey _navKey = GlobalKey();
  Size _navSize = const Size(200, 52);
  Offset? _navPos;
  int _matchIndex = 0;
  int _matchCount = 0;
  bool _replaceOpen = false;
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  final FocusNode _contentFocus = FocusNode();
  final GlobalKey _editorFieldKey = GlobalKey();
  final GlobalKey<RichTextNoteViewState> _richtextKey = GlobalKey();
  List<int> _findMatches = [];
  int _findIndex = 0;

  AppState get state => widget.state;

  Future<void> flushEdits() {
    if (_note?.format == AppDb.noteFormatRichtext) {
      return _richtextKey.currentState?.flushEdits() ?? Future.value();
    }
    return _save(silent: true);
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _renderScroll.addListener(_onRenderScroll);
    _highlight.addListener(_onHighlightChanged);
    _toc.addListener(_onTocChanged);
    state.addListener(_reloadIfIdle);
    _load();
    _loadNavPos();
    _loadTocVisible();
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
        _navAreaKey.currentContext?.findRenderObject() as RenderBox?;
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
      final count = _highlight.matches.length;
      if (_pendingFirstMatch && count > 0 && !_editing) {
        _pendingFirstMatch = false;
        setState(() {
          _matchCount = count;
          _matchIndex = 0;
        });
        _jumpToMatch(0);
        return;
      }
      final next = count == 0 ? 0 : _matchIndex.clamp(0, count - 1);
      if (count == _matchCount && next == _matchIndex) {
        return;
      }
      setState(() {
        _matchCount = count;
        _matchIndex = next;
      });
    });
  }

  Future<void> _load({bool jumpToFirstMatch = true}) async {
    final note = await state.db.getNote(widget.noteId);
    if (!mounted) {
      return;
    }
    setState(() {
      _note = note;
      _titleController.text = note.title;
      _contentController.text = note.content;
    });
    if (jumpToFirstMatch) {
      _scheduleFirstMatch();
    }
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
      _pendingFirstMatch = false;
      return;
    }
    _pendingFirstMatch = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editing || _highlight.matches.isEmpty) {
        return;
      }
      _pendingFirstMatch = false;
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
    _findController.dispose();
    _replaceController.dispose();
    _findFocus.dispose();
    _contentFocus.dispose();
    _renderScroll.dispose();
    _editScroll.dispose();
    _highlight.removeListener(_onHighlightChanged);
    _toc.removeListener(_onTocChanged);
    _toc.dispose();
    super.dispose();
  }

  void _reloadIfIdle() {
    if (_editing || _dirty || _note == null) {
      return;
    }
    _reloadNote();
  }

  Future<void> _reloadNote() async {
    final fresh = await state.db.getNote(widget.noteId);
    if (!mounted) {
      return;
    }
    final current = _note;
    if (current != null &&
        current.title == fresh.title &&
        current.content == fresh.content &&
        current.updateAt == fresh.updateAt &&
        current.notebookId == fresh.notebookId) {
      return;
    }
    setState(() {
      _note = fresh;
      _titleController.text = fresh.title;
      _contentController.text = fresh.content;
    });
  }

  Future<void> _enterEdit() async {
    final outcome = await state.syncNow('edit');
    if (outcome.error != null) {
      developer.log(
          'skip, 编辑前同步失败放行离线编辑, noteId: ${widget.noteId}, err: ${outcome.error}');
    }
    if (!mounted) {
      return;
    }
    if (state.sync.conflictIds.contains(widget.noteId)) {
      developer.log(
          'hit, 笔记存在未裁决冲突先打开裁决面板, noteId: ${widget.noteId}');
      await showConflictPanel(context, state: state, noteId: widget.noteId);
      if (!mounted) {
        return;
      }
    }
    await _load();
    if (!mounted) {
      return;
    }
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
      if (!mounted || !_editing) {
        return;
      }
      _contentFocus.requestFocus();
      if (!_editScroll.hasClients) {
        return;
      }
      _editScroll.jumpTo(fraction * _editScroll.position.maxScrollExtent);
    });
  }

  void _onRenderScroll() {
    _touchLease();
    final show = _renderScroll.hasClients && _renderScroll.position.pixels > 0;
    final previousActive = _tocActive;
    _updateTocActive();
    if (show != _showScrollTop || _tocActive != previousActive) {
      setState(() => _showScrollTop = show);
    }
  }

  List<MarkdownTocEntry> _tocEntries() => noteTocVisibleEntries(_toc.entries);

  Future<void> _loadTocVisible() async {
    final raw = await state.db.getSetting(_tocVisibleSettingKey);
    if (!mounted || raw == null) {
      return;
    }
    setState(() => _tocVisible = raw != '0');
  }

  Future<void> _toggleTocVisible() async {
    setState(() {
      _tocVisible = !_tocVisible;
      _updateTocActive();
    });
    await state.db.setSetting(_tocVisibleSettingKey, _tocVisible ? '1' : '0');
  }

  void _onTocChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(_updateTocActive);
    });
  }

  void _updateTocActive() {
    var active = -1;
    if (!_editing && _tocVisible && _renderScroll.hasClients) {
      final viewport =
          _renderViewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (viewport != null && viewport.hasSize) {
        final top = viewport.localToGlobal(Offset.zero).dy;
        final entries = _tocEntries();
        for (var i = 0; i < entries.length; i++) {
          final box =
              entries[i].key.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) {
            continue;
          }
          if (box.localToGlobal(Offset.zero).dy - top <=
              noteTocRevealOffset + 1) {
            active = i;
          }
        }
      }
    }
    _tocActive = active;
  }

  void _jumpToTocEntry(MarkdownTocEntry entry) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_renderScroll.hasClients) {
        return;
      }
      final viewport =
          _renderViewportKey.currentContext?.findRenderObject() as RenderBox?;
      final box = entry.key.currentContext?.findRenderObject() as RenderBox?;
      if (viewport == null || box == null) {
        return;
      }
      final top = viewport.localToGlobal(Offset.zero).dy;
      final target = (_renderScroll.position.pixels +
              box.localToGlobal(Offset.zero).dy -
              top -
              noteTocRevealOffset)
          .clamp(0.0, _renderScroll.position.maxScrollExtent);
      _renderScroll.animateTo(target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    });
  }

  void _openTocSheet() {
    final note = _note;
    final entries = _tocEntries();
    if (note == null || entries.isEmpty) {
      return;
    }
    showNoteTocSheet(context,
        entries: entries,
        activeIndex: _tocActive,
        tint: Color(state.notebookColor(note.notebookId)),
        onSelect: _jumpToTocEntry);
  }

  void _scrollToTop() {
    if (!_renderScroll.hasClients) {
      return;
    }
    _renderScroll.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _touchLease() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLeaseTouch < 15000) {
      return;
    }
    _lastLeaseTouch = now;
    state.touchNote(widget.noteId);
  }

  void _changed() {
    _touchLease();
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 800), () => _save(silent: true));
    setState(() => _saveStatus = '未保存');
    if (_replaceOpen) {
      _refreshFindMatches(null);
    }
  }

  Future<void> _save({bool silent = false}) async {
    _autosave?.cancel();
    final note = _note;
    if (note == null || !_dirty) {
      return;
    }
    final title = _titleController.text;
    final content = _contentController.text;
    final changed = await state.saveNote(note.id, title, content);
    if (!mounted) {
      return;
    }
    final fresh = await state.db.findNote(note.id);
    if (!mounted || fresh == null) {
      return;
    }
    final typedDuringSave = _dirty;
    setState(() {
      _note = fresh;
      _saveStatus = changed
          ? '已保存 ${formatHm(fresh.updateAt)}'
          : '无变更';
      if (typedDuringSave) {
        return;
      }
      _dirty = false;
      if (_contentController.text != fresh.content) {
        _contentController.text = fresh.content;
        developer.log(
            'hit, 保存后内容与编辑器不同已回填合并结果, noteId: ${fresh.id}');
      }
      if (_titleController.text != fresh.title) {
        _titleController.text = fresh.title;
      }
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
    setState(() {
      _editing = false;
      _replaceOpen = false;
    });
  }

  void _openReplace() {
    if (!_editing) {
      developer.log('skip, 非编辑态忽略替换快捷键, noteId: ${widget.noteId}');
      return;
    }
    setState(() {
      _replaceOpen = true;
      _refreshFindMatches(null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _replaceOpen) {
        _findFocus.requestFocus();
      }
    });
  }

  void _closeReplace() {
    setState(() => _replaceOpen = false);
    _contentFocus.requestFocus();
  }

  void _refreshFindMatches(int? preferred) {
    final needle = _findController.text;
    final content = _contentController.text;
    final matches = <int>[];
    if (needle.isNotEmpty) {
      var start = content.indexOf(needle);
      while (start >= 0) {
        matches.add(start);
        start = content.indexOf(needle, start + needle.length);
      }
    }
    _findMatches = matches;
    if (matches.isEmpty) {
      _findIndex = 0;
      return;
    }
    final target = preferred ?? _findMatches[_findIndex.clamp(0, matches.length - 1)];
    var best = 0;
    for (var i = 0; i < matches.length; i++) {
      if (matches[i] <= target) {
        best = i;
      }
    }
    _findIndex = best;
  }

  void _selectFindMatch() {
    if (_findMatches.isEmpty) {
      return;
    }
    final start = _findMatches[_findIndex];
    final end = start + _findController.text.length;
    _contentController.selection =
        TextSelection(baseOffset: start, extentOffset: end);
    if (!_editScroll.hasClients) {
      return;
    }
    final box =
        _editorFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: _contentController.text.substring(0, start),
        style: _editorTextStyle(inkOf(context)),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1.0, box.size.width - spaceMd * 2));
    final viewport = _editScroll.position.viewportDimension;
    final target = (painter.height - viewport * 0.4)
        .clamp(0.0, _editScroll.position.maxScrollExtent);
    painter.dispose();
    _editScroll.animateTo(target,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  void _stepFindMatch(int delta) {
    final count = _findMatches.length;
    if (count == 0) {
      return;
    }
    setState(() => _findIndex = (_findIndex + delta + count) % count);
    _selectFindMatch();
  }

  void _replaceCurrent() {
    if (_findMatches.isEmpty) {
      return;
    }
    final needle = _findController.text;
    final replacement = _replaceController.text;
    final start = _findMatches[_findIndex];
    final text = _contentController.text;
    _contentController.value = TextEditingValue(
      text: text.replaceRange(start, start + needle.length, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _changed();
    _refreshFindMatches(start);
    developer.log(
        'done, 替换一处, noteId: ${widget.noteId}, offset: $start, 剩余: ${_findMatches.length}');
    setState(() {});
    if (_findMatches.isNotEmpty) {
      _selectFindMatch();
    }
  }

  void _replaceAll() {
    final needle = _findController.text;
    if (needle.isEmpty || _findMatches.isEmpty) {
      return;
    }
    final replaced = _findMatches.length;
    _contentController.value = TextEditingValue(
      text: _contentController.text.replaceAll(needle, _replaceController.text),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _changed();
    _refreshFindMatches(0);
    setState(() {});
    developer.log('done, 全部替换, noteId: ${widget.noteId}, replaced: $replaced');
    _snack('已替换 $replaced 处');
  }

  Widget _replacePanel(InkTokens t) {
    final count = _findMatches.length;
    final tint = Color(state.notebookColor(_note!.notebookId));
    final inkAlt = readableOn(tint, t.surfaceAlt);
    final selAlt =
        readableOn(tint, t.surfaceAlt, ratio: 3).withValues(alpha: 0.4);
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: BorderSide(color: inkAlt, width: 1.5),
    );
    final linkStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? t.ink.withValues(alpha: 0.38)
              : inkAlt),
    );
    final panel = Container(
      key: const ValueKey('replacePanel'),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(spaceMd, spaceSm, spaceMd, spaceSm),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findController,
                  focusNode: _findFocus,
                  onChanged: (_) {
                    setState(() => _refreshFindMatches(null));
                    _selectFindMatch();
                  },
                  decoration: InputDecoration(
                    hintText: '查找（区分大小写）',
                    isDense: true,
                    focusedBorder: focusedBorder,
                  ),
                ),
              ),
              const SizedBox(width: spaceSm),
              Text('${count == 0 ? 0 : _findIndex + 1}/$count',
                  style: Theme.of(context).textTheme.labelMedium),
              IconButton(
                tooltip: '上一处',
                onPressed: count == 0 ? null : () => _stepFindMatch(-1),
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              ),
              IconButton(
                tooltip: '下一处',
                onPressed: count == 0 ? null : () => _stepFindMatch(1),
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: _closeReplace,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: spaceSm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replaceController,
                  decoration: InputDecoration(
                    hintText: '替换为',
                    isDense: true,
                    focusedBorder: focusedBorder,
                  ),
                ),
              ),
              const SizedBox(width: spaceSm),
              TextButton(
                onPressed: count == 0 ? null : _replaceCurrent,
                style: linkStyle,
                child: const Text('替换'),
              ),
              TextButton(
                onPressed: count == 0 ? null : _replaceAll,
                style: linkStyle,
                child: const Text('全部替换'),
              ),
            ],
          ),
        ],
      ),
    );
    return TextSelectionTheme(
      data: TextSelectionThemeData(cursorColor: inkAlt, selectionColor: selAlt),
      child: panel,
    );
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

  void _onEditorPointerUp(PointerUpEvent e) {
    final buttons = _editorButtons;
    _editorButtons = 0;
    if (buttons != kPrimaryButton) {
      return;
    }
    final pressed = Platform.isMacOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (!pressed) {
      return;
    }
    final root = _editorFieldKey.currentContext?.findRenderObject();
    RenderEditable? editable;
    void visit(RenderObject node) {
      if (editable != null) {
        return;
      }
      if (node is RenderEditable) {
        editable = node;
        return;
      }
      node.visitChildren(visit);
    }

    if (root != null) {
      visit(root);
    }
    final ed = editable;
    if (ed == null) {
      return;
    }
    final offset = ed.getPositionForPoint(e.position).offset;
    final href = _hrefAtOffset(_contentController.text, offset);
    if (href == null) {
      return;
    }
    final match = AttachmentStore.refPattern.firstMatch(href);
    if (match != null) {
      _openAttachment(match.group(1)!);
      return;
    }
    _launchHref(href);
  }

  String? _hrefAtOffset(String text, int offset) {
    for (final m in RegExp(r'\[[^\]]*\]\(([^)\s]+)\)').allMatches(text)) {
      if (offset >= m.start && offset <= m.end) {
        return m.group(1);
      }
    }
    for (final m in RegExp(r'https?://[^\s)\]]+').allMatches(text)) {
      if (offset >= m.start && offset <= m.end) {
        return m.group(0);
      }
    }
    return null;
  }

  void _launchHref(String href) {
    if (kIsWeb) {
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    if (Platform.isMacOS) {
      Process.run('open', [href]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [href]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', href]);
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
    final name = await store.nameOf(id) ?? id;
    if (!mounted) {
      return;
    }
    await _openExternally(bytes, name);
  }

  Future<void> _openPdfViewer(String id, int ordinal) async {
    final store = state.attachments;
    if (store == null) {
      return;
    }
    final bytes = await store.read(id);
    if (bytes == null) {
      _snack('附件文件不存在');
      return;
    }
    final name = await store.nameOf(id) ?? id;
    if (!mounted) {
      return;
    }
    await showPdfViewer(
      context,
      bytes: bytes,
      name: name,
      onAction: (action) => _attachmentAction(action, id, ordinal),
      onOpenExternal: () => _openExternally(bytes, name),
    );
  }

  Future<void> _openExternally(Uint8List bytes, String name) async {
    final safeName = name.replaceAll(RegExp(r'[/\\]'), '_');
    final dir = await Directory.systemTemp.createTemp('onenote_open');
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes);
    if (Platform.isMacOS) {
      await Process.run('open', [file.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', file.path]);
    }
  }

  Future<void> _openImageViewer(String id, int ordinal, Uint8List bytes) async {
    final store = state.attachments;
    if (store == null) {
      return;
    }
    final name = await store.nameOf(id) ?? id;
    if (!mounted) {
      return;
    }
    await showImageViewer(
      context,
      bytes: bytes,
      name: name,
      onAction: (action) => _attachmentAction(action, id, ordinal),
    );
  }

  Future<void> _attachmentContext(String id, int ordinal, Offset pos) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'save', child: Text('另存为')),
        const PopupMenuItem(value: 'copy', child: Text('复制')),
        PopupMenuItem(
            value: 'delete',
            child: Text('删除',
                style: TextStyle(color: inkOf(context).danger))),
      ],
    );
    if (value == null || !mounted) {
      return;
    }
    final message = await _attachmentAction(value, id, ordinal);
    if (message != null && mounted) {
      _snack(message);
    }
  }

  Future<String?> _attachmentAction(String action, String id, int ordinal) async {
    final store = state.attachments;
    if (store == null) {
      return null;
    }
    if (action == 'delete') {
      final ok = await confirm(
        context,
        title: '删除附件',
        message: '将从正文移除这一处引用，可在版本历史中恢复。',
        confirmLabel: '删除',
        danger: true,
      );
      if (!ok || !mounted) {
        return null;
      }
      final content = _contentController.text;
      final updated = removeAttachmentRefAt(content, id, ordinal);
      if (updated == null) {
        return '未找到对应引用';
      }
      setState(() {
        _note = _note?.copyWith(content: updated);
        _contentController.text = updated;
      });
      _changed();
      return '已删除';
    }
    final bytes = await store.read(id);
    if (bytes == null) {
      return '附件文件不存在';
    }
    final name = await store.nameOf(id) ?? id;
    if (!mounted) {
      return null;
    }
    if (action == 'save') {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '另存为',
        fileName: name.replaceAll(RegExp(r'[/\\]'), '_'),
      );
      if (path == null) {
        return null;
      }
      await File(path).writeAsBytes(bytes, flush: true);
      return '已另存为 $path';
    }
    if (action == 'copy') {
      if (!isPdfLinkText(name)) {
        await Pasteboard.writeImage(bytes);
        return '图片已复制';
      }
      final safeName = name.replaceAll(RegExp(r'[/\\]'), '_');
      final dir = await Directory.systemTemp.createTemp('onenote_copy');
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes);
      await Pasteboard.writeFiles([file.path]);
      return '文件已复制';
    }
    return null;
  }

  Widget _editorArea() {
    final t = inkOf(context);
    final tint = Color(state.notebookColor(_note!.notebookId));
    final fill = readableOn(tint, t.paper, ratio: 3);
    final ink = readableOn(tint, t.paper);
    final onFill = readableOn(t.onAccent, fill);
    final editor = Container(
      color: t.paper,
      padding: const EdgeInsets.symmetric(horizontal: spaceSm),
      child: Listener(
        onPointerDown: (e) => _editorButtons = e.buttons,
        onPointerUp: _onEditorPointerUp,
        child: TextField(
        key: _editorFieldKey,
        controller: _contentController,
        focusNode: _contentFocus,
        scrollController: _editScroll,
        onChanged: (_) => _changed(),
        autofocus: true,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: _editorTextStyle(t),
        decoration: const InputDecoration(
          hintText: '用 Markdown 书写…',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.all(spaceMd),
        ),
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
                      SizedBox(
                        height: 40,
                        width: 48,
                        child: FilledButton(
                          onPressed: _exitEdit,
                          style: ButtonStyle(
                            padding:
                                const WidgetStatePropertyAll(EdgeInsets.zero),
                            mouseCursor: const WidgetStatePropertyAll(
                              SystemMouseCursors.click,
                            ),
                            backgroundColor: WidgetStatePropertyAll(fill),
                            foregroundColor: WidgetStatePropertyAll(onFill),
                            overlayColor: WidgetStatePropertyAll(
                                onFill.withValues(alpha: 0.1)),
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(radiusMd),
                              ),
                            ),
                          ),
                          child: Semantics(
                            button: true,
                            label: '完成',
                            child: const Icon(Icons.check, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_replaceOpen) _replacePanel(t),
        Expanded(child: editor),
      ],
    );
    final themed = TextSelectionTheme(
      data: TextSelectionThemeData(
          cursorColor: ink, selectionColor: fill.withValues(alpha: 0.4)),
      child: area,
    );
    if (kIsWeb) {
      return themed;
    }
    return DropTarget(
      onDrop: _onDrop,
      acceptedKinds: const {DropItemKind.file},
      child: Actions(
        actions: {
          PasteTextIntent: CallbackAction<PasteTextIntent>(
            onInvoke: (_) {
              _handlePaste();
              return null;
            },
          ),
        },
        child: themed,
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
    if (note.format == AppDb.noteFormatRichtext) {
      return RichTextNoteView(
        key: _richtextKey,
        state: state,
        noteId: note.id,
        showBack: widget.showBack,
        onBack: widget.onBack,
        highlightQuery: widget.highlightQuery,
        onShowHistory: () => showNoteHistory(context,
            state: state, noteId: note.id, onRestored: () async {
          await _richtextKey.currentState?.reloadAfterRestore();
        }),
      );
    }
    final isWideWindow = MediaQuery.sizeOf(context).width >= 900;
    final tocTint = Color(state.notebookColor(note.notebookId));
    final content = Column(
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
                    ? TextSelectionTheme(
                        data: TextSelectionThemeData(
                          cursorColor: readableOn(tocTint, t.paper),
                          selectionColor:
                              readableOn(tocTint, t.paper, ratio: 3)
                                  .withValues(alpha: 0.4),
                        ),
                        child: TextField(
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
        if (state.sync.conflictIds.contains(widget.noteId))
          _conflictBanner(t),
        Expanded(
          child: _editing
              ? _editorArea()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final tocEntries = _tocEntries();
                    final showTocColumn = isWideWindow &&
                        _tocVisible &&
                        tocEntries.isNotEmpty &&
                        constraints.maxWidth >= _tocColumnMinWidth;
                    final showTocButton =
                        !showTocColumn && _tocVisible && tocEntries.isNotEmpty;
                    final renderArea = Stack(
                      key: _renderViewportKey,
                      fit: StackFit.expand,
                      children: [
                        SingleChildScrollView(
                          key: PageStorageKey<String>(
                              'noteScroll:${widget.noteId}'),
                          controller: _renderScroll,
                          padding: const EdgeInsets.fromLTRB(
                              spaceLg, spaceLg, spaceLg, spaceXxl),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: _noteColumnWidth),
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
                                    onAttachmentPdfTap: _openPdfViewer,
                                    onAttachmentImageTap: _openImageViewer,
                                    onAttachmentContext: _attachmentContext,
                                    onToggleTask: _toggleTask,
                                    highlightQuery: widget.highlightQuery,
                                    highlightActiveIndex: _matchIndex,
                                    highlightController: _highlight,
                                    tocController: _toc,
                                    tint: tocTint,
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
                                child: _editButton(t, tocTint),
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
                        if (showTocButton)
                          Positioned.fill(
                            child: _readingColumnOverlay(
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                      right: spaceXs,
                                      bottom:
                                          spaceLg + (_showScrollTop ? 52 : 0)),
                                  child: _tocButton(t),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                    final Widget body = showTocColumn
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: renderArea),
                              Container(
                                width: noteTocWidth,
                                decoration: BoxDecoration(
                                  border: Border(
                                      left: BorderSide(color: t.hairline)),
                                ),
                                child: NoteTocPanel(
                                  entries: tocEntries,
                                  activeIndex: _tocActive,
                                  tint: tocTint,
                                  onTap: _jumpToTocEntry,
                                ),
                              ),
                            ],
                          )
                        : renderArea;
                    return Stack(
                      key: _navAreaKey,
                      fit: StackFit.expand,
                      children: [
                        body,
                        if (_highlight.matches.isNotEmpty)
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final area = constraints.biggest;
                                final bar = _navSize;
                                final contentArea = Size(
                                    area.width -
                                        (showTocColumn ? noteTocWidth : 0.0),
                                    area.height);
                                final pos = _clampNav(
                                    _navPos ??
                                        _defaultNavPos(contentArea, bar),
                                    area,
                                    bar);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
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
                    );
                  },
                ),
        ),
      ],
    );
    final Widget listened = Listener(
      onPointerDown: (_) => _touchLease(),
      child: content,
    );
    if (!isDesktopWindow) {
      return listened;
    }
    return CallbackShortcuts(
      bindings: {
        if (_editing) ...{
          const SingleActivator(LogicalKeyboardKey.keyR, meta: true):
              _openReplace,
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              _openReplace,
        },
        if (_replaceOpen)
          const SingleActivator(LogicalKeyboardKey.escape): _closeReplace,
      },
      child: listened,
    );
  }

  Widget _conflictBanner(InkTokens t) {
    return Container(
      color: t.danger.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(spaceMd, spaceSm, spaceMd, spaceSm),
      child: Row(
        children: [
          Icon(Icons.sync_problem, size: 18, color: t.danger),
          const SizedBox(width: spaceSm),
          Expanded(
            child: Text(
              '此笔记与其他设备的修改存在冲突，裁决前不会上传。',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: t.ink),
            ),
          ),
          TextButton(
            onPressed: () => showConflictPanel(context,
                state: state, noteId: widget.noteId),
            child: const Text('去裁决'),
          ),
        ],
      ),
    );
  }

  Widget _editButton(InkTokens t, Color tint) {
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
            foregroundColor:
                WidgetStatePropertyAll(readableOn(tint, t.paper)),
            overlayColor:
                WidgetStatePropertyAll(tint.withValues(alpha: 0.08)),
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
    final note = _note;
    final hasPassword =
        note != null && state.noteLock(note.id)?.active == true;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(
            value: 'toc',
            child: Text(_tocVisible ? '隐藏目录' : '显示目录')),
        const PopupMenuItem(value: 'history', child: Text('版本历史')),
        PopupMenuItem(
            value: 'password',
            child: Text(hasPassword ? '修改密码' : '设置密码')),
        if (hasPassword)
          const PopupMenuItem(value: 'removePassword', child: Text('移除密码')),
        const PopupMenuItem(value: 'trash', child: Text('删除')),
      ],
    );
    if (!mounted) {
      return;
    }
    if (value == 'toc') {
      _toggleTocVisible();
    } else if (value == 'history') {
      _showHistory();
    } else if (value == 'password') {
      if (note != null) {
        await setNotePasswordFlow(context, state, note.id);
      }
    } else if (value == 'removePassword') {
      if (note != null) {
        await removeNotePasswordFlow(context, state, note.id);
      }
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

  Widget _tocButton(InkTokens t) {
    return Semantics(
      button: true,
      label: '目录',
      child: Material(
        color: t.surfaceAlt,
        shape: CircleBorder(side: BorderSide(color: t.hairline)),
        elevation: 4,
        shadowColor: Colors.black54,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _openTocSheet,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.format_list_bulleted, color: t.inkMuted),
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

  TextStyle _editorTextStyle(InkTokens t) => TextStyle(
        fontFamily: t.sans,
        fontFamilyFallback: cjkSansFallback,
        fontSize: t.noteFontSize * t.fontScale,
        height: 1.75,
        color: t.ink,
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
        await widget.state.restoreVersion(widget.noteId, version.id);
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