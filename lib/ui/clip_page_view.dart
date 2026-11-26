import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';

import '../clip/mhtml_html.dart';
import '../data/attachment_store.dart';
import 'theme.dart';

bool get clipPageEmbedSupported =>
    !kIsWeb &&
    !Platform.environment.containsKey('FLUTTER_TEST') &&
    (Platform.isMacOS || Platform.isAndroid);

bool isClipPageLinkText(String text) {
  final lower = text.toLowerCase();
  return lower.endsWith('.mhtml') || lower.endsWith('.html');
}

class ClipPageLinkBuilder extends MarkdownElementBuilder {
  ClipPageLinkBuilder(this.store, {this.onOpenExternal});

  final AttachmentStore store;
  final void Function(String id)? onOpenExternal;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (!clipPageEmbedSupported) {
      return null;
    }
    final href = element.attributes['href'] ?? '';
    final match = AttachmentStore.refPattern.firstMatch(href);
    if (match == null) {
      return null;
    }
    final text = element.textContent;
    if (!isClipPageLinkText(text)) {
      return null;
    }
    return ClipPageEmbed(
      store: store,
      id: match.group(1)!,
      name: text,
      onOpenExternal: onOpenExternal,
    );
  }
}

class ClipPageEmbed extends StatefulWidget {
  const ClipPageEmbed({
    super.key,
    required this.store,
    required this.id,
    required this.name,
    this.onOpenExternal,
  });

  final AttachmentStore store;
  final String id;
  final String name;
  final void Function(String id)? onOpenExternal;

  @override
  State<ClipPageEmbed> createState() => _ClipPageEmbedState();
}

class _ClipPageEmbedState extends State<ClipPageEmbed> {
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ClipPageEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _controller = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.id;
    try {
      final bytes = await widget.store.read(id);
      if (!mounted || id != widget.id) {
        return;
      }
      if (bytes == null) {
        setState(() => _error = '附件不存在或已被清理');
        return;
      }
      final name = await widget.store.nameOf(id) ?? widget.name;
      final html = name.toLowerCase().endsWith('.mhtml')
          ? convertMhtmlToHtml(bytes)
          : utf8.decode(bytes, allowMalformed: true);
      if (!mounted || id != widget.id) {
        return;
      }
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.prevent,
        ));
      if (!Platform.isMacOS) {
        controller.setBackgroundColor(inkOf(context).paper);
      }
      await controller.loadHtmlString(html, baseUrl: 'about:blank');
      if (!mounted || id != widget.id) {
        return;
      }
      setState(() => _controller = controller);
    } catch (err) {
      if (mounted && id == widget.id) {
        setState(() => _error = '页面解析失败：$err');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    final height = MediaQuery.sizeOf(context).height * 0.6;
    Widget child;
    if (_error != null) {
      child = Center(
        child: Text(_error!, style: TextStyle(color: t.inkMuted, fontSize: 14)),
      );
    } else if (_controller == null) {
      child = const Center(child: CircularProgressIndicator());
    } else {
      child = WebViewWidget(controller: _controller!);
    }
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: spaceSm),
      decoration: BoxDecoration(
        border: Border.all(color: t.hairline),
        borderRadius: BorderRadius.circular(spaceSm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                const SizedBox(width: spaceSm),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.inkMuted, fontSize: 13),
                  ),
                ),
                if (widget.onOpenExternal != null)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => widget.onOpenExternal!(widget.id),
                    ),
                  ),
                const SizedBox(width: spaceSm - 4),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}