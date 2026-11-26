import 'package:appflowy_editor/appflowy_editor.dart';

class RichtextMatch {
  const RichtextMatch(this.path, this.start, this.end);

  final List<int> path;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is RichtextMatch &&
      _samePath(other.path, path) &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(Object.hashAll(path), start, end);

  static bool _samePath(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

List<RichtextMatch> richtextFindMatches(
  Document document,
  String needle, {
  bool caseSensitive = false,
}) {
  if (needle.isEmpty) {
    return const [];
  }
  final matches = <RichtextMatch>[];
  final target = caseSensitive ? needle : needle.toLowerCase();
  void walk(Node node) {
    final delta = node.delta;
    if (delta != null) {
      final text = delta.toPlainText();
      final haystack = caseSensitive ? text : text.toLowerCase();
      var start = haystack.indexOf(target);
      while (start >= 0) {
        matches.add(RichtextMatch(node.path, start, start + needle.length));
        start = haystack.indexOf(target, start + needle.length);
      }
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  for (final child in document.root.children) {
    walk(child);
  }
  return matches;
}