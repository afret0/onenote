import 'dart:convert';

import 'package:markdown/markdown.dart';

class TaskCheckboxHoistSyntax extends BlockSyntax {
  const TaskCheckboxHoistSyntax(this.delegate);

  final BlockSyntax delegate;

  @override
  RegExp get pattern => delegate.pattern;

  @override
  Node? parse(BlockParser parser) {
    final node = delegate.parse(parser);
    _hoistCheckboxes(node);
    return node;
  }
}

const List<BlockSyntax> markdownTaskBlockSyntaxes = [
  TaskCheckboxHoistSyntax(UnorderedListWithCheckboxSyntax()),
  TaskCheckboxHoistSyntax(OrderedListWithCheckboxSyntax()),
];

void _hoistCheckboxes(Node? node) {
  if (node is! Element) {
    return;
  }
  final children = node.children;
  if (children == null) {
    return;
  }
  if (node.tag == 'li' && node.attributes['class'] == 'task-list-item') {
    final first = children.first;
    if (first is Element && first.tag == 'p') {
      final paragraphChildren = first.children;
      if (paragraphChildren != null && paragraphChildren.isNotEmpty) {
        final head = paragraphChildren.first;
        if (head is Element &&
            head.tag == 'input' &&
            head.attributes['type'] == 'checkbox') {
          paragraphChildren.removeAt(0);
          children.insert(0, head);
        }
      }
    }
  }
  for (final child in List<Node>.of(children)) {
    _hoistCheckboxes(child);
  }
}

Document _taskDocument() => Document(
      blockSyntaxes: markdownTaskBlockSyntaxes,
      extensionSet: ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );

List<bool> markdownTaskStates(String content) {
  final nodes = _taskDocument().parseLines(const LineSplitter().convert(content));
  final states = <bool>[];
  void walk(Node node) {
    if (node is! Element) {
      return;
    }
    for (final child in node.children ?? const <Node>[]) {
      walk(child);
    }
    if (node.tag != 'li') {
      return;
    }
    final children = node.children;
    if (children == null || children.isEmpty) {
      return;
    }
    final first = children.first;
    if (first is Element &&
        first.tag == 'input' &&
        first.attributes['type'] == 'checkbox') {
      states.add(first.attributes.containsKey('checked'));
    }
  }

  nodes.forEach(walk);
  return states;
}

final _taskLinePattern = RegExp(
  r'^[ \t]*(?:>[ \t]*)*(?:[-*+]|\d{1,9}[.)])[ \t]+\[([ xX])\][ \t]',
  multiLine: true,
);

int? markdownTaskMarkerPosition(String content, int ordinal) {
  final baseline = markdownTaskStates(content);
  if (ordinal < 0 || ordinal >= baseline.length) {
    return null;
  }
  for (final match in _taskLinePattern.allMatches(content)) {
    final position = match.start + match[0]!.indexOf('[') + 1;
    final states = markdownTaskStates(toggleMarkdownTaskAt(content, position));
    if (states.length != baseline.length) {
      continue;
    }
    var diffs = 0;
    var diffAt = -1;
    for (var i = 0; i < states.length; i++) {
      if (states[i] != baseline[i]) {
        diffs++;
        diffAt = i;
      }
    }
    if (diffs == 1 && diffAt == ordinal) {
      return position;
    }
  }
  return null;
}

String toggleMarkdownTaskAt(String content, int position) {
  final replacement = content[position] == ' ' ? 'x' : ' ';
  return content.replaceRange(position, position + 1, replacement);
}
