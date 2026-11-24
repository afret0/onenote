import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';

import '../data/app_db.dart';
import '../data/attachment_store.dart';
import '../state/app_state.dart';
import 'dialogs.dart';
import 'markdown_view.dart';
import 'theme.dart';
import 'widgets.dart';

class NoteView extends StatefulWidget {
  const NoteView({
    super.key,
    required this.state,
    required this.noteId,
    required this.showBack,
    required this.onBack,
  });

  final AppState state;
  final String noteId;
  final bool showBack;
  final VoidCallback onBack;

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

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _load();
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
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _enterEdit() {
    setState(() {
      _editing = true;
      _dirty = false;
      _saveStatus = '';
    });
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
        onChanged: (_) => _changed(),
        autofocus: true,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontFamily: monoFamily,
          fontFamilyFallback: cjkMonoFallback,
          fontSize: 15,
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
    if (kIsWeb) {
      return editor;
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
        child: editor,
      ),
    );
  }

  Future<void> _showHistory() async {
    final note = _note;
    if (note == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: inkOf(context).surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _HistorySheet(
        state: state,
        noteId: note.id,
        onRestored: () async {
          Navigator.of(sheetContext).pop();
          setState(() => _editing = false);
          await _load();
        },
      ),
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
                  tooltip: '返回列表',
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
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: spaceSm),
                        child: Text(
                          noteDisplayTitle(note),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _titleStyle(context),
                        ),
                      ),
              ),
              if (_editing && _saveStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: spaceSm),
                  child: Text(_saveStatus,
                      style: Theme.of(context).textTheme.labelSmall),
                ),
              if (_editing) ...[
                IconButton(
                  tooltip: '插入图片',
                  onPressed: () => _pickFiles(image: true),
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton(
                  tooltip: '插入文件',
                  onPressed: () => _pickFiles(image: false),
                  icon: const Icon(Icons.attach_file),
                ),
              ],
              IconButton(
                tooltip: '版本历史',
                onPressed: _showHistory,
                icon: const Icon(Icons.history),
              ),
              if (!_editing)
                IconButton(
                  tooltip: '移入回收站',
                  onPressed: _trash,
                  icon: const Icon(Icons.delete_outline),
                ),
              const SizedBox(width: spaceXs),
              _editing
                  ? FilledButton.icon(
                      onPressed: _exitEdit,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('完成'),
                    )
                  : FilledButton.icon(
                      onPressed: _enterEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('编辑'),
                    ),
            ],
          ),
        ),
        Expanded(
          child: _editing
              ? _editorArea()
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      spaceLg, spaceLg, spaceLg, spaceXxl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: spaceLg),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: Color(state
                                          .notebookColor(note.notebookId)),
                                      shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(state.notebookName(note.notebookId),
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                                const SizedBox(width: spaceMd),
                                Text('更新于 ${formatRelative(note.updateAt)}',
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                              ],
                            ),
                          ),
                          MarkdownView(
                            content: note.content,
                            attachments: state.attachments,
                            onAttachmentLink: _openAttachment,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  TextStyle? _titleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge?.copyWith(
            fontFamily: serifFamily,
            fontFamilyFallback: cjkSerifFallback,
            fontSize: 22,
          );
}

String formatHm(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}';
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