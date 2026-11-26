import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/sync/sync_engine.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/lock_screen.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/theme.dart';

import 'fake_local_auth.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  late LocalAuthPlatform originalAuth;
  final dbs = <AppDb>[];

  setUp(() {
    originalAuth = LocalAuthPlatform.instance;
    supportDir =
        Directory.systemTemp.createTempSync('onenote_lock_trust_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    LocalAuthPlatform.instance = originalAuth;
    for (final db in dbs) {
      await db.close();
    }
    dbs.clear();
    supportDir.deleteSync(recursive: true);
  });

  AppDb track(AppDb db) {
    dbs.add(db);
    return db;
  }

  void useAndroid() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }

  Future<void> pumpGateRaw(
    WidgetTester tester,
    AppDb db,
    void Function(AppDb db, String? spaceId) onUnlocked,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: LockGate(globalDb: db, onUnlocked: onUnlocked),
    ));
  }

  Future<void> pumpUntil(
      WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  }

  testWidgets('Android 信任系统应用锁免密码免生物识别直接进入', (tester) async {
    useAndroid();
    final fake = FakeLocalAuth(enrolled: const [BiometricType.fingerprint]);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pass', 1000).encode());
      await db.setSetting(AppDb.trustSystemLockKey, '1');
    });
    AppDb? entered;
    String? enteredSpace = 'unset';
    await pumpGateRaw(tester, db, (d, s) {
      entered = d;
      enteredSpace = s;
    });
    await pumpUntil(tester, () => entered != null);
    expect(entered, same(db));
    expect(enteredSpace, isNull);
    expect(fake.authCalls, 0);
    expect(find.text('onenote 已锁定'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('信任开关关闭仍走锁屏', (tester) async {
    useAndroid();
    final fake = FakeLocalAuth(enrolled: const []);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pass', 1000).encode());
      await db.setSetting(AppDb.trustSystemLockKey, '0');
    });
    AppDb? entered;
    await pumpGateRaw(tester, db, (d, s) => entered = d);
    await pumpUntil(
        tester, () => find.text('onenote 已锁定').evaluate().isNotEmpty);
    expect(find.text('onenote 已锁定'), findsOneWidget);
    expect(entered, isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('非 Android 平台信任键不生效', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final fake = FakeLocalAuth(enrolled: const []);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pass', 1000).encode());
      await db.setSetting(AppDb.trustSystemLockKey, '1');
    });
    AppDb? entered;
    await pumpGateRaw(tester, db, (d, s) => entered = d);
    await pumpUntil(
        tester, () => find.text('onenote 已锁定').evaluate().isNotEmpty);
    expect(find.text('onenote 已锁定'), findsOneWidget);
    expect(entered, isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('托管解锁进上次解锁的隐私空间', (tester) async {
    useAndroid();
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('daily-pass', 1000).encode());
      final ref = PrivacySpaceRef(
          id: 'trust-space-1',
          lock: PasswordLock.create('secret-pass', 2000),
          createAt: 2000);
      final engine = SyncEngine(db);
      await engine.provisionPrivacySpace(ref);
      engine.dispose();
      await db.setSetting(AppDb.privacySpaceKey, ref.encode());
      await db.setSetting(AppDb.lockBioSpaceKey, 'trust-space-1');
      await db.setSetting(AppDb.trustSystemLockKey, '1');
    });
    AppDb? entered;
    String? enteredSpace;
    await tester.runAsync(() async {
      await pumpGateRaw(tester, db, (d, s) {
        entered = d;
        enteredSpace = s;
      });
      await waitUntil(tester, () => enteredSpace != null);
    });
    expect(enteredSpace, 'trust-space-1');
    expect(entered, isNotNull);
    expect(entered, isNot(same(db)));
    track(entered!);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('记忆空间已不存在回日常空间并清记忆', (tester) async {
    useAndroid();
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pass', 1000).encode());
      await db.setSetting(AppDb.lockBioSpaceKey, 'ghost-space');
      await db.setSetting(AppDb.trustSystemLockKey, '1');
    });
    AppDb? entered;
    String? enteredSpace = 'unset';
    await tester.runAsync(() async {
      await pumpGateRaw(tester, db, (d, s) {
        entered = d;
        enteredSpace = s;
      });
      await waitUntil(tester, () => entered != null);
    });
    expect(entered, same(db));
    expect(enteredSpace, isNull);
    await tester.runAsync(() async {
      expect(await db.getSetting(AppDb.lockBioSpaceKey), '');
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('生物识别认证免确认且允许系统密码兜底', (tester) async {
    final fake = FakeLocalAuth(enrolled: const [BiometricType.fingerprint]);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pass', 1000).encode());
    });
    AppDb? entered;
    await pumpGateRaw(tester, db, (d, s) => entered = d);
    await pumpUntil(tester, () => entered != null);
    expect(entered, same(db));
    expect(fake.lastOptions, isNotNull);
    expect(fake.lastOptions!.sensitiveTransaction, isFalse);
    expect(fake.lastOptions!.biometricOnly, isFalse);
  });

  Future<AppState> seedState(WidgetTester tester,
      {required String password}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var now = 1700000000000;
    final db = track(AppDb(NativeDatabase.memory(), clock: () => now));
    final state = AppState(db);
    addTearDown(state.dispose);
    await tester.runAsync(() async {
      now += 1000;
      await db.createNotebook('work');
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create(password, now).encode());
      await state.init();
    });
    return state;
  }

  Future<void> openSettings(WidgetTester tester, AppState state,
      String password) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final dialogField = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogField, password);
    await tester.runAsync(() async {
      await waitUntil(
          tester, () => find.byType(SettingsPage).evaluate().isNotEmpty);
    });
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  }

  testWidgets('设置页信任开关落库且可关回', (tester) async {
    useAndroid();
    final state = await seedState(tester, password: 'pw-123');
    await openSettings(tester, state, 'pw-123');
    final row = find.text('信任系统应用锁');
    await tester.scrollUntilVisible(row, 300);
    await tester.pumpAndSettle();
    expect(state.trustSystemLock, isFalse);

    await tester.tap(row);
    await tester.runAsync(() async {
      await waitUntil(tester, () => state.trustSystemLock);
      expect(await state.db.getSetting(AppDb.trustSystemLockKey), '1');
    });
    await tester.pumpAndSettle();

    await tester.tap(row);
    await tester.runAsync(() async {
      await waitUntil(tester, () => !state.trustSystemLock);
      expect(await state.db.getSetting(AppDb.trustSystemLockKey), '0');
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('非 Android 平台设置页不显示信任开关', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final state = await seedState(tester, password: 'pw-123');
    await openSettings(tester, state, 'pw-123');
    await tester.scrollUntilVisible(find.text('立即锁定'), 300);
    await tester.pumpAndSettle();
    expect(find.text('信任系统应用锁'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}