import 'package:markdown/markdown.dart' as md;

import 'attachment_store.dart';
import 'markdown_tasks.dart';

final RegExp _assetRefSource = RegExp(
    '!?\\[[^\\]]*\\]\\(${AttachmentStore.scheme}://([0-9a-f]{64})\\)');

bool isPdfLinkText(String text) => text.toLowerCase().endsWith('.pdf');

int _renderedRefCount(List<md.Node> nodes, String id) {
  var count = 0;
  for (final node in nodes) {
    if (node is! md.Element) {
      continue;
    }
    if (node.tag == 'img') {
      if (AttachmentStore.refPattern.firstMatch(node.attributes['src'] ?? '')
              ?.group(1) ==
          id) {
        count++;
      }
    } else if (node.tag == 'a') {
      if (AttachmentStore.refPattern.firstMatch(node.attributes['href'] ?? '')
              ?.group(1) ==
          id &&
          isPdfLinkText(node.textContent)) {
        count++;
      }
    }
    final children = node.children;
    if (children != null) {
      count += _renderedRefCount(children, id);
    }
  }
  return count;
}

int renderedAttachmentRefCount(String content, String id) => _renderedRefCount(
    md.Document(
            blockSyntaxes: markdownTaskBlockSyntaxes,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            encodeHtml: false)
        .parseLines(content.split('\n')),
    id);

Map<String, int> renderedAttachmentRefTotals(String content) {
  final totals = <String, int>{};
  for (final match in _assetRefSource.allMatches(content)) {
    final id = match.group(1)!;
    if (!totals.containsKey(id)) {
      final count = renderedAttachmentRefCount(content, id);
      if (count > 0) {
        totals[id] = count;
      }
    }
  }
  return totals;
}

String? removeAttachmentRefAt(String content, String id, int ordinal) {
  final total = renderedAttachmentRefCount(content, id);
  if (ordinal < 0 || ordinal >= total) {
    return null;
  }
  final lines = content.split('\n');
  var rendered = 0;
  for (final match in _assetRefSource.allMatches(content)) {
    if (match.group(1) != id) {
      continue;
    }
    final startLine = '\n'.allMatches(content.substring(0, match.start)).length;
    final endLine = '\n'.allMatches(content.substring(0, match.end)).length;
    final without = content.replaceRange(match.start, match.end, '');
    if (renderedAttachmentRefCount(without, id) != total - 1) {
      continue;
    }
    if (rendered == ordinal) {
      if (startLine == endLine &&
          lines[startLine].trim() == match.group(0)!.trim()) {
        lines.removeAt(startLine);
        if (startLine < lines.length &&
            lines[startLine].trim().isEmpty &&
            (startLine == 0 || lines[startLine - 1].trim().isEmpty)) {
          lines.removeAt(startLine);
        } else if (startLine == lines.length &&
            lines.isNotEmpty &&
            lines.last.trim().isEmpty) {
          lines.removeLast();
        }
        return lines.join('\n');
      }
      return without;
    }
    rendered++;
  }
  return null;
}

class AttachmentRefCounter {
  AttachmentRefCounter(this.totals);

  final Map<String, int> totals;
  final Map<String, int> _calls = {};

  int next(String id) {
    final total = totals[id] ?? 1;
    final call = _calls[id] ?? 0;
    _calls[id] = call + 1;
    return call % total;
  }
}