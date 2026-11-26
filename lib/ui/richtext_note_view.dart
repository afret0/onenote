import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart'
    show MarkdownTocEntry;
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';

import '../data/app_db.dart';
import '../data/attachment_store.dart';
import '../richtext/document_matches.dart';
import '../richtext/markdown_codec.dart';
import '../state/app_state.dart';
import '../window_setup.dart';
import 'conflict_panel.dart';
import 'dialogs.dart';
import 'note_toc.dart';
import 'password_prompts.dart';
import 'richtext_blocks.dart';
import 'theme.dart';
import 'widgets.dart';

const _noteColumnWidth = 760.0;
const _tocColumnMinWidth = 600.0;
const _revealOffset = 96.0;
const _navPosSettingKey = 'searchNavPos';
const _tocVisibleSettingKey = 'tocVisible';

String _formatHm(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.hour)}:${two(date.minute)}';
}

String _titleOf(Note note) =>
    note.title.trim().isEmpty ? '无标题' : note.title.trim();

class RichTextNoteView extends StatefulWidget {
  const RichTextNoteView({
    super.key,
    required this.state,
    required this.noteId,
    required this.showBack,
    required this.onBack,
    required this.onShowHistory,
    this.highlightQuery,
  });

  final AppState state;
  final String noteId;
  final bool showBack;
  final VoidCallback onBack;
  final Future<void> Function() onShowHistory;
  final String? highlightQuery;

  @override
  State<RichTextNoteView> createState() => RichTextNoteViewState();
}

class RichTextNoteViewState extends State<RichTextNoteView> {
  Note? _note;
  EditorState? _editorState;
  EditorScrollController? _editorScroll;
  ScrollPosition? _boundPosition;
  final GlobalKey _viewportKey = GlobalKey();
  final GlobalKey _editorKey = GlobalKey();
  late final TextEditingController _titleController;
  bool _dirty = false;
  String _saveStatus = '';
  Timer? _autosave;
  bool _suppressTx = false;
  StreamSubscription<EditorTransactionValue>? _txSub;
  final FocusNode _editorFocus = FocusNode();

  List<MarkdownTocEntry> _tocEntries = [];
  final Map<String, GlobalKey> _headingKeys = {};
  int _tocActive = -1;
  bool _tocVisible = true;

  List<RichtextMatch> _matches = [];
  int _matchIndex = 0;
  Map<String, List<RichtextMatch>> _matchesByPath = {};

  bool _replaceOpen = false;
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  List<RichtextMatch> _findMatches = [];
  int _findIndex = 0;

  final GlobalKey _navKey = GlobalKey();
  Size _navSize = const Size(200, 52);
  Offset? _navPos;
  bool _showScrollTop = false;

  AppState get state => widget.state;
  Document? get _document => _editorState?.document;
  ScrollPosition? get _scrollPosition => _editorState?.scrollableState?.position;

  Future<void> flushEdits() => _save(silent: true);

  Future<void> reloadAfterRestore() => _reloadNote();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    state.addListener(_reloadIfIdle);
    _load();
    _loadNavPos();
    _loadTocVisible();
  }

  @override
  void didUpdateWidget(covariant RichTextNoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _save(silent: true);
      _load();
    } else if (oldWidget.highlightQuery != widget.highlightQuery) {
      _rebuildMatches();
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    state.removeListener(_reloadIfIdle);
    _txSub?.cancel();
    _titleController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _findFocus.dispose();
    _editorFocus.dispose();
    _boundPosition?.removeListener(_onScroll);
    _editorScroll?.dispose();
    _editorState?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final note = await state.db.findNote(widget.noteId);
    if (!mounted || note == null) {
      return;
    }
    _titleController.text = note.title;
    _attachDocument(note.content);
    setState(() {
      _note = note;
      _dirty = false;
      _saveStatus = '';
    });
    _rebuildToc();
    _rebuildMatches();
    unawaited(_syncOnOpen());
  }

  void _attachDocument(String content) {
    _suppressTx = true;
    _txSub?.cancel();
    _editorScroll?.dispose();
    _editorState?.dispose();
    final document = richtextDecode(content);
    final editorState = EditorState(document: document);
    _editorState = editorState;
    _editorScroll = EditorScrollController(
      editorState: editorState,
      shrinkWrap: true,
    );
    _txSub = editorState.transactionStream.listen(_onTransaction);
    _suppressTx = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _bindScroll();
      }
    });
  }

  void _bindScroll() {
    final position = _scrollPosition;
    if (position == null || position == _boundPosition) {
      return;
    }
    _boundPosition?.removeListener(_onScroll);
    _boundPosition = position;
    position.addListener(_onScroll);
  }

  Future<void> _syncOnOpen() async {
    final outcome = await state.syncNow('edit');
    if (!mounted) {
      return;
    }
    if (outcome.error != null) {
      developer.log('skip, 富文本打开前同步失败放行离线编辑, noteId: ${widget.noteId}, err: ${outcome.error}');
    }
    if (state.sync.conflictIds.contains(widget.noteId)) {
      await showConflictPanel(context, state: state, noteId: widget.noteId);
    }
    if (mounted) {
      _reloadIfIdle();
    }
  }

  void _onTransaction(EditorTransactionValue value) {
    if (_suppressTx || !mounted) {
      return;
    }
    _dirty = true;
    _autosave?.cancel();
    _autosave =
        Timer(const Duration(milliseconds: 800), () => _save(silent: true));
    setState(() => _saveStatus = '未保存');
    _rebuildToc();
    _rebuildMatches();
    if (_replaceOpen) {
      _refreshFindMatches(null);
    }
  }

  void _reloadIfIdle() {
    if (_dirty || _note == null || !mounted) {
      return;
    }
    unawaited(_reloadNote());
  }

  Future<void> _reloadNote() async {
    final fresh = await state.db.findNote(widget.noteId);
    if (!mounted || fresh == null) {
      return;
    }
    final current = _note!;
    if (fresh.content == current.content && fresh.title == current.title) {
      return;
    }
    final encoded = _document == null ? '' : richtextEncode(_document!);
    if (fresh.content == encoded && fresh.title == _titleController.text) {
      setState(() => _note = fresh);
      return;
    }
    _titleController.text = fresh.title;
    _attachDocument(fresh.content);
    setState(() {
      _note = fresh;
      _dirty = false;
    });
    _rebuildToc();
    _rebuildMatches();
  }

  Future<void> _save({bool silent = false}) async {
    _autosave?.cancel();
    final note = _note;
    final document = _document;
    if (note == null || document == null || !_dirty) {
      return;
    }
    final title = _titleController.text;
    final content = richtextEncode(document);
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
      _saveStatus = changed ? '已保存 ${_formatHm(fresh.updateAt)}' : '无变更';
    });
    if (typedDuringSave) {
      return;
    }
    _dirty = false;
    if (fresh.content != content) {
      _attachDocument(fresh.content);
      _rebuildToc();
      _rebuildMatches();
      developer.log('hit, 富文本保存后回填合并结果, noteId: ${fresh.id}');
    }
    if (!silent && !changed) {
      _snack('内容没有变化');
    }
  }

  void _rebuildToc() {
    final document = _document;
    if (document == null) {
      return;
    }
    final entries = <MarkdownTocEntry>[];
    void walk(Node node) {
      if (node.type == HeadingBlockKeys.type) {
        final level = node.attributes[HeadingBlockKeys.level] as int? ?? 1;
        if (level <= noteTocMaxLevel) {
          final key = _headingKeys.putIfAbsent(node.id, () => GlobalKey());
          entries.add(MarkdownTocEntry(
              key, level, node.delta?.toPlainText() ?? ''));
        }
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final node in document.root.children) {
      walk(node);
    }
    _tocEntries = entries;
    _updateTocActive();
  }

  void _updateTocActive() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox) {
      return;
    }
    var active = -1;
    for (var i = 0; i < _tocEntries.length; i++) {
      final box = _tocEntries[i].key.currentContext?.findRenderObject();
      if (box is! RenderBox) {
        continue;
      }
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top <= _revealOffset + 1) {
        active = i;
      }
    }
    if (active != _tocActive) {
      setState(() => _tocActive = active);
    }
  }

  void _jumpToTocEntry(MarkdownTocEntry entry) {
    final box = entry.key.currentContext?.findRenderObject();
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final position = _scrollPosition;
    if (box is! RenderBox || viewport is! RenderBox || position == null) {
      return;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final target = (position.pixels + top - _revealOffset)
        .clamp(0.0, position.maxScrollExtent);
    position.animateTo(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  void _rebuildMatches() {
    final document = _document;
    final query = widget.highlightQuery ?? '';
    if (document == null || query.isEmpty) {
      if (_matches.isNotEmpty) {
        setState(() {
          _matches = [];
          _matchesByPath = {};
          _matchIndex = 0;
        });
      }
      return;
    }
    final matches = richtextFindMatches(document, query);
    final byPath = <String, List<RichtextMatch>>{};
    for (final m in matches) {
      byPath.putIfAbsent(m.path.join('/'), () => []).add(m);
    }
    setState(() {
      _matches = matches;
      _matchesByPath = byPath;
      _matchIndex = matches.isEmpty ? 0 : _matchIndex.clamp(0, matches.length - 1);
    });
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) {
      return;
    }
    setState(() {
      _matchIndex = (_matchIndex + delta) % _matches.length;
      if (_matchIndex < 0) {
        _matchIndex += _matches.length;
      }
    });
    _revealMatch(_matches[_matchIndex]);
  }

  void _revealMatch(RichtextMatch match) {
    final node = _document?.nodeAtPath(match.path);
    if (node == null) {
      return;
    }
    _editorState?.selection = Selection.single(
      path: match.path,
      startOffset: match.start,
      endOffset: match.end,
    );
    final key = _headingKeys[node.id];
    final box = (key?.currentContext?.findRenderObject()) ??
        node.key.currentContext?.findRenderObject();
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final position = _scrollPosition;
    if (box is! RenderBox || viewport is! RenderBox || position == null) {
      return;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final target = (position.pixels + top - _revealOffset)
        .clamp(0.0, position.maxScrollExtent);
    position.animateTo(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  InlineSpan _decorateSpan(BuildContext context, Node node, int index,
      TextInsert text, TextSpan before, TextSpan after) {
    final nodeMatches = _matchesByPath[node.path.join('/')];
    if (nodeMatches == null || nodeMatches.isEmpty) {
      return before;
    }
    final delta = node.delta;
    if (delta == null) {
      return before;
    }
    var offset = 0;
    var opIndex = 0;
    for (final op in delta) {
      if (opIndex >= index) {
        break;
      }
      offset += op.length;
      opIndex++;
    }
    final textLen = text.text.length;
    final end = offset + textLen;
    final t = inkOf(context);
    final active = _matches.isEmpty ? null : _matches[_matchIndex];
    final children = <InlineSpan>[];
    var cursor = offset;
    for (final m in nodeMatches) {
      if (m.end <= offset || m.start >= end) {
        continue;
      }
      final s = math.max(m.start, offset);
      final e = math.min(m.end, end);
      if (s > cursor) {
        children.add(TextSpan(
            text: text.text.substring(cursor - offset, s - offset),
            style: before.style));
      }
      final isActive = active != null &&
          active.path.join('/') == node.path.join('/') &&
          active.start == m.start &&
          active.end == m.end;
      children.add(TextSpan(
        text: text.text.substring(s - offset, e - offset),
        style: (before.style ?? const TextStyle()).copyWith(
          backgroundColor: isActive ? t.searchActive : t.searchMark,
          color: isActive ? t.searchActiveInk : before.style?.color,
        ),
      ));
      cursor = e;
    }
    if (children.isEmpty) {
      return before;
    }
    if (cursor < end) {
      children.add(TextSpan(
          text: text.text.substring(cursor - offset), style: before.style));
    }
    return TextSpan(style: before.style, children: children);
  }

  void _onScroll() {
    _updateTocActive();
    final position = _scrollPosition;
    final show = position != null && position.pixels > 400;
    if (show != _showScrollTop) {
      setState(() => _showScrollTop = show);
    }
  }

  void _scrollToTop() {
    final position = _scrollPosition;
    if (position != null) {
      position.animateTo(0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    }
  }

  Future<void> _loadNavPos() async {
    final raw = await state.db.getSetting(_navPosSettingKey);
    if (!mounted || raw == null) {
      return;
    }
    final parts = raw.split(',');
    if (parts.length == 2) {
      final x = double.tryParse(parts[0]);
      final y = double.tryParse(parts[1]);
      if (x != null && y != null) {
        setState(() => _navPos = Offset(x, y));
      }
    }
  }

  void _dragNav(Offset delta) {
    setState(() => _navPos = (_navPos ?? Offset.zero) + delta);
  }

  Future<void> _saveNavPos() async {
    final pos = _navPos;
    if (pos != null) {
      await state.db.setSetting(
          _navPosSettingKey, '${pos.dx.round()},${pos.dy.round()}');
    }
  }

  Future<void> _loadTocVisible() async {
    final raw = await state.db.getSetting(_tocVisibleSettingKey);
    if (mounted && raw == '0') {
      setState(() => _tocVisible = false);
    }
  }

  Future<void> _toggleTocVisible() async {
    setState(() => _tocVisible = !_tocVisible);
    await state.db
        .setSetting(_tocVisibleSettingKey, _tocVisible ? '1' : '0');
  }

  void _openReplace() {
    setState(() {
      _replaceOpen = true;
      _findIndex = 0;
    });
    _refreshFindMatches(null);
    _findFocus.requestFocus();
  }

  void _closeReplace() {
    setState(() => _replaceOpen = false);
    _editorFocus.requestFocus();
  }

  void _refreshFindMatches(int? preferred) {
    final document = _document;
    final needle = _findController.text;
    if (document == null || needle.isEmpty) {
      setState(() {
        _findMatches = [];
        _findIndex = 0;
      });
      return;
    }
    final matches =
        richtextFindMatches(document, needle, caseSensitive: true);
    setState(() {
      _findMatches = matches;
      _findIndex = matches.isEmpty
          ? 0
          : (preferred ?? _findIndex).clamp(0, matches.length - 1);
    });
  }

  void _stepFind(int delta) {
    if (_findMatches.isEmpty) {
      return;
    }
    setState(() {
      _findIndex = (_findIndex + delta) % _findMatches.length;
      if (_findIndex < 0) {
        _findIndex += _findMatches.length;
      }
    });
    _revealMatch(_findMatches[_findIndex]);
  }

  void _replaceCurrent() {
    if (_findMatches.isEmpty) {
      return;
    }
    final m = _findMatches[_findIndex];
    final node = _document?.nodeAtPath(m.path);
    if (node == null) {
      return;
    }
    final transaction = _editorState!.transaction
      ..replaceText(node, m.start, m.end - m.start, _replaceController.text);
    _editorState!.apply(transaction);
    _refreshFindMatches(_findIndex);
  }

  void _replaceAll() {
    final document = _document;
    if (document == null || _findMatches.isEmpty) {
      return;
    }
    final replacement = _replaceController.text;
    final transaction = _editorState!.transaction;
    final byNode = <String, List<RichtextMatch>>{};
    for (final m in _findMatches) {
      byNode.putIfAbsent(m.path.join('/'), () => []).add(m);
    }
    for (final entry in byNode.entries) {
      final node = document.nodeAtPath(entry.value.first.path);
      if (node == null) {
        continue;
      }
      final sorted = entry.value.toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      for (final m in sorted) {
        transaction.replaceText(node, m.start, m.end - m.start, replacement);
      }
    }
    _editorState!.apply(transaction);
    _refreshFindMatches(0);
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _toggleInline(String key) {
    _editorState?.toggleAttribute(key);
    _editorFocus.requestFocus();
  }

  void _convertBlock(Node Function(Node node) builder) {
    final editorState = _editorState;
    if (editorState == null || editorState.selection == null) {
      return;
    }
    editorState.formatNode(editorState.selection, builder);
    _editorFocus.requestFocus();
  }

  void _toParagraph() {
    convertToParagraphCommand.execute(_editorState!);
    _editorFocus.requestFocus();
  }

  void _insertBlock(Node node) {
    final editorState = _editorState;
    if (editorState == null) {
      return;
    }
    final selection = editorState.selection;
    final path = selection?.end.path ?? [editorState.document.root.children.length - 1];
    final newPath = [...path.sublist(0, path.length - 1), path.last + 1];
    final transaction = editorState.transaction
      ..insertNode(newPath, node)
      ..afterSelection = Selection.collapsed(Position(path: newPath, offset: 0));
    editorState.apply(transaction);
    _editorFocus.requestFocus();
  }

  void _insertTable() {
    final table = TableNode.fromList<String>([
      ['', ''],
      ['', ''],
    ]);
    _insertBlock(table.node);
  }

  void _insertCodeBlock() {
    final editorState = _editorState;
    final selection = editorState?.selection;
    if (editorState == null || selection == null) {
      return;
    }
    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null) {
      return;
    }
    if (node.type == richtextCodeBlockType) {
      _toParagraph();
      return;
    }
    editorState.formatNode(
      selection,
      (n) => Node(type: richtextCodeBlockType, attributes: {
        'delta': (n.delta ?? Delta()).toJson(),
        'language': '',
      }),
    );
    _editorFocus.requestFocus();
  }

  Future<void> _insertLink() async {
    final editorState = _editorState;
    final selection = editorState?.selection;
    if (editorState == null || selection == null || selection.isCollapsed) {
      _snack('请先选中要加链接的文字');
      return;
    }
    final url = await _promptLink();
    if (url == null || url.isEmpty) {
      return;
    }
    editorState.formatDelta(selection, {BuiltInAttributeKey.href: url});
    _editorFocus.requestFocus();
  }

  Future<String?> _promptLink() async {
    final controller = TextEditingController(text: 'https://');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final t = inkOf(context);
        return AlertDialog(
          backgroundColor: t.surface,
          title: const Text('插入链接'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'https://example.com'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('确定')),
          ],
        );
      },
    );
    controller.dispose();
    return result;
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
      if (asImage) {
        _insertBlock(imageNode(url: '${AttachmentStore.scheme}://$id')
          ..updateAttributes({richtextImageAltKey: name}));
      } else {
        final delta = Delta()
          ..insert(name, attributes: {
            BuiltInAttributeKey.href: '${AttachmentStore.scheme}://$id',
          });
        _insertBlock(paragraphNode(delta: delta));
      }
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
    pasteCommand.execute(_editorState!);
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

  Future<void> _openAsset(String id) async {
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
    await _openExternally(bytes, name);
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

  Future<void> _assetContext(String id, Offset pos) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'save', child: Text('另存为')),
        PopupMenuItem(value: 'delete', child: Text('删除图片')),
      ],
    );
    if (!mounted || value == null) {
      return;
    }
    final store = state.attachments;
    if (store == null) {
      return;
    }
    final bytes = await store.read(id);
    if (bytes == null) {
      return;
    }
    final name = await store.nameOf(id) ?? id;
    if (value == 'save') {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '另存为',
        fileName: name,
      );
      if (path != null) {
        await File(path).writeAsBytes(bytes);
        _snack('已另存为');
      }
    } else if (value == 'delete') {
      _deleteImageNode(id);
    }
  }

  void _deleteImageNode(String id) {
    final document = _document;
    if (document == null) {
      return;
    }
    Node? target;
    void walk(Node node) {
      if (node.type == ImageBlockKeys.type &&
          (node.attributes[ImageBlockKeys.url] as String? ?? '').contains(id)) {
        target = node;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final node in document.root.children) {
      walk(node);
    }
    if (target != null) {
      final transaction = _editorState!.transaction..deleteNode(target!);
      _editorState!.apply(transaction);
    }
  }

  Future<void> _showNoteMenu(Offset pos) async {
    final note = _note;
    final hasPassword = note != null && state.noteLock(note.id)?.active == true;
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
    if (!mounted || value == null) {
      return;
    }
    if (value == 'toc') {
      _toggleTocVisible();
    } else if (value == 'history') {
      await _save(silent: true);
      if (mounted) {
        await widget.onShowHistory();
      }
    } else if (value == 'password') {
      if (note != null) {
        await setNotePasswordFlow(context, state, note.id);
      }
    } else if (value == 'removePassword') {
      if (note != null) {
        await removeNotePasswordFlow(context, state, note.id);
      }
    } else if (value == 'trash') {
      await _trash();
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
        message: '「${_titleOf(note)}」将保留 $days 天，可随时恢复。');
    if (ok && mounted) {
      await _save(silent: true);
      await state.trashNote(note.id);
    }
  }

  TextStyle _titleStyle(BuildContext context) {
    final t = inkOf(context);
    return TextStyle(
      fontFamily: serifFamily,
      fontSize: 26 * t.fontScale,
      fontWeight: FontWeight.w600,
      color: t.ink,
      height: 1.3,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final note = _note;
    final editorState = _editorState;
    if (note == null || editorState == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isWideWindow = MediaQuery.sizeOf(context).width >= 900;
    final tint = Color(state.notebookColor(note.notebookId));
    final editorStyle = EditorStyle.desktop(
      padding: const EdgeInsets.symmetric(horizontal: spaceLg),
      cursorColor: readableOn(tint, t.paper),
      selectionColor: readableOn(tint, t.paper, ratio: 3).withValues(alpha: 0.3),
      textSpanDecorator: _decorateSpan,
      textStyleConfiguration: TextStyleConfiguration(
        text: TextStyle(
          fontFamily: t.sans,
          fontSize: t.noteFontSize,
          color: t.ink,
          height: 1.7,
        ),
        bold: const TextStyle(fontWeight: FontWeight.w700),
        italic: const TextStyle(fontStyle: FontStyle.italic),
        strikethrough: const TextStyle(decoration: TextDecoration.lineThrough),
        href: TextStyle(color: t.accentText, decoration: TextDecoration.underline),
        code: TextStyle(fontFamily: monoFamily, color: t.accentText),
        lineHeight: 1.7,
      ),
    );

    final editor = AppFlowyEditor(
      key: _editorKey,
      editorState: editorState,
      editorScrollController: _editorScroll,
      shrinkWrap: true,
      autoFocus: true,
      focusNode: _editorFocus,
      editorStyle: editorStyle,
      blockComponentBuilders: richtextBlockBuilders(
        tokens: t,
        noteFontSize: t.noteFontSize,
        attachments: state.attachments,
        onOpenAsset: _openAsset,
        onAssetContext: _assetContext,
      ),
      characterShortcutEvents: richtextCharacterShortcuts(),
      blockWrapper: (context, {required node, required child}) {
        if (node.type == HeadingBlockKeys.type) {
          final key = _headingKeys[node.id];
          if (key != null) {
            return KeyedSubtree(key: key, child: child);
          }
        }
        return child;
      },
      header: Padding(
        padding: const EdgeInsets.fromLTRB(spaceLg, spaceMd, spaceLg, spaceMd),
        child: _metaRow(note),
      ),
      footer: const SizedBox(height: spaceXxl),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.hairline))),
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
                child: TextField(
                  controller: _titleController,
                  onChanged: (_) {
                    _dirty = true;
                    _autosave?.cancel();
                    _autosave = Timer(const Duration(milliseconds: 800),
                        () => _save(silent: true));
                    setState(() => _saveStatus = '未保存');
                  },
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
              ),
              if (_saveStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: spaceSm),
                  child: Text(_saveStatus,
                      style: Theme.of(context).textTheme.labelSmall),
                ),
              GestureDetector(
                onSecondaryTapUp: (d) => _showNoteMenu(d.globalPosition),
                onLongPressStart: (d) => _showNoteMenu(d.globalPosition),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: spaceSm),
                  child: Icon(Icons.more_horiz, color: t.inkMuted),
                ),
              ),
            ],
          ),
        ),
        if (state.sync.conflictIds.contains(widget.noteId))
          _conflictBanner(t),
        _toolbar(t, tint),
        if (_replaceOpen) _replacePanel(t, tint),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final entries = noteTocVisibleEntries(_tocEntries);
              final showTocColumn = isWideWindow &&
                  _tocVisible &&
                  entries.isNotEmpty &&
                  constraints.maxWidth >= _tocColumnMinWidth;
              final showTocButton =
                  !showTocColumn && _tocVisible && entries.isNotEmpty;
              final editorArea = Stack(
                key: _viewportKey,
                fit: StackFit.expand,
                children: [
                  DropTarget(
                    onDrop: _onDrop,
                    acceptedKinds: const {DropItemKind.file},
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _noteColumnWidth),
                        child: Actions(
                          actions: {
                            PasteTextIntent: CallbackAction<PasteTextIntent>(
                              onInvoke: (_) {
                                _handlePaste();
                                return null;
                              },
                            ),
                          },
                          child: editor,
                        ),
                      ),
                    ),
                  ),
                  if (_matches.isNotEmpty)
                    _matchNavPositioned(t, constraints),
                  if (showTocButton)
                    Positioned(
                      right: spaceMd,
                      bottom: _showScrollTop ? spaceLg + 52 : spaceLg,
                      child: _tocButton(t, tint, entries),
                    ),
                  if (_showScrollTop)
                    Positioned(
                      right: spaceMd,
                      bottom: spaceLg,
                      child: _scrollTopButton(t),
                    ),
                ],
              );
              if (!showTocColumn) {
                return editorArea;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: editorArea),
                  Container(
                    width: noteTocWidth,
                    decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: t.hairline))),
                    child: NoteTocPanel(
                      entries: entries,
                      activeIndex: _tocActive,
                      tint: tint,
                      onTap: _jumpToTocEntry,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );

    return Shortcuts(
      shortcuts: isDesktopWindow
          ? {
              SingleActivator(LogicalKeyboardKey.keyR,
                  meta: Platform.isMacOS, control: !Platform.isMacOS):
                  const _OpenReplaceIntent(),
            }
          : const {},
      child: Actions(
        actions: {
          _OpenReplaceIntent: CallbackAction<_OpenReplaceIntent>(
            onInvoke: (_) {
              _openReplace();
              return null;
            },
          ),
        },
        child: content,
      ),
    );
  }

  Widget _toolbar(InkTokens t, Color tint) {
    Widget button(IconData icon, String label, VoidCallback onTap) {
      return Semantics(
        button: true,
        label: label,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          color: t.ink,
          visualDensity: VisualDensity.compact,
          style: ButtonStyle(
            mouseCursor:
                const WidgetStatePropertyAll(SystemMouseCursors.click),
            overlayColor: WidgetStatePropertyAll(t.ink.withValues(alpha: 0.05)),
          ),
        ),
      );
    }

    Widget divider() => Container(
        width: 1, height: 20, color: t.hairline, margin: const EdgeInsets.symmetric(horizontal: spaceXs));

    return Container(
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.hairline))),
      padding: const EdgeInsets.symmetric(horizontal: spaceSm, vertical: spaceXs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            button(Icons.format_bold, '粗体', () => _toggleInline(BuiltInAttributeKey.bold)),
            button(Icons.format_italic, '斜体', () => _toggleInline(BuiltInAttributeKey.italic)),
            button(Icons.format_strikethrough, '删除线', () => _toggleInline(BuiltInAttributeKey.strikethrough)),
            button(Icons.code, '行内代码', () => _toggleInline(BuiltInAttributeKey.code)),
            divider(),
            button(Icons.looks_one_outlined, '一级标题', () => _convertBlock((n) => headingNode(level: 1, delta: n.delta))),
            button(Icons.looks_two_outlined, '二级标题', () => _convertBlock((n) => headingNode(level: 2, delta: n.delta))),
            button(Icons.looks_3_outlined, '三级标题', () => _convertBlock((n) => headingNode(level: 3, delta: n.delta))),
            divider(),
            button(Icons.format_list_bulleted, '无序列表', () => _convertBlock((n) => bulletedListNode(delta: n.delta))),
            button(Icons.format_list_numbered, '有序列表', () => _convertBlock((n) => numberedListNode(delta: n.delta))),
            button(Icons.check_box_outlined, '待办清单', () => _convertBlock((n) => todoListNode(checked: false, delta: n.delta))),
            button(Icons.format_quote, '引用', () => _convertBlock((n) => quoteNode(delta: n.delta))),
            button(Icons.data_object, '代码块', _insertCodeBlock),
            divider(),
            button(Icons.link, '链接', _insertLink),
            button(Icons.image_outlined, '插入图片', () => _pickFiles(image: true)),
            button(Icons.attach_file, '插入文件', () => _pickFiles(image: false)),
            button(Icons.horizontal_rule, '分割线', () => _insertBlock(dividerNode())),
            button(Icons.table_chart_outlined, '插入表格', _insertTable),
            divider(),
            button(Icons.format_clear, '转为正文', _toParagraph),
          ],
        ),
      ),
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
            child: Text('此笔记与其他设备的修改存在冲突，裁决前不会上传。',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: t.ink)),
          ),
          TextButton(
            onPressed: () =>
                showConflictPanel(context, state: state, noteId: widget.noteId),
            child: const Text('去裁决'),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(Note note) {
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
      ],
    );
  }

  Widget _replacePanel(InkTokens t, Color tint) {
    return Container(
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.hairline))),
      padding: const EdgeInsets.symmetric(horizontal: spaceMd, vertical: spaceSm),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: TextField(
              controller: _findController,
              focusNode: _findFocus,
              onChanged: (_) => _refreshFindMatches(0),
              style: TextStyle(fontSize: 13 * t.fontScale, color: t.ink),
              decoration: InputDecoration(
                hintText: '查找（区分大小写）',
                isDense: true,
                suffixText: _findMatches.isEmpty
                    ? null
                    : '${_findIndex + 1}/${_findMatches.length}',
              ),
            ),
          ),
          const SizedBox(width: spaceSm),
          IconButton(
            onPressed: () => _stepFind(-1),
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
          ),
          IconButton(
            onPressed: () => _stepFind(1),
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          ),
          const SizedBox(width: spaceSm),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _replaceController,
              style: TextStyle(fontSize: 13 * t.fontScale, color: t.ink),
              decoration:
                  const InputDecoration(hintText: '替换为', isDense: true),
            ),
          ),
          const SizedBox(width: spaceSm),
          TextButton(onPressed: _replaceCurrent, child: const Text('替换')),
          TextButton(onPressed: _replaceAll, child: const Text('全部替换')),
          const Spacer(),
          IconButton(
            onPressed: _closeReplace,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _matchNavPositioned(InkTokens t, BoxConstraints constraints) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _navKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.size != _navSize) {
        _navSize = box.size;
      }
    });
    final pos = _navPos ??
        Offset(constraints.maxWidth - _navSize.width - spaceSm,
            constraints.maxHeight - _navSize.height - spaceLg - 52);
    final clamped = Offset(
      pos.dx.clamp(0.0, math.max(0.0, constraints.maxWidth - _navSize.width)),
      pos.dy.clamp(0.0, math.max(0.0, constraints.maxHeight - _navSize.height)),
    );
    return Positioned(
      left: clamped.dx,
      top: clamped.dy,
      child: _matchNav(t),
    );
  }

  Widget _matchNav(InkTokens t) {
    return MouseRegion(
      key: _navKey,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onPanUpdate: (d) => _dragNav(d.delta),
        onPanEnd: (_) => _saveNavPos(),
        child: Material(
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
                  padding: const EdgeInsets.symmetric(horizontal: spaceXs),
                  child: Text('${_matchIndex + 1}/${_matches.length}',
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                IconButton(
                  onPressed: () => _stepMatch(-1),
                  icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _stepMatch(1),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tocButton(InkTokens t, Color tint, List<MarkdownTocEntry> entries) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(22),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          mouseCursor: SystemMouseCursors.click,
          onTap: () => showNoteTocSheet(context,
              entries: entries,
              activeIndex: _tocActive,
              tint: tint, onSelect: _jumpToTocEntry),
          child: Icon(Icons.toc, color: readableOn(tint, t.surfaceAlt)),
        ),
      ),
    );
  }

  Widget _scrollTopButton(InkTokens t) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(22),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          mouseCursor: SystemMouseCursors.click,
          onTap: _scrollToTop,
          child: Icon(Icons.arrow_upward, color: t.ink),
        ),
      ),
    );
  }
}

class _OpenReplaceIntent extends Intent {
  const _OpenReplaceIntent();
}