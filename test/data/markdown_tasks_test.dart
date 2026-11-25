import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/markdown_tasks.dart';

void main() {
  test('flat task states follow source order', () {
    expect(markdownTaskStates('- [ ] a\n- [x] b\n- [X] c'),
        [false, true, true]);
  });

  test('loose lists keep task states', () {
    expect(markdownTaskStates('- [ ] a\n\n- [x] b\n\n- [ ] c'),
        [false, true, false]);
  });

  test('nested tasks report children before parent', () {
    expect(
        markdownTaskStates('- [ ] parent\n  - [x] child\n- [ ] second'),
        [true, false, false]);
  });

  test('task-like lines in code blocks are not tasks', () {
    expect(markdownTaskStates('```\n- [ ] fake\n```\n\n- [ ] real'), [false]);
    expect(markdownTaskStates('    - [ ] code\n\n- [ ] real'), [false]);
  });

  test('ordered and blockquote tasks are counted', () {
    expect(markdownTaskStates('1. [ ] o\n\n> - [x] q'), [false, true]);
  });

  test('toggle flips the exact flat item both ways', () {
    const content = '- [ ] a\n- [x] b';
    final first = markdownTaskMarkerPosition(content, 0);
    expect(toggleMarkdownTaskAt(content, first!), '- [x] a\n- [x] b');
    final second = markdownTaskMarkerPosition(content, 1);
    expect(toggleMarkdownTaskAt(content, second!), '- [ ] a\n- [ ] b');
  });

  test('toggle targets the right loose item', () {
    const content = '- [ ] a\n\n- [ ] b';
    final position = markdownTaskMarkerPosition(content, 1);
    expect(toggleMarkdownTaskAt(content, position!), '- [ ] a\n\n- [x] b');
  });

  test('toggle follows post-order ordinals for nested tasks', () {
    const content = '- [ ] parent\n  - [x] child\n- [ ] second';
    final child = markdownTaskMarkerPosition(content, 0);
    expect(toggleMarkdownTaskAt(content, child!),
        '- [ ] parent\n  - [ ] child\n- [ ] second');
    final parent = markdownTaskMarkerPosition(content, 1);
    expect(toggleMarkdownTaskAt(content, parent!),
        '- [x] parent\n  - [x] child\n- [ ] second');
  });

  test('toggle skips code block lookalikes', () {
    const content = '```\n- [ ] fake\n```\n\n- [ ] real';
    final position = markdownTaskMarkerPosition(content, 0);
    expect(toggleMarkdownTaskAt(content, position!),
        '```\n- [ ] fake\n```\n\n- [x] real');
  });

  test('toggle preserves crlf line endings', () {
    const content = '- [ ] a\r\n- [ ] b';
    final position = markdownTaskMarkerPosition(content, 0);
    expect(toggleMarkdownTaskAt(content, position!), '- [x] a\r\n- [ ] b');
  });

  test('out of range ordinal has no marker', () {
    expect(markdownTaskMarkerPosition('- [ ] a', 1), isNull);
    expect(markdownTaskMarkerPosition('plain text', 0), isNull);
  });

  test('thematic breaks do not stall the hoist syntax', () {
    expect(markdownTaskStates('* * *\n\n- [ ] a\n\n***\n\n- [x] b'),
        [false, true]);
    expect(markdownTaskStates('- - -\n\n1. [ ] a'), [false]);
  });
}
