import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

const richtextCodeBlockType = 'code';
const richtextImageAltKey = 'alt';

Document richtextDecode(String markdown) {
  final document = AppFlowyEditorMarkdownCodec(
    markdownParsers: [
      const _CodeBlockMarkdownParser(),
      const _ImageWithAltMarkdownParser(),
      const MarkdownParagraphParserV2(),
      const MarkdownHeadingParserV2(),
      const MarkdownTodoListParserV2(),
      const MarkdownUnorderedListParserV2(),
      const MarkdownOrderedListParserV2(),
      const MarkdownUnorderedListItemParserV2(),
      const MarkdownOrderedListItemParserV2(),
      const MarkdownBlockQuoteParserV2(),
      const MarkdownTableListParserV2(),
      const MarkdownDividerParserV2(),
      const MarkdownImageParserV2(),
      const _FallbackMarkdownParser(),
    ],
  ).decode(markdown);
  if (document.root.children.isEmpty) {
    document.insert([0], [paragraphNode()]);
  }
  return document;
}

String richtextEncode(Document document) => _RichtextDocumentEncoder(
      parsers: [
        const _DashBulletedListNodeParser(),
        const _NumberedListNodeParser(),
        const _ImageWithAltNodeParser(),
        const TextNodeParser(),
        const TodoListNodeParser(),
        const _QuoteNodeParser(),
        const CodeBlockNodeParser(),
        const HeadingNodeParser(),
        const TableNodeParser(),
        const DividerNodeParser(),
      ],
    ).convert(document);

String richtextNormalize(String markdown) =>
    richtextEncode(richtextDecode(markdown));

const _knownTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ul', 'ol', 'li', 'blockquote', 'pre', 'code', 'hr',
  'img', 'a', 'em', 'strong', 'del', 'u', 'br', 'input',
  'table', 'thead', 'tbody', 'tr', 'th', 'td', 'formula',
};

final _htmlTagPattern = RegExp(r'</?([a-zA-Z][a-zA-Z0-9-]*)(?:\s[^<>]*)?/?>');
const _supportedHtmlTags = {'u'};

List<String> richtextLossyParts(String markdown) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parse(markdown);
  final found = <String>{};
  void walk(md.Node node) {
    if (node is md.UnparsedContent) {
      found.add('HTML 块');
      return;
    }
    if (node is md.Text) {
      for (final match in _htmlTagPattern.allMatches(node.text)) {
        final tag = match.group(1)!.toLowerCase();
        if (!_supportedHtmlTags.contains(tag)) {
          found.add('HTML <$tag>');
        }
      }
      return;
    }
    if (node is md.Element) {
      if (node.tag == 'code' || node.tag == 'pre') {
        return;
      }
      if (!_knownTags.contains(node.tag)) {
        found.add('HTML <${node.tag}>');
      }
      for (final child in node.children ?? const <md.Node>[]) {
        walk(child);
      }
    }
  }

  for (final node in nodes) {
    walk(node);
  }
  return found.toList();
}

const _listTypes = {
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  TodoListBlockKeys.type,
};

class _RichtextDocumentEncoder extends DocumentMarkdownEncoder {
  _RichtextDocumentEncoder({required super.parsers});

  @override
  String convert(Document input) => _join(input.root.children.toList());

  @override
  String convertNodes(List<Node> nodes, {bool withIndent = false}) {
    final result = _join(nodes);
    if (result.isNotEmpty && withIndent) {
      return result
          .split('\n')
          .map((e) => e.isNotEmpty ? '\t$e' : e)
          .join('\n');
    }
    return result;
  }

  String _join(List<Node> nodes) {
    final buffer = StringBuffer();
    Node? prev;
    for (final node in nodes) {
      if (node.type == ParagraphBlockKeys.type &&
          (node.delta?.toPlainText() ?? '').isEmpty &&
          node.children.isEmpty) {
        continue;
      }
      NodeParser? parser;
      for (final candidate in parsers) {
        if (candidate.id == node.type) {
          parser = candidate;
          break;
        }
      }
      if (parser == null) {
        continue;
      }
      final core =
          parser.transform(node, this).replaceFirst(RegExp(r'\n+$'), '');
      if (core.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.write(prev!.type == node.type && _listTypes.contains(node.type)
            ? '\n'
            : '\n\n');
      }
      buffer.write(core);
      prev = node;
    }
    if (buffer.isEmpty) {
      return '';
    }
    return '$buffer\n';
  }
}

class _CodeBlockMarkdownParser extends CustomMarkdownParser {
  const _CodeBlockMarkdownParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'pre') {
      return [];
    }
    final children = element.children ?? const <md.Node>[];
    if (children.isEmpty || children.first is! md.Element) {
      return [];
    }
    final code = children.first as md.Element;
    if (code.tag != 'code') {
      return [];
    }
    var language = '';
    final cls = code.attributes['class'] ?? '';
    if (cls.startsWith('language-')) {
      language = cls.substring('language-'.length);
    }
    var text = code.textContent;
    if (text.endsWith('\n')) {
      text = text.substring(0, text.length - 1);
    }
    return [
      Node(
        type: richtextCodeBlockType,
        attributes: {
          'language': language,
          'delta': (Delta()..insert(text)).toJson(),
        },
      ),
    ];
  }
}

class _FallbackMarkdownParser extends CustomMarkdownParser {
  const _FallbackMarkdownParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    final text = element.textContent;
    if (text.trim().isEmpty) {
      return [];
    }
    return [paragraphNode(delta: Delta()..insert(text))];
  }
}

class _ImageWithAltMarkdownParser extends CustomMarkdownParser {
  const _ImageWithAltMarkdownParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element) {
      return [];
    }
    md.Element? img;
    if (element.tag == 'img') {
      img = element;
    } else if (element.tag == 'p') {
      final children = element.children ?? const <md.Node>[];
      if (children.length == 1 &&
          children.first is md.Element &&
          (children.first as md.Element).tag == 'img') {
        img = children.first as md.Element;
      }
    }
    final src = img?.attributes['src'];
    if (img == null || src == null) {
      return [];
    }
    final node = imageNode(url: src);
    final alt = img.attributes['alt'] ?? '';
    if (alt.isNotEmpty) {
      node.updateAttributes({richtextImageAltKey: alt});
    }
    return [node];
  }
}

class _ImageWithAltNodeParser extends NodeParser {
  const _ImageWithAltNodeParser();

  @override
  String get id => ImageBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final alt = node.attributes[richtextImageAltKey] as String? ?? '';
    return '![$alt](${node.attributes[ImageBlockKeys.url]})';
  }
}

class _DashBulletedListNodeParser extends NodeParser {
  const _DashBulletedListNodeParser();

  @override
  String get id => BulletedListBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final delta = node.delta ?? Delta()
      ..insert('');
    final children = encoder?.convertNodes(node.children, withIndent: true);
    String markdown = '- ${DeltaMarkdownEncoder().convert(delta)}\n';
    if (children != null && children.isNotEmpty) {
      markdown += children;
    }
    return markdown;
  }
}

class _NumberedListNodeParser extends NodeParser {
  const _NumberedListNodeParser();

  @override
  String get id => NumberedListBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    var runStart = node;
    var distance = 0;
    while (runStart.previous != null &&
        runStart.previous!.type == NumberedListBlockKeys.type) {
      runStart = runStart.previous!;
      distance++;
    }
    final base = runStart.attributes[NumberedListBlockKeys.number] as int? ?? 1;
    final number = base + distance;
    final delta = node.delta ?? Delta()
      ..insert('');
    final children = encoder?.convertNodes(node.children, withIndent: true);
    String markdown = '$number. ${DeltaMarkdownEncoder().convert(delta)}\n';
    if (children != null && children.isNotEmpty) {
      markdown += children;
    }
    return markdown;
  }
}

class _QuoteNodeParser extends NodeParser {
  const _QuoteNodeParser();

  @override
  String get id => QuoteBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final own = DeltaMarkdownEncoder().convert(node.delta ?? Delta());
    final parts = <String>[
      if (own.isNotEmpty) own,
      for (final child in node.children)
        DeltaMarkdownEncoder().convert(child.delta ?? Delta()),
    ];
    if (parts.isEmpty) {
      return '>\n';
    }
    return parts
        .expand((part) => part.split('\n'))
        .map((line) => '> $line')
        .join('\n');
  }
}