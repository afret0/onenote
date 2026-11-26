import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/attachment_refs.dart';

void main() {
  final a = 'a' * 64;
  final b = 'b' * 64;
  String img(String id, [String name = 'pic.png']) =>
      '![$name](onenote-asset://$id)';
  String link(String id, String name) => '[$name](onenote-asset://$id)';

  group('renderedAttachmentRefCount', () {
    test('counts image and asset links', () {
      final content = '${img(a)}\n\n${link(a, 'doc.pdf')}\n\n${link(a, 'note.txt')}';
      expect(renderedAttachmentRefCount(content, a), 3);
    });

    test('ignores refs inside fenced and inline code', () {
      final content = '```\n${img(a)}\n```\n\n`![x](onenote-asset://$a)`\n\n${img(a)}';
      expect(renderedAttachmentRefCount(content, a), 1);
    });

    test('asset link counted regardless of extension', () {
      expect(renderedAttachmentRefCount(link(a, 'DOC.PDF'), a), 1);
      expect(renderedAttachmentRefCount(link(a, 'doc.pdfx'), a), 1);
    });

    test('counts nested image inside emphasis', () {
      expect(renderedAttachmentRefCount('**${img(a)}**', a), 1);
    });
  });

  group('renderedAttachmentRefTotals', () {
    test('per-id totals exclude code-block-only ids', () {
      final content = '${img(a)}\n\n${img(a)}\n\n```\n${img(b)}\n```';
      expect(renderedAttachmentRefTotals(content), {a: 2});
    });

    test('empty for plain content', () {
      expect(renderedAttachmentRefTotals('hello'), isEmpty);
    });
  });

  group('removeAttachmentRefAt', () {
    test('removes only the chosen occurrence and its empty line', () {
      final content = 'before\n\n${img(a)}\n\nmiddle\n\n${img(a)}\n\nafter';
      final first = removeAttachmentRefAt(content, a, 0)!;
      expect(first, 'before\n\nmiddle\n\n${img(a)}\n\nafter');
      final second = removeAttachmentRefAt(content, a, 1)!;
      expect(second, 'before\n\n${img(a)}\n\nmiddle\n\nafter');
    });

    test('skips code-block lookalikes when mapping ordinals', () {
      final content = '```\n${img(a)}\n```\n\n${img(a)}';
      final updated = removeAttachmentRefAt(content, a, 0)!;
      expect(updated, '```\n${img(a)}\n```');
    });

    test('inline removal keeps surrounding text', () {
      final content = 'left ${img(a)} right';
      expect(removeAttachmentRefAt(content, a, 0), 'left  right');
    });

    test('removes pdf link occurrence', () {
      final content = '${link(a, 'doc.pdf')}\n\ntail';
      expect(removeAttachmentRefAt(content, a, 0), 'tail');
    });

    test('out-of-range ordinal returns null', () {
      expect(removeAttachmentRefAt(img(a), a, 1), isNull);
      expect(removeAttachmentRefAt(img(a), a, -1), isNull);
      expect(removeAttachmentRefAt(img(a), b, 0), isNull);
    });

    test('non-pdf asset link is removable', () {
      expect(removeAttachmentRefAt(link(a, 'note.txt'), a, 0), '');
    });
  });

  group('AttachmentRefCounter', () {
    test('assigns ordinals modulo total across rebuilds', () {
      final counter = AttachmentRefCounter({a: 2});
      expect(counter.next(a), 0);
      expect(counter.next(a), 1);
      expect(counter.next(a), 0);
      expect(counter.next(a), 1);
    });

    test('unknown id falls back to ordinal 0', () {
      final counter = AttachmentRefCounter(const {});
      expect(counter.next(b), 0);
      expect(counter.next(b), 0);
    });
  });
}