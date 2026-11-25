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
    final RenderObject? render = context.findRenderObject();
    if (render is! RenderParagraph) {
      return null;
    }
    final Offset local = render.getOffsetForCaret(
      TextPosition(offset: match.offset),
      Rect.zero,
    );
    return render.localToGlobal(local);
  }
}