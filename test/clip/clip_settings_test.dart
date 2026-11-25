import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  testWidgets('clip section switch starts bridge and port row reflects state',
      (WidgetTester tester) async {
    HttpOverrides.global = null;
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_clip_ui_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    final db = AppDb(NativeDatabase.memory());
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    var freePort = 0;
    await tester.runAsync(() async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      freePort = probe.port;
      await probe.close();
      await db.createNotebook('工作');
      await state.init();
      await state.setClipPort(freePort);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: SettingsPage(state: state),
    ));
    await tester.pumpAndSettle();

    expect(find.text('剪藏'), findsOneWidget);
    expect(find.text('$freePort'), findsOneWidget);
    final toggle = find.byType(Switch);
    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.runAsync(() async {
      await tester.tap(toggle);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(state.clipEnabled, isTrue);
    expect(tester.widget<Switch>(toggle).value, isTrue);

    await tester.runAsync(() async {
      final client = HttpClient()..findProxy = (uri) => 'DIRECT';
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$freePort/ping'));
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();
      client.close(force: true);
    });

    await tester.runAsync(() async {
      await tester.tap(toggle);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(state.clipEnabled, isFalse);
  });
}