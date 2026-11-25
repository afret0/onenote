import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class MarkdownHighlightMatch {
  const MarkdownHighlightMatch(this.paragraphKey, this.offset);

  final GlobalKey paragraphKey;
  final int offset;
}

class MarkdownHighlightController extends ChangeNotifier {
  final List<MarkdownHighlightMatch> matches = <MarkdownHighlightMatch>[];
  final List<GlobalKey> _paragraphKeys = <GlobalKey>[];
  List<MarkdownHighlightMatch> _notified = const <MarkdownHighlightMatch>[];

  GlobalKey paragraphKey(int ordinal) {
    while (_paragraphKeys.length <= ordinal) {
      _paragraphKeys.add(GlobalKey());
    }
    return _paragraphKeys[ordinal];
  }

  void reset() {
    matches.clear();
  }

  void recorded() {
    if (matches.length == _notified.length) {
      bool same = true;
      for (int i = 0; i < matches.length; i++) {
        if (!identical(matches[i].paragraphKey, _notified[i].paragraphKey) ||
            matches[i].offset != _notified[i].offset) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
    }
    _notified = List<MarkdownHighlightMatch>.of(matches);
    notifyListeners();
  }

  Offset? globalOffset(int index) {
    if (index < 0 || index >= matches.length) {
      return null;
    }
    final MarkdownHighlightMatch match = matches[index];
    final BuildContext? context = match.paragraphKey.currentContext;
    if (context == null) {
      return null;
    }
    final RenderObject? root = context.findRenderObject();
    if (root == null) {
      return null;
    }
    RenderObject? textRender;
    void visit(RenderObject node) {
      if (textRender != null) {
        return;
      }
      if (node is RenderParagraph || node is RenderEditable) {
        textRender = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(root);
    final RenderObject? render = textRender;
    if (render is! RenderBox) {
      return null;
    }
    final TextPosition position = TextPosition(offset: match.offset);
    final Offset local = render is RenderParagraph
        ? render.getOffsetForCaret(position, Rect.zero)
        : (render as RenderEditable).getLocalRectForCaret(position).topLeft;
    return render.localToGlobal(local);
  }
}