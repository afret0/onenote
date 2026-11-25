import 'package:flutter/widgets.dart';

class MarkdownTocEntry {
  const MarkdownTocEntry(this.key, this.level, this.text);

  final GlobalKey key;
  final int level;
  final String text;
}

class MarkdownTocController extends ChangeNotifier {
  final List<GlobalKey> _keys = <GlobalKey>[];
  List<MarkdownTocEntry> _entries = const <MarkdownTocEntry>[];
  List<MarkdownTocEntry> _building = <MarkdownTocEntry>[];

  List<MarkdownTocEntry> get entries => _entries;

  void beginBuild() {
    _building = <MarkdownTocEntry>[];
  }

  GlobalKey recordHeading(int level, String text) {
    final int ordinal = _building.length;
    while (_keys.length <= ordinal) {
      _keys.add(GlobalKey());
    }
    final GlobalKey key = _keys[ordinal];
    _building.add(MarkdownTocEntry(key, level, text));
    return key;
  }

  void endBuild() {
    if (_sameEntries(_entries, _building)) {
      return;
    }
    _entries = List<MarkdownTocEntry>.of(_building);
    notifyListeners();
  }

  static bool _sameEntries(
      List<MarkdownTocEntry> a, List<MarkdownTocEntry> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (!identical(a[i].key, b[i].key) ||
          a[i].level != b[i].level ||
          a[i].text != b[i].text) {
        return false;
      }
    }
    return true;
  }
}