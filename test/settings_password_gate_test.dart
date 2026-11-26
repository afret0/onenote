import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/theme.dart';

import 'fake_local_auth.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> seed(WidgetTester tester, {String? password}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final supportDir =
        Directory.systemTemp.createTempSync('onenote_settings_gate_test');
    addTearDown(() => supportDir.deleteSync(recursive: true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      now += 1000;
      await db.createNotebook('work');
      if (password != null) {
        await db.setSetting(
            AppDb.appLockKey, PasswordLock.create(password, now).encode());
      }
      await state.init();
    });
    return state;
  }

  Future<void> pumpHome(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('未设置密码点设置直接进入', (tester) async {
    final state = await seed(tester);
    await pumpHome(tester, state);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('验证应用密码'), findsNothing);
  });

  testWidgets('已设密码: 取消不进入, 错误提示重试, 输对自动进入且退出再进需再验证',
      (tester) async {
    final state = await seed(tester, password: 'pw-123');
    await pumpHome(tester, state);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('验证应用密码'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final dialogField = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogField, 'wrong');
    await tester.tap(find.text('验证'));
    await tester.pumpAndSettle();
    expect(find.text('密码错误，请重试'), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);

    await tester.enterText(dialogField, 'pw-123');
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (find.byType(SettingsPage).evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('验证应用密码'), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('输错同长密码不提示不计次, 按钮才计次', (tester) async {
    final state = await seed(tester, password: 'pw-123');
    await pumpHome(tester, state);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final dialogField = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.runAsync(() async {
      await tester.enterText(dialogField, 'pw-124');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    expect(find.text('密码错误，请重试'), findsNothing);
    expect(find.text('验证应用密码'), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
    await tester.runAsync(() async {
      expect(await state.db.getSetting(AppDb.lockFailCountKey), isNull);
      await tester.tap(find.text('验证'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (find.text('密码错误，请重试').evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
      expect(await state.db.getSetting(AppDb.lockFailCountKey), '1');
    });
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('旧锁无长度不自动提交仍走按钮', (tester) async {
    final state = await seed(tester);
    await tester.runAsync(() async {
      final lock = PasswordLock.create('pw-123', 1700000001000);
      final raw = jsonEncode({
        'salt': lock.salt,
        'hash': lock.hash,
        'updateAt': lock.updateAt
      });
      await state.db.setSetting(AppDb.appLockKey, raw);
      state.appLock = PasswordLock.parse(raw);
    });
    await pumpHome(tester, state);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final dialogField = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.runAsync(() async {
      await tester.enterText(dialogField, 'pw-123');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    expect(find.text('验证应用密码'), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
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
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('cmd+comma 同样过密码门', (tester) async {
    final state = await seed(tester, password: 'pw-123');
    await pumpHome(tester, state);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('验证应用密码'), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
  });

  FakeLocalAuth useFakeAuth({bool authResult = true}) {
    final fake = FakeLocalAuth(authResult: authResult);
    final original = LocalAuthPlatform.instance;
    LocalAuthPlatform.instance = fake;
    addTearDown(() => LocalAuthPlatform.instance = original);
    return fake;
  }

  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('生物识别自动弹出通过后直接进入设置', (tester) async {
    final fake = useFakeAuth();
    final state = await seed(tester, password: 'pw-123');
    await pumpHome(tester, state);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await waitUntil(tester, () => find.byType(SettingsPage).evaluate().isNotEmpty);
    expect(fake.authCalls, 1);
    expect(fake.lastReason, '进入设置');
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('生物识别未通过回退密码, 输对仍进入', (tester) async {
    final fake = useFakeAuth(authResult: false);
    final state = await seed(tester, password: 'pw-123');
    await pumpHome(tester, state);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await waitUntil(
        tester, () => find.text('生物识别未通过，请输入密码').evaluate().isNotEmpty);
    expect(fake.authCalls, 1);
    expect(find.byType(SettingsPage), findsNothing);
    final dialogField = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogField, 'pw-123');
    await waitUntil(tester, () => find.byType(SettingsPage).evaluate().isNotEmpty);
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('生物识别开关关闭时设置门禁不弹生物识别', (tester) async {
    final fake = useFakeAuth();
    final state = await seed(tester, password: 'pw-123');
    await tester.runAsync(() async {
      await state.db.setSetting(AppDb.lockBioKey, '0');
      state.lockBio = false;
    });
    await pumpHome(tester, state);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('验证应用密码'), findsOneWidget);
    expect(find.text('生物识别解锁'), findsNothing);
    expect(fake.authCalls, 0);
    final dialogField = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogField, 'pw-123');
    await waitUntil(tester, () => find.byType(SettingsPage).evaluate().isNotEmpty);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(fake.authCalls, 0);
  });
}