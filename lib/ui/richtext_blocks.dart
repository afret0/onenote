import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/attachment_store.dart';
import '../richtext/markdown_codec.dart';
import 'theme.dart';

Map<String, BlockComponentBuilder> richtextBlockBuilders({
  required InkTokens tokens,
  required double noteFontSize,
  required AttachmentStore? attachments,
  required void Function(String id) onOpenAsset,
  required void Function(String id, Offset position) onAssetContext,
}) {
  final monoStyle = TextStyle(
    fontFamily: monoFamily,
    fontSize: noteFontSize,
    color: tokens.ink,
    height: 1.6,
  );
  return {
    ...standardBlockComponentBuilderMap,
    richtextCodeBlockType: ParagraphBlockComponentBuilder(
      configuration: BlockComponentConfiguration(
        padding: (node) => const EdgeInsets.symmetric(
            horizontal: spaceMd, vertical: spaceSm),
        textStyle: (node, {textSpan}) => monoStyle,
      ),
    ),
    ImageBlockKeys.type: _AssetImageBlockBuilder(
      attachments: attachments,
      onOpenAsset: onOpenAsset,
      onAssetContext: onAssetContext,
    ),
  };
}

List<CharacterShortcutEvent> richtextCharacterShortcuts() {
  return [
    for (final event in standardCharacterShortcutEvents)
      event.copyWith(
        handler: (editorState) async {
          final selection = editorState.selection;
          if (selection != null) {
            final node = editorState.getNodeAtPath(selection.end.path);
            if (node != null && node.type == richtextCodeBlockType) {
              return false;
            }
          }
          return event.handler(editorState);
        },
      ),
  ];
}

class _AssetImageBlockBuilder extends BlockComponentBuilder {
  _AssetImageBlockBuilder({
    required this.attachments,
    required this.onOpenAsset,
    required this.onAssetContext,
  });

  final AttachmentStore? attachments;
  final void Function(String id) onOpenAsset;
  final void Function(String id, Offset position) onAssetContext;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return _AssetImageBlockWidget(
      key: node.key,
      node: node,
      attachments: attachments,
      onOpenAsset: onOpenAsset,
      onAssetContext: onAssetContext,
      configuration: configuration,
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta == null && node.children.isEmpty;
}

class _AssetImageBlockWidget extends BlockComponentStatefulWidget {
  const _AssetImageBlockWidget({
    super.key,
    required super.node,
    required this.attachments,
    required this.onOpenAsset,
    required this.onAssetContext,
    super.configuration = const BlockComponentConfiguration(),
  });

  final AttachmentStore? attachments;
  final void Function(String id) onOpenAsset;
  final void Function(String id, Offset position) onAssetContext;

  @override
  State<_AssetImageBlockWidget> createState() => _AssetImageBlockWidgetState();
}

class _AssetImageBlockWidgetState extends State<_AssetImageBlockWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final imageKey = GlobalKey();
  Future<Uint8List?>? _bytes;
  String? _loadedId;

  late final editorState = Provider.of<EditorState>(context, listen: false);

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  String get _url => node.attributes[ImageBlockKeys.url] as String? ?? '';

  String? get _assetId {
    final match = AttachmentStore.refPattern.firstMatch(_url);
    return match?.group(1);
  }

  void _ensureLoaded() {
    final id = _assetId;
    if (id == null || id == _loadedId) {
      return;
    }
    _loadedId = id;
    final store = widget.attachments;
    _bytes = store == null ? Future.value(null) : store.read(id);
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    final t = inkOf(context);
    final id = _assetId;
    Widget child;
    if (id == null) {
      child = _placeholder(t, '图片地址无效');
    } else {
      child = FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return _placeholder(
                t, snapshot.connectionState == ConnectionState.done ? '附件不存在' : '加载中…');
          }
          return GestureDetector(
            onTap: () => widget.onOpenAsset(id),
            onSecondaryTapUp: (d) =>
                widget.onAssetContext(id, d.globalPosition),
            onLongPressStart: (d) =>
                widget.onAssetContext(id, d.globalPosition),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          );
        },
      );
    }
    child = Padding(key: imageKey, padding: padding, child: child);
    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );
    return child;
  }

  Widget _placeholder(InkTokens t, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(spaceMd),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: t.hairline),
      ),
      child: Text(message,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: t.inkMuted)),
    );
  }

  @override
  Position start() => Position(path: node.path, offset: 0);

  @override
  Position end() => Position(path: node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) {
      return Offset.zero & imageBox.size;
    }
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(Position position,
      {bool shiftWithBaseOffset = false}) {
    if (_renderBox == null) {
      return null;
    }
    final size = _renderBox!.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }

  @override
  List<Rect> getRectsInSelection(Selection selection,
      {bool shiftWithBaseOffset = false}) {
    if (_renderBox == null) {
      return [];
    }
    final parentBox = context.findRenderObject();
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && imageBox is RenderBox) {
      return [
        imageBox.localToGlobal(Offset.zero, ancestor: parentBox) & imageBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);
}