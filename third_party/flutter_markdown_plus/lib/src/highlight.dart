import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class MarkdownHighlightMatch {
  const MarkdownHighlightMatch(this.paragraphKey, this.offset);

  final GlobalKey paragraphKey;
  final int offset;
}

class MarkdownHighlightController extends ChangeNotifier {
  final List<MarkdownHighlightMatch> matches = <MarkdownHighlightMatch>[];

  void reset() {
    matches.clear();
    notifyListeners();
  }

  void recorded() => notifyListeners();

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