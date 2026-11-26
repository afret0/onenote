import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/theme.dart';

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

  testWidgets('已设密码: 取消不进入, 错误提示重试, 正确进入且退出再进需再验证',
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

    await tester.tap(find.byIcon(Icons.arrow_back_ios));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('验证应用密码'), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
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
}