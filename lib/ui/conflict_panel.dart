import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showConflictPanel(BuildContext context,
    {required AppState state, required String noteId}) async {
  final payload = await state.conflictPayload(noteId);
  if (payload == null) {
    developer.log('skip, 冲突已被裁决无需打开面板, noteId: $noteId');
    return;
  }
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) =>
        ConflictPanel(state: state, noteId: noteId, payload: payload),
  );
}

class ConflictPanel extends StatefulWidget {
  const ConflictPanel({
    super.key,
    required this.state,
    required this.noteId,
    required this.payload,
  });

  final AppState state;
  final String noteId;
  final Map<String, dynamic> payload;

  @override
  State<ConflictPanel> createState() => _ConflictPanelState();
}

class _ConflictPanelState extends State<ConflictPanel> {
  late final List<Map<String, dynamic>> _segments = [
    for (final raw in (widget.payload['segments'] as List))
      raw as Map<String, dynamic>,
  ];
  late final List<bool> _pickLocal = [
    for (final segment in _segments)
      if (segment['conflict'] == true) true,
  ];
  bool _resolving = false;

  AppState get state => widget.state;

  int get _conflictCount => _pickLocal.length;

  Future<void> _resolve() async {
    setState(() => _resolving = true);
    await state.resolveConflict(widget.noteId, List<bool>.from(_pickLocal));
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('冲突已合并保存')));
  }

  void _pickAll(bool local) {
    setState(() {
      for (var i = 0; i < _pickLocal.length; i++) {
        _pickLocal[i] = local;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final remoteMeta =
        widget.payload['remoteMeta'] as Map<String, dynamic>? ?? {};
    final remoteDevice =
        (remoteMeta['deviceName'] as String? ?? '').trim().isEmpty
            ? '其他设备'
            : remoteMeta['deviceName'] as String;
    final remoteAt = remoteMeta['updateAt'] as int? ?? 0;
    final localAt = widget.payload['localUpdateAt'] as int? ?? 0;
    var conflictIndex = 0;
    return Dialog(
      backgroundColor: t.surface,
      insetPadding: const EdgeInsets.all(spaceLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(spaceLg, spaceLg, spaceLg, 0),
              child: Row(
                children: [
                  Icon(Icons.sync_problem, color: t.danger, size: 20),
                  const SizedBox(width: spaceSm),
                  Expanded(
                    child: Text('同步冲突裁决',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text('共 $_conflictCount 处，逐块选择保留哪一侧',
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(spaceLg, spaceXs, spaceLg, 0),
              child: Text(
                '本机 ${formatDateTime(localAt)} · $remoteDevice ${remoteAt == 0 ? '' : formatDateTime(remoteAt)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: spaceSm),
            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsets.fromLTRB(spaceLg, spaceSm, spaceLg, spaceSm),
                itemCount: _segments.length,
                separatorBuilder: (_, _) => const SizedBox(height: spaceSm),
                itemBuilder: (context, index) {
                  final segment = _segments[index];
                  if (segment['conflict'] != true) {
                    return _stablePreview(t, segment['text'] as String? ?? '');
                  }
                  final pickIndex = conflictIndex++;
                  return _conflictBlock(
                    t,
                    pickIndex,
                    segment['local'] as String? ?? '',
                    segment['remote'] as String? ?? '',
                    remoteDevice,
                  );
                },
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.hairline)),
              ),
              padding: const EdgeInsets.all(spaceMd),
              child: Row(
                children: [
                  TextButton(
                    onPressed:
                        _resolving ? null : () => _pickAll(true),
                    child: const Text('全部用本机'),
                  ),
                  TextButton(
                    onPressed:
                        _resolving ? null : () => _pickAll(false),
                    child: const Text('全部用远端'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _resolving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('稍后裁决'),
                  ),
                  const SizedBox(width: spaceSm),
                  FilledButton(
                    onPressed: _resolving ? null : _resolve,
                    child: Text(_resolving ? '合并中…' : '确认合并'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stablePreview(InkTokens t, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }
    final preview = trimmed.length <= 80
        ? trimmed
        : '${trimmed.substring(0, 40)} … ${trimmed.substring(trimmed.length - 30)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(spaceSm),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      child: Text(
        '一致内容 · ${trimmed.length} 字 · $preview',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: t.inkMuted),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _conflictBlock(InkTokens t, int pickIndex, String local, String remote,
      String remoteDevice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: spaceXs),
          child: Text('冲突块 ${pickIndex + 1}/$_conflictCount',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: t.accentText)),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _sideCard(
                t,
                title: '本机',
                text: local,
                selected: _pickLocal[pickIndex],
                onTap: () => setState(() => _pickLocal[pickIndex] = true),
              ),
            ),
            const SizedBox(width: spaceSm),
            Expanded(
              child: _sideCard(
                t,
                title: remoteDevice,
                text: remote,
                selected: !_pickLocal[pickIndex],
                onTap: () => setState(() => _pickLocal[pickIndex] = false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sideCard(InkTokens t,
      {required String title,
      required String text,
      required bool selected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: _resolving ? null : onTap,
      child: AnimatedContainer(
        duration: motionFast,
        padding: const EdgeInsets.all(spaceMd),
        decoration: BoxDecoration(
          color: selected ? t.accentSoft : t.surface,
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(
            color: selected ? t.accent : t.hairline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                  color: selected ? t.accentText : t.inkMuted,
                ),
                const SizedBox(width: spaceXs),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                              color: selected ? t.accentText : t.inkMuted)),
                ),
              ],
            ),
            const SizedBox(height: spaceSm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: SelectableText(
                  text.isEmpty ? '（删除了这段内容）' : text,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.7,
                    color: t.ink,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}