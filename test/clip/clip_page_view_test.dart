import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/attachment_store.dart';
import 'package:onenote/ui/clip_page_view.dart';
import 'package:onenote/ui/theme.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  bool loaded = false;

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    loaded = true;
  }

  @override
  Future<void> setBackgroundColor(Color color) {
    throw UnimplementedError('opaque is not implemented on macOS');
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: Key('fake-webview'));
}

class _FakeWebViewPlatform extends WebViewPlatform {
  final controllers = <_FakeController>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _FakeController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _FakeWebViewWidget(params);
}

void main() {
  testWidgets('mac 内嵌剪藏页不调 setBackgroundColor, 页面正常加载', (tester) async {
    final platform = _FakeWebViewPlatform();
    WebViewPlatform.instance = platform;

    late Directory root;
    late AttachmentStore store;
    late String id;
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('clip_page_view_test');
      store = AttachmentStore.forTest(root);
      id = await store.save(
        Uint8List.fromList(utf8.encode('<html><body>clip</body></html>')),
        'page.html',
      );
    });
    addTearDown(() => root.deleteSync(recursive: true));

    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: ClipPageEmbed(store: store, id: id, name: 'page.html'),
      ),
    ));
    for (var i = 0;
        i < 50 && find.byKey(const Key('fake-webview')).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    expect(find.textContaining('页面解析失败'), findsNothing);
    expect(find.byKey(const Key('fake-webview')), findsOneWidget);
    expect(platform.controllers.single.loaded, isTrue);
  });
}