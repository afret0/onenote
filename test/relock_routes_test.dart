import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/main.dart';
import 'package:onenote/ui/lock_screen.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/sync_settings_page.dart';
import 'package:onenote/ui/widgets.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> unlockToHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_relock_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (call) async => false,
    );
    final db = AppDb(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pw-123', 1000).encode());
      await db.createNotebook('工作');
    });
    await tester.pumpWidget(OneNoteApp(db: db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pw-123');
    await tester.tap(find.text('解锁'));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (find.widgetWithText(ScopeTile, '工作').evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ScopeTile, '工作'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final gate = find.text('验证应用密码');
    if (gate.evaluate().isNotEmpty) {
      final dialogField = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(dialogField, 'pw-123');
      await tester.tap(find.text('验证'));
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (find.byType(SettingsPage).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
    }
    expect(find.byType(SettingsPage), findsOneWidget);
  }

  testWidgets('设置页点立即锁定回到锁屏, 设置页被关闭', (tester) async {
    await unlockToHome(tester);

    await tester.ensureVisible(find.text('立即锁定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即锁定'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(LockGate), findsOneWidget);
    expect(find.text('onenote 已锁定'), findsOneWidget);
  });

  testWidgets('退后台锁定时设置页与同步子页一并关闭', (tester) async {
    await unlockToHome(tester);

    await tester.ensureVisible(find.text('WebDAV / OSS 同步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebDAV / OSS 同步'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncSettingsPage), findsOneWidget);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(SyncSettingsPage), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(LockGate), findsOneWidget);
    expect(find.text('onenote 已锁定'), findsOneWidget);
  });
}