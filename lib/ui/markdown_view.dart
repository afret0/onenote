import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../data/attachment_refs.dart';
import '../data/attachment_store.dart';
import '../data/markdown_tasks.dart';
import 'attachment_image.dart';
import 'attachment_link.dart';
import 'clip_page_view.dart';
import 'theme.dart';

class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.content,
    this.attachments,
    this.onAttachmentLink,
    this.onAttachmentPdfTap,
    this.onAttachmentImageTap,
    this.onAttachmentContext,
    this.onToggleTask,
    this.browserLauncherOverride,
    this.highlightQuery,
    this.highlightActiveIndex = -1,
    this.highlightController,
    this.tocController,
    this.tint,
  });

  final String content;
  final AttachmentStore? attachments;
  final void Function(String id)? onAttachmentLink;
  final void Function(String id, int ordinal)? onAttachmentPdfTap;
  final void Function(String id, int ordinal, Uint8List bytes)?
      onAttachmentImageTap;
  final void Function(String id, int ordinal, Offset position)?
      onAttachmentContext;
  final void Function(int ordinal)? onToggleTask;
  final Future<void> Function(String url)? browserLauncherOverride;
  final String? highlightQuery;
  final int highlightActiveIndex;
  final MarkdownHighlightController? highlightController;
  final MarkdownTocController? tocController;
  final Color? tint;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  MarkdownStyleSheet? _sheet;
  InkTokens? _sheetTokens;
  double _sheetScale = -1;
  Color? _sheetTint;
  String? _taskContent;
  List<bool> _taskStates = const [];
  String? _refContent;
  Map<String, int> _refTotals = const {};
  final GlobalKey _bodyKey = GlobalKey();
  int _pointerButtons = 0;
  bool _suppressContextMenu = false;
  bool _openModifier = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_syncOpenModifier);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_syncOpenModifier);
    super.dispose();
  }

  bool _syncOpenModifier(KeyEvent event) {
    final mac = kIsWeb
        ? defaultTargetPlatform == TargetPlatform.macOS
        : Platform.isMacOS;
    final pressed = mac
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (pressed != _openModifier) {
      setState(() => _openModifier = pressed);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final content = widget.content;
    if (content.trim().isEmpty) {
      return Text('这篇笔记还没有内容，点「编辑」开始书写。',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: t.inkFaint));
    }
    final contentScale = t.noteFontSize * t.fontScale / 16;
    if (_sheet == null ||
        !identical(_sheetTokens, t) ||
        _sheetScale != contentScale ||
        _sheetTint != widget.tint) {
      final tint = widget.tint;
      final accentFill =
          tint == null ? t.accent : readableOn(tint, t.paper, ratio: 3);
      final accentInk =
          tint == null ? t.accentText : readableOn(tint, t.paper);
      final headingSerif = TextStyle(
        fontFamily: serifFamily,
        fontFamilyFallback: cjkSerifFallback,
        color: t.ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      );
      final body = TextStyle(
        fontFamily: t.sans,
        fontFamilyFallback: cjkSansFallback,
        fontSize: 16 * contentScale,
        height: 1.8,
        color: t.ink,
      );
      final mono = TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: cjkMonoFallback,
        fontSize: 13.5 * contentScale,
        height: 1.6,
        color: t.ink,
      );
      _sheet = MarkdownStyleSheet(
        p: body,
        blockSpacing: 14,
        h1: headingSerif.copyWith(fontSize: 30 * contentScale, height: 1.3),
        h2: headingSerif.copyWith(fontSize: 24 * contentScale, height: 1.35),
        h3: headingSerif.copyWith(fontSize: 20 * contentScale, height: 1.4),
        h4: headingSerif.copyWith(fontSize: 17 * contentScale, height: 1.4),
        h1Padding: const EdgeInsets.only(top: spaceSm, bottom: spaceMd),
        h2Padding: const EdgeInsets.only(top: spaceMd, bottom: spaceSm),
        h3Padding: const EdgeInsets.only(top: spaceMd, bottom: spaceSm),
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(
            color: accentInk, decoration: TextDecoration.underline),
        blockquote: body.copyWith(color: t.inkMuted),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: accentFill, width: 3)),
          color: t.surfaceAlt.withValues(alpha: 0.5),
        ),
        blockquotePadding:
            const EdgeInsets.symmetric(horizontal: spaceMd, vertical: spaceSm),
        code: mono.copyWith(
            backgroundColor: t.surfaceAlt, fontSize: 13 * contentScale),
        codeblockDecoration: BoxDecoration(
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(radiusMd),
          border: Border.all(color: t.hairline),
        ),
        codeblockPadding: const EdgeInsets.all(spaceMd),
        codeblockAlign: WrapAlignment.start,
        listBullet: body.copyWith(color: accentFill),
        listIndent: 28,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline, width: 1)),
        ),
        tableHead: body.copyWith(fontWeight: FontWeight.w700),
        tableBody: body,
        tableBorder: TableBorder.all(color: t.hairline, width: 1),
        tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: spaceSm + 4, vertical: spaceSm),
        tableCellsDecoration: BoxDecoration(color: t.surface),
        checkbox: body.copyWith(color: accentFill),
      );
      _sheetTokens = t;
      _sheetScale = contentScale;
      _sheetTint = tint;
    }
    final sheet = _sheet!;
    if (!identical(_taskContent, content)) {
      _taskStates = markdownTaskStates(content);
      _taskContent = content;
    }
    final store = widget.attachments;
    final MouseCursor? linkCursor =
        _openModifier ? SystemMouseCursors.click : null;
    int Function(String href, String text)? linkOrdinal;
    Map<String, MarkdownElementBuilder>? attachmentBuilders;
    if (store != null) {
      if (!identical(_refContent, content)) {
        _refTotals = content.contains('${AttachmentStore.scheme}://')
            ? renderedAttachmentRefTotals(content)
            : const {};
        _refContent = content;
      }
      final counter = AttachmentRefCounter(_refTotals);
      linkOrdinal = (href, text) {
        final m = AttachmentStore.refPattern.firstMatch(href);
        if (m == null || isPdfLinkText(text)) {
          return -1;
        }
        return counter.next(m.group(1)!);
      };
      final imageTap = widget.onAttachmentImageTap;
      final onContext = widget.onAttachmentContext;
      final pdfTap = widget.onAttachmentPdfTap;
      attachmentBuilders = {
        'img': AttachmentImageBuilder(store,
            refCounter: counter, onTap: imageTap, onContext: onContext),
        'a': _ChainLinkBuilder([
          if (onContext != null && pdfTap != null)
            AttachmentLinkBuilder(
                store: store, refCounter: counter, mouseCursor: linkCursor),
          ClipPageLinkBuilder(store, onOpenExternal: widget.onAttachmentLink),
        ]),
      };
    }
    final toggle = widget.onToggleTask;
    final taskCount = toggle == null ? 0 : _taskStates.length;
    final lineHeight = sheet.p!.fontSize! * sheet.p!.height!;
    var checkboxCalls = 0;
    return Listener(
      onPointerDown: (e) => _pointerButtons = e.buttons,
      onPointerUp: _onPointerUp,
      child: KeyedSubtree(
        key: _bodyKey,
        child: MarkdownBody(
      data: content,
      selectable: true,
      fitContent: false,
      linkRefOrdinal: linkOrdinal,
      linkMouseCursor: linkCursor,
      contextMenuBuilder: _contextMenu,
      highlightQuery: widget.highlightQuery,
      highlightColor: widget.highlightQuery == null ? null : t.searchMark,
      highlightActiveIndex: widget.highlightActiveIndex,
      highlightActiveColor:
          widget.highlightQuery == null ? null : t.searchActive,
      highlightActiveInk:
          widget.highlightQuery == null ? null : t.searchActiveInk,
      highlightController: widget.highlightController,
      tocController: widget.tocController,
      blockSyntaxes: markdownTaskBlockSyntaxes,
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
      checkboxBuilder: (checked) {
        if (toggle == null || taskCount == 0) {
          return _TaskCheckbox(
              checked: checked, lineHeight: lineHeight, tint: widget.tint);
        }
        final ordinal = checkboxCalls++ % taskCount;
        return _TaskCheckbox(
          checked: checked,
          lineHeight: lineHeight,
          onTap: () => toggle(ordinal),
          tint: widget.tint,
        );
      },
      builders: attachmentBuilders ?? const {},
      styleSheet: sheet,
      onTapLink: (text, href, title) {
        if (href == null) {
          return;
        }
        final match = AttachmentStore.refPattern.firstMatch(href);
        if (match != null) {
          widget.onAttachmentLink?.call(match.group(1)!);
          return;
        }
        if (_openInBrowser(href)) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(href)));
      },
        ),
      ),
    );
  }

  Widget _contextMenu(BuildContext context, EditableTextState state) {
    if (_suppressContextMenu) {
      return const SizedBox.shrink();
    }
    return AdaptiveTextSelectionToolbar.editableText(editableTextState: state);
  }

  void _releaseSuppress() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _suppressContextMenu = false;
        }
      });
    });
  }

  void _onPointerUp(PointerUpEvent e) {
    final buttons = _pointerButtons;
    _pointerButtons = 0;
    final link = _linkAt(e.position);
    if (buttons == kSecondaryButton) {
      final href = link?.href;
      if (link == null || href == null) {
        return;
      }
      _suppressContextMenu = true;
      _releaseSuppress();
      final match = AttachmentStore.refPattern.firstMatch(href);
      if (match != null) {
        widget.onAttachmentContext
            ?.call(match.group(1)!, link.refOrdinal, e.position);
        return;
      }
      _showWebLinkMenu(href, e.position);
      return;
    }
    if (buttons == kPrimaryButton) {
      final pressed = Platform.isMacOS
          ? HardwareKeyboard.instance.isMetaPressed
          : HardwareKeyboard.instance.isControlPressed;
      final href = link?.href;
      if (!pressed || link == null || href == null) {
        return;
      }
      final match = AttachmentStore.refPattern.firstMatch(href);
      if (match != null) {
        final id = match.group(1)!;
        if (isPdfLinkText(link.toPlainText().replaceAll(RegExp(r'[\uFFFC]'), ''))) {
          widget.onAttachmentPdfTap?.call(id, link.refOrdinal);
        } else {
          widget.onAttachmentLink?.call(id);
        }
        return;
      }
      if (!_launchBrowser(href)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(href)));
      }
    }
  }

  Future<void> _showWebLinkMenu(String href, Offset pos) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'open', child: Text('打开')),
        PopupMenuItem(value: 'copy', child: Text('复制链接')),
      ],
    );
    if (!mounted || value == null) {
      return;
    }
    if (value == 'open') {
      if (!_launchBrowser(href)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(href)));
      }
    } else if (value == 'copy') {
      await Clipboard.setData(ClipboardData(text: href));
    }
  }

  MarkdownLinkSpan? _linkAt(Offset global) {
    final root = _bodyKey.currentContext?.findRenderObject();
    if (root == null) {
      return null;
    }
    MarkdownLinkSpan? found;
    void visit(RenderObject node) {
      if (found != null) {
        return;
      }
      if (node is RenderParagraph) {
        final local = node.globalToLocal(global);
        if (local.dx >= 0 &&
            local.dy >= 0 &&
            local.dx <= node.size.width &&
            local.dy <= node.size.height) {
          final pos = node.getPositionForOffset(local);
          found = _findLinkSpan(node.text, pos.offset, 0, null);
        }
      } else if (node is RenderEditable) {
        final local = node.globalToLocal(global);
        if (local.dx >= 0 &&
            local.dy >= 0 &&
            local.dx <= node.size.width &&
            local.dy <= node.size.height) {
          final pos = node.getPositionForPoint(global);
          found = _findLinkSpan(node.text ?? const TextSpan(), pos.offset, 0, null);
        }
      }
      node.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  MarkdownLinkSpan? _findLinkSpan(
      InlineSpan node, int offset, int base, MarkdownLinkSpan? link) {
    final nextLink = node is MarkdownLinkSpan ? node : link;
    if (node is TextSpan && node.children == null) {
      final text = node.text ?? '';
      if (offset >= base && offset < base + text.length) {
        return nextLink;
      }
      return null;
    }
    if (node is TextSpan) {
      var cur = base;
      for (final child in node.children!) {
        final hit = _findLinkSpan(child, offset, cur, nextLink);
        if (hit != null) {
          return hit;
        }
        cur += child.toPlainText().length;
      }
      return null;
    }
    if (offset >= base && offset < base + node.toPlainText().length) {
      return nextLink;
    }
    return null;
  }

  bool _launchBrowser(String href) {
    if (kIsWeb) {
      return false;
    }
    final uri = Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final override = widget.browserLauncherOverride;
    if (override != null) {
      override(href);
    } else if (Platform.isMacOS) {
      Process.run('open', [href]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [href]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', href]);
    } else {
      return false;
    }
    return true;
  }

  bool _openInBrowser(String href) {
    if (kIsWeb) {
      return false;
    }
    final pressed = Platform.isMacOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (!pressed) {
      return false;
    }
    final uri = Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final override = widget.browserLauncherOverride;
    if (override != null) {
      override(href);
    } else if (Platform.isMacOS) {
      Process.run('open', [href]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [href]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', href]);
    } else {
      return false;
    }
    return true;
  }
}

class _TaskCheckbox extends StatefulWidget {
  const _TaskCheckbox({
    required this.checked,
    required this.lineHeight,
    this.onTap,
    this.tint,
  });

  final bool checked;
  final double lineHeight;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  State<_TaskCheckbox> createState() => _TaskCheckboxState();
}

class _TaskCheckboxState extends State<_TaskCheckbox> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final interactive = widget.onTap != null;
    final tint = widget.tint;
    final fill =
        tint == null ? t.accent : readableOn(tint, t.paper, ratio: 3);
    final hover =
        tint == null ? t.accentText : readableOn(tint, t.paper);
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: SizedBox(
            width: 28,
            height: widget.lineHeight,
            child: Center(
              child: Opacity(
                opacity: _pressed ? 0.7 : 1,
                child: Icon(
                  widget.checked
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 20,
                  color: interactive && _hover ? hover : fill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _ChainLinkBuilder extends MarkdownElementBuilder {
  _ChainLinkBuilder(this._chain);

  final List<MarkdownElementBuilder> _chain;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    for (final builder in _chain) {
      final built = builder.visitElementAfterWithContext(
          context, element, preferredStyle, parentStyle);
      if (built != null) {
        return built;
      }
    }
    return null;
  }
}
