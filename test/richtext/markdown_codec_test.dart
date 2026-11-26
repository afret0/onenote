import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/richtext/document_matches.dart';
import 'package:onenote/richtext/markdown_codec.dart';

const _corpus = <String>[
  '',
  '一段普通文字。',
  '第一段\n\n第二段\n\n第三段',
  '# 标题一\n\n## 标题二\n\n### 标题三',
  '**粗体** 与 _斜体_ 与 ~~删除线~~ 与 `行内代码`',
  '[链接](https://example.com) 正文',
  '![截图.png](onenote-asset://abc123)',
  '- 甲\n- 乙\n- 丙',
  '1. 第一\n2. 第二\n3. 第三',
  '- 外层\n\t- 内层一\n\t- 内层二\n- 外层二',
  '- [ ] 待办一\n- [x] 待办二',
  '- [ ] 父任务\n\t- [x] 子任务',
  '> 引用一句话',
  '```dart\nvoid main() {\n  print(1);\n}\n```',
  '```\n无语言代码\n```',
  '| 列一 | 列二 |\n| --- | --- |\n| a | b |',
  '上文\n\n---\n\n下文',
  '中文混排 English 123 数字与符号 §±→',
  '# 项目笔记\n\n简介段落。\n\n## 待办\n\n- [ ] 事项一\n- [x] 事项二\n\n## 代码\n\n```go\nfmt.Println("hi")\n```\n\n> 备注\n\n| k | v |\n| --- | --- |\n| 1 | 2 |',
];

void main() {
  test('normalize 幂等：往返一次后不再变化', () {
    for (final source in _corpus) {
      final once = richtextNormalize(source);
      final twice = richtextNormalize(once);
      expect(twice, once, reason: 'source: $source');
    }
  });

  test('空内容解码出至少一个可编辑段落', () {
    final document = richtextDecode('');
    expect(document.root.children, isNotEmpty);
    expect(richtextEncode(document), '');
  });

  test('todo 勾选状态与嵌套保留', () {
    final document = richtextDecode('- [ ] 父任务\n\t- [x] 子任务');
    final parent = document.root.children.first;
    expect(parent.type, TodoListBlockKeys.type);
    expect(parent.attributes[TodoListBlockKeys.checked], false);
    expect(parent.children, isNotEmpty);
    expect(parent.children.first.attributes[TodoListBlockKeys.checked], true);
    final encoded = richtextEncode(document);
    expect(encoded, contains('- [ ] 父任务'));
    expect(encoded, contains('- [x] 子任务'));
  });

  test('代码块语言与内容保留', () {
    final document = richtextDecode('```dart\nvar a = 1;\n```');
    final node = document.root.children.first;
    expect(node.type, richtextCodeBlockType);
    expect(node.attributes['language'], 'dart');
    expect(node.delta!.toPlainText(), 'var a = 1;');
    expect(richtextEncode(document), contains('```dart\nvar a = 1;\n```'));
  });

  test('图片 alt 保留（附件文件名）', () {
    final document = richtextDecode('![截图.png](onenote-asset://abc123)');
    final node = document.root.children.first;
    expect(node.type, ImageBlockKeys.type);
    expect(node.attributes[ImageBlockKeys.url], 'onenote-asset://abc123');
    expect(richtextEncode(document),
        contains('![截图.png](onenote-asset://abc123)'));
  });

  test('无序列表统一为 - 前缀', () {
    final document = richtextDecode('* 甲\n* 乙');
    expect(richtextEncode(document), contains('- 甲\n- 乙'));
  });

  test('表格保留为表格块', () {
    final document = richtextDecode('| a | b |\n| --- | --- |\n| 1 | 2 |');
    expect(document.root.children.first.type, TableBlockKeys.type);
    final encoded = richtextEncode(document);
    expect(encoded, contains('|'));
    expect(richtextNormalize(encoded), encoded);
  });

  test('段落之间不被合并', () {
    final document = richtextDecode('第一段\n\n第二段');
    expect(document.root.children.length, 2);
    expect(richtextNormalize('第一段\n\n第二段'), contains('第一段\n\n第二段'));
  });

  test('遇损检测：HTML 块与内联 HTML 命中，常规 markdown 不命中', () {
    expect(richtextLossyParts('<div>raw</div>'), isNotEmpty);
    expect(richtextLossyParts('a <kbd>b</kbd> c'), isNotEmpty);
    for (final source in _corpus) {
      expect(richtextLossyParts(source), isEmpty, reason: 'source: $source');
    }
  });

  test('不支持的块降级为文本而不是丢弃', () {
    final document = richtextDecode('<div>保留这段文字</div>');
    final text = document.root.children
        .map((n) => n.delta?.toPlainText() ?? '')
        .join();
    expect(text, contains('保留这段文字'));
  });

  test('匹配：大小写敏感与不敏感、嵌套节点', () {
    final document =
        richtextDecode('Alpha alpha\n\n- 外层 alpha\n\t- 内层 ALPHA');
    final insensitive = richtextFindMatches(document, 'alpha');
    expect(insensitive.length, 4);
    final sensitive =
        richtextFindMatches(document, 'alpha', caseSensitive: true);
    expect(sensitive.length, 2);
    expect(sensitive.first.path, [0]);
    expect(sensitive.first.start, 6);
    expect(richtextFindMatches(document, ''), isEmpty);
  });
}