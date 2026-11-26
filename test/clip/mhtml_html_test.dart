import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/clip/mhtml_html.dart';

Uint8List _mhtml(String html, {String htmlEncoding = '8bit'}) {
  final png = base64.encode(Uint8List.fromList([1, 2, 3]));
  final bg = base64.encode(Uint8List.fromList([4, 5]));
  final css = base64.encode(utf8.encode('body{color:red;background:url(img/a.png)}'));
  final body = htmlEncoding == 'quoted-printable'
      ? html.replaceAll('中', '=E4=B8=AD')
      : html;
  final raw = [
    'From: <Saved by Blink>',
    'Snapshot-Content-Location: http://x/page.html',
    'Content-Type: multipart/related; type="text/html";',
    '\tboundary="----MultipartBoundary--TEST----"',
    '',
    '------MultipartBoundary--TEST----',
    'Content-Type: text/html; charset=utf-8',
    'Content-Transfer-Encoding: $htmlEncoding',
    'Content-Location: http://x/page.html',
    '',
    body,
    '------MultipartBoundary--TEST----',
    'Content-Type: image/png',
    'Content-Transfer-Encoding: base64',
    'Content-Location: http://x/img/a.png',
    '',
    png,
    '------MultipartBoundary--TEST----',
    'Content-Type: text/css',
    'Content-Transfer-Encoding: base64',
    'Content-Location: http://x/s.css',
    '',
    css,
    '------MultipartBoundary--TEST----',
    'Content-Type: image/png',
    'Content-Transfer-Encoding: base64',
    'Content-Location: http://x/img/bg.png',
    '',
    bg,
    '------MultipartBoundary--TEST------',
    '',
  ].join('\r\n');
  return Uint8List.fromList(utf8.encode(raw));
}

const _html =
    '<html><head><link rel="stylesheet" href="s.css">'
    '<style>body{background:url(img/bg.png)}</style></head>'
    '<body><img src="img/a.png" srcset="img/a.png 2x">'
    '<script>alert(1)</script>'
    '<p style="background:url(\'img/bg.png\')">中</p></body></html>';

void main() {
  test('mhtml 转单文件 html：资源内联/脚本剥离/srcset 剥离', () {
    final out = convertMhtmlToHtml(_mhtml(_html));
    expect(out, contains('src="data:image/png;base64,AQID"'));
    expect(out, contains('url(data:image/png;base64,AQID)'));
    expect(out, contains('url(data:image/png;base64,BAU=)'));
    expect(out, isNot(contains('<script')));
    expect(out, isNot(contains('srcset')));
    expect(out, isNot(contains('<link')));
    expect(out, contains('color:red'));
    expect(out, contains('中'));
  });

  test('quoted-printable 正文解码', () {
    final out = convertMhtmlToHtml(_mhtml(_html, htmlEncoding: 'quoted-printable'));
    expect(out, contains('中'));
    expect(out, isNot(contains('=E4=B8=AD')));
  });

  test('非 multipart 输入按 html 直通并剥脚本', () {
    final raw = Uint8List.fromList(utf8.encode('<p>ok</p><script>x</script>'));
    expect(convertMhtmlToHtml(raw), '<p>ok</p>');
  });

  test('cid 引用内联', () {
    final png = base64.encode(Uint8List.fromList([9]));
    final raw = [
      'Content-Type: multipart/related; boundary="B"',
      '',
      '--B',
      'Content-Type: text/html',
      'Content-Location: http://x/p.html',
      '',
      '<img src="cid:img1">',
      '--B',
      'Content-Type: image/png',
      'Content-Transfer-Encoding: base64',
      'Content-ID: <img1>',
      '',
      png,
      '--B--',
      '',
    ].join('\r\n');
    final out = convertMhtmlToHtml(Uint8List.fromList(latin1.encode(raw)));
    expect(out, contains('src="data:image/png;base64,$png"'));
  });
}