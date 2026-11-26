import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/lock/biometrics.dart';
import 'package:onenote/state/lock_attempts.dart';
import 'package:onenote/ui/password_prompts.dart';
import 'package:onenote/ui/theme.dart';

import 'fake_local_auth.dart';

void main() {
  late LocalAuthPlatform originalAuth;
  final dbs = <AppDb>[];

  setUp(() {
    originalAuth = LocalAuthPlatform.instance;
  });

  tearDown(() async {
    LocalAuthPlatform.instance = originalAuth;
    for (final db in dbs) {
      await db.close();
    }
    dbs.clear();
  });

  AppDb track(AppDb db) {
    dbs.add(db);
    return db;
  }

  Future<void> pumpHost(
    WidgetTester tester,
    AppDb db,
    PasswordLock lock,
    Future<bool> Function()? onBiometric,
    void Function(String?) onResult,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                final result = await promptPassword(
                  context,
                  title: '解锁笔记本',
                  attempts: LockAttempts(db),
                  lock: lock,
                  onBiometric: onBiometric,
                );
                onResult(result);
              },
              child: const Text('打开弹窗'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开弹窗'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('已录入生物识别自动弹出认证并免密关闭', (WidgetTester tester) async {
    final fake = FakeLocalAuth();
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    final lock = PasswordLock.create('pass', 1000);
    var bioOk = false;
    String? result = 'unset';
    await pumpHost(tester, db, lock, () async {
      final ok = await Biometrics.authenticate('解锁笔记本');
      if (ok) {
        bioOk = true;
      }
      return ok;
    }, (r) => result = r);
    await tester.pumpAndSettle();
    expect(bioOk, isTrue);
    expect(result, isNull);
    expect(fake.authCalls, 1);
    expect(fake.lastReason, '解锁笔记本');
    expect(find.text('解锁笔记本'), findsNothing);
  });

  testWidgets('生物识别未通过留在弹窗回退密码', (WidgetTester tester) async {
    final fake = FakeLocalAuth(authResult: false);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    final lock = PasswordLock.create('pass', 1000);
    var bioOk = false;
    String? result = 'unset';
    await pumpHost(tester, db, lock, () async {
      final ok = await Biometrics.authenticate('解锁笔记本');
      if (ok) {
        bioOk = true;
      }
      return ok;
    }, (r) => result = r);
    await tester.pumpAndSettle();
    expect(find.text('生物识别未通过，请输入密码'), findsOneWidget);
    expect(find.text('解锁笔记本'), findsOneWidget);
    expect(result, 'unset');

    await tester.enterText(find.byType(TextField), 'pass');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(result, 'pass');
    expect(bioOk, isFalse);
  });

  testWidgets('未录入生物识别不自动弹, 手动按钮可用', (WidgetTester tester) async {
    final fake = FakeLocalAuth(enrolled: const []);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    final lock = PasswordLock.create('pass', 1000);
    var bioOk = false;
    String? result = 'unset';
    await pumpHost(tester, db, lock, () async {
      final ok = await Biometrics.authenticate('解锁笔记本');
      if (ok) {
        bioOk = true;
      }
      return ok;
    }, (r) => result = r);
    await tester.pumpAndSettle();
    expect(fake.authCalls, 0);
    expect(find.text('生物识别解锁'), findsOneWidget);

    await tester.tap(find.text('生物识别解锁'));
    await tester.pumpAndSettle();
    expect(fake.authCalls, 1);
    expect(bioOk, isTrue);
    expect(result, isNull);
  });

  testWidgets('无生物识别回调的验证弹窗不出按钮不探测', (WidgetTester tester) async {
    final fake = FakeLocalAuth();
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    final lock = PasswordLock.create('pass', 1000);
    String? result = 'unset';
    await pumpHost(tester, db, lock, null, (r) => result = r);
    await tester.pumpAndSettle();
    expect(fake.authCalls, 0);
    expect(find.text('生物识别解锁'), findsNothing);
    expect(find.text('解锁笔记本'), findsOneWidget);
    expect(result, 'unset');
  });
}