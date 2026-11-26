import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/main.dart';
import 'package:onenote/ui/lock_screen.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/widgets.dart';

import 'fake_local_auth.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('生物识别认证在途时退后台不自锁, 认证通过仍进入设置; 无认证在途退后台照常锁',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_bio_blur_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    final originalAuth = LocalAuthPlatform.instance;
    final fake = FakeLocalAuth(authResult: false);
    LocalAuthPlatform.instance = fake;
    addTearDown(() {
      final gate = fake.authGate;
      if (gate != null && !gate.isCompleted) {
        gate.complete(false);
      }
      LocalAuthPlatform.instance = originalAuth;
    });

    final db = AppDb(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pw-123', 1000).encode());
      await db.createNotebook('工作');
    });
    await tester.pumpWidget(OneNoteApp(db: db));
    await tester.pump();

    Future<void> waitUntil(bool Function() done, {bool settle = true}) async {
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!done() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      if (settle) {
        await tester.pumpAndSettle();
      }
    }

    await waitUntil(() => find.text('解锁').evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextField), 'pw-123');
    await tester.tap(find.text('解锁'));
    await waitUntil(
        () => find.widgetWithText(ScopeTile, '工作').evaluate().isNotEmpty);
    expect(find.widgetWithText(ScopeTile, '工作'), findsOneWidget);

    fake.authGate = Completer<bool>();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final callsBefore = fake.authCalls;
    await waitUntil(() => fake.authCalls > callsBefore, settle: false);
    expect(find.text('验证应用密码'), findsOneWidget);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byType(LockGate), findsNothing);
    expect(find.text('验证应用密码'), findsOneWidget);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    fake.authGate!.complete(true);
    await waitUntil(
        () => find.byType(SettingsPage).evaluate().isNotEmpty);
    expect(find.byType(SettingsPage), findsOneWidget);

    fake.authGate = null;
    fake.authResult = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitUntil(() => find.text('解锁').evaluate().isNotEmpty);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(LockGate), findsOneWidget);
  });
}