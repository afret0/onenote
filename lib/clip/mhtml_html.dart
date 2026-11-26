import 'dart:convert';
import 'dart:typed_data';

final _boundaryPattern = RegExp(r'boundary\s*=\s*"?([^";\s]+)"?', caseSensitive: false);
final _scriptPattern = RegExp(r'<script\b[^>]*>[\s\S]*?</script\s*>|<script\b[^>]*/>', caseSensitive: false);
final _srcsetPattern = RegExp('\\s+srcset\\s*=\\s*("[^"]*"|\'[^\']*\')', caseSensitive: false);
final _attrUrlPattern = RegExp('\\b(src|href|poster|data-src)\\s*=\\s*("([^"]*)"|\'([^\']*)\')', caseSensitive: false);
final _cssUrlPattern = RegExp('url\\(\\s*(\'([^\']*)\'|"([^"]*)"|([^\'")\\s]+))\\s*\\)', caseSensitive: false);
final _styleBlockPattern = RegExp(r'(<style\b[^>]*>)([\s\S]*?)(</style\s*>)', caseSensitive: false);
final _styleAttrPattern = RegExp('\\bstyle\\s*=\\s*("([^"]*)"|\'([^\']*)\')', caseSensitive: false);
final _linkTagPattern = RegExp(r'<link\b[^>]*>', caseSensitive: false);
final _relStylesheetPattern = RegExp('\\brel\\s*=\\s*["\']?stylesheet["\']?', caseSensitive: false);
final _hrefPattern = RegExp('\\bhref\\s*=\\s*("([^"]*)"|\'([^\']*)\')', caseSensitive: false);

class _Part {
  _Part(this.mime, this.charset, this.location, this.cid, this.bytes);

  final String mime;
  final String charset;
  final String location;
  final String cid;
  final Uint8List bytes;

  bool get isHtml => mime == 'text/html';
  bool get isCss => mime == 'text/css';

  String get text => utf8.decode(bytes, allowMalformed: true);
}

String convertMhtmlToHtml(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final headerEnd = _headerEnd(raw);
  final boundary = _boundaryPattern.firstMatch(raw.substring(0, headerEnd));
  if (boundary == null) {
    return _stripScripts(utf8.decode(bytes, allowMalformed: true));
  }
  final parts = _splitParts(raw, boundary.group(1)!);
  if (parts.isEmpty) {
    return _stripScripts(utf8.decode(bytes, allowMalformed: true));
  }
  final main = parts.firstWhere((p) => p.isHtml, orElse: () => parts.first);
  final resources = <String, String>{};
  final cssParts = <String, _Part>{};
  for (final part in parts) {
    if (identical(part, main)) {
      continue;
    }
    final data = 'data:${part.mime};base64,${base64.encode(part.bytes)}';
    if (part.location.isNotEmpty) {
      resources[part.location] = data;
      cssParts[part.location] = part;
    }
    if (part.cid.isNotEmpty) {
      resources['cid:${part.cid}'] = data;
    }
  }
  var html = _stripScripts(main.text);
  html = html.replaceAll(_srcsetPattern, '');
  html = _inlineStylesheets(html, main.location, resources, cssParts);
  html = _rewriteStyleBlocks(html, main.location, resources);
  html = _rewriteStyleAttrs(html, main.location, resources);
  html = _rewriteAttrUrls(html, main.location, resources);
  return html;
}

int _headerEnd(String raw) {
  final crlf = raw.indexOf('\r\n\r\n');
  final lf = raw.indexOf('\n\n');
  if (crlf == -1) {
    return lf == -1 ? raw.length : lf;
  }
  if (lf == -1) {
    return crlf;
  }
  return crlf < lf ? crlf : lf;
}

List<_Part> _splitParts(String raw, String boundary) {
  final delimiter = '--$boundary';
  final chunks = raw.split(delimiter);
  final parts = <_Part>[];
  for (final chunk in chunks.skip(1)) {
    if (chunk.startsWith('--')) {
      break;
    }
    final end = _headerEnd(chunk);
    if (end == chunk.length) {
      continue;
    }
    final headerText = chunk.substring(0, end);
    var body = chunk.substring(end).replaceFirst(RegExp(r'^(\r\n\r\n|\n\n)'), '');
    body = body.replaceFirst(RegExp(r'(\r\n|\n)$'), '');
    final headers = <String, String>{};
    for (final line in headerText.split(RegExp(r'\r\n|\n'))) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        headers[line.substring(0, colon).trim().toLowerCase()] =
            line.substring(colon + 1).trim();
      }
    }
    final type = headers['content-type'] ?? 'application/octet-stream';
    final mime = type.split(';').first.trim().toLowerCase();
    final charsetMatch =
        RegExp(r'charset\s*=\s*"?([^";\s]+)"?', caseSensitive: false).firstMatch(type);
    final encoding = (headers['content-transfer-encoding'] ?? '').toLowerCase();
    Uint8List decoded;
    if (encoding == 'base64') {
      decoded = base64.decode(body.replaceAll(RegExp(r'\s+'), ''));
    } else if (encoding == 'quoted-printable') {
      decoded = _decodeQuotedPrintable(body);
    } else {
      decoded = Uint8List.fromList(latin1.encode(body));
    }
    parts.add(_Part(
      mime,
      charsetMatch?.group(1)?.toLowerCase() ?? 'utf-8',
      headers['content-location'] ?? '',
      (headers['content-id'] ?? '').replaceAll(RegExp(r'^<|>$'), ''),
      decoded,
    ));
  }
  return parts;
}

Uint8List _decodeQuotedPrintable(String body) {
  final joined = body.replaceAll(RegExp(r'=\r\n|=\n'), '');
  final out = <int>[];
  for (var i = 0; i < joined.length; i++) {
    final ch = joined.codeUnitAt(i);
    if (ch == 0x3D && i + 2 < joined.length) {
      final hex = int.tryParse(joined.substring(i + 1, i + 3), radix: 16);
      if (hex != null) {
        out.add(hex);
        i += 2;
        continue;
      }
    }
    out.add(ch);
  }
  return Uint8List.fromList(out);
}

String _stripScripts(String html) => html.replaceAll(_scriptPattern, '');

String _resolve(String base, String ref) {
  if (ref.isEmpty ||
      ref.startsWith('data:') ||
      ref.startsWith('cid:') ||
      ref.startsWith('#') ||
      ref.startsWith('mailto:') ||
      ref.startsWith('javascript:')) {
    return ref;
  }
  final baseUri = Uri.tryParse(base);
  final refUri = Uri.tryParse(ref);
  if (baseUri == null || refUri == null) {
    return ref;
  }
  return baseUri.resolveUri(refUri).toString();
}

String _lookup(String base, String ref, Map<String, String> resources) {
  if (ref.startsWith('cid:')) {
    return resources[ref] ?? ref;
  }
  return resources[_resolve(base, ref)] ?? ref;
}

String _inlineStylesheets(
  String html,
  String base,
  Map<String, String> resources,
  Map<String, _Part> cssParts,
) {
  return html.replaceAllMapped(_linkTagPattern, (m) {
    final tag = m.group(0)!;
    if (!_relStylesheetPattern.hasMatch(tag)) {
      return tag;
    }
    final href = _hrefPattern.firstMatch(tag);
    final ref = href?.group(2) ?? href?.group(3) ?? '';
    final url = _resolve(base, ref);
    final part = cssParts[url];
    if (part == null) {
      return tag;
    }
    final css = _rewriteCssUrls(part.text, url, resources);
    return '<style>$css</style>';
  });
}

String _rewriteStyleBlocks(String html, String base, Map<String, String> resources) {
  return html.replaceAllMapped(_styleBlockPattern, (m) {
    return '${m.group(1)}${_rewriteCssUrls(m.group(2)!, base, resources)}${m.group(3)}';
  });
}

String _rewriteStyleAttrs(String html, String base, Map<String, String> resources) {
  return html.replaceAllMapped(_styleAttrPattern, (m) {
    final quote = m.group(2) != null ? '"' : "'";
    final value = m.group(2) ?? m.group(3) ?? '';
    return 'style=$quote${_rewriteCssUrls(value, base, resources)}$quote';
  });
}

String _rewriteCssUrls(String css, String base, Map<String, String> resources) {
  return css.replaceAllMapped(_cssUrlPattern, (m) {
    final ref = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
    final resolved = _lookup(base, ref, resources);
    if (resolved.startsWith('data:')) {
      return 'url($resolved)';
    }
    final quote = m.group(2) != null ? "'" : '"';
    return 'url($quote$resolved$quote)';
  });
}

String _rewriteAttrUrls(String html, String base, Map<String, String> resources) {
  return html.replaceAllMapped(_attrUrlPattern, (m) {
    final name = m.group(1)!;
    final quote = m.group(3) != null ? '"' : "'";
    final ref = m.group(3) ?? m.group(4) ?? '';
    final resolved = _lookup(base, ref, resources);
    return '$name=$quote$resolved$quote';
  });
}