import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/sync/sync_engine.dart';
import 'package:onenote/ui/lock_screen.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  final dbs = <AppDb>[];

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('onenote_gate_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (call) async => false,
    );
  });

  tearDown(() async {
    for (final db in dbs) {
      await db.close();
    }
    dbs.clear();
    await supportDir.delete(recursive: true);
  });

  AppDb track(AppDb db) {
    dbs.add(db);
    return db;
  }

  Future<void> pumpGate(
    WidgetTester tester,
    AppDb db,
    void Function(AppDb db, String? spaceId) onUnlocked,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: LockGate(globalDb: db, onUnlocked: onUnlocked),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('未设置密码直接进入', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    AppDb? entered;
    String? enteredSpace = 'unset';
    await pumpGate(tester, db, (d, s) {
      entered = d;
      enteredSpace = s;
    });
    expect(entered, same(db));
    expect(enteredSpace, isNull);
    expect(find.text('onenote 已锁定'), findsNothing);
  });

  testWidgets('错误密码提示重试, 正确密码进入', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
    });
    AppDb? entered;
    await pumpGate(tester, db, (d, s) => entered = d);
    expect(find.text('onenote 已锁定'), findsOneWidget);
    expect(entered, isNull);

    await tester.enterText(find.byType(TextField), 'wrong-pass');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.text('密码错误，请重试'), findsOneWidget);
    expect(entered, isNull);

    await tester.enterText(find.byType(TextField), 'right-pass');
    await tester.tap(find.text('解锁'));
    await tester.pump();
    await tester.pump();
    expect(entered, same(db));
  });

  testWidgets('隐私空间密码打开独立子库', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    late PrivacySpaceRef ref;
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('daily-pass', 1000).encode());
      ref = PrivacySpaceRef(
          id: 'gate-space-1',
          lock: PasswordLock.create('secret-pass', 2000),
          createAt: 2000);
      final engine = SyncEngine(db);
      await engine.provisionPrivacySpace(ref);
      engine.dispose();
      await db.setSetting(AppDb.privacySpaceKey, ref.encode());
    });
    AppDb? entered;
    String? enteredSpace;
    await pumpGate(tester, db, (d, s) {
      entered = d;
      enteredSpace = s;
    });

    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField), 'secret-pass');
      await tester.tap(find.text('解锁'));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (enteredSpace == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(enteredSpace, 'gate-space-1');
    expect(entered, isNotNull);
    expect(entered, isNot(same(db)));
    track(entered!);
    await tester.runAsync(() async {
      final childLock =
          PasswordLock.parse(await entered!.getSetting(AppDb.appLockKey));
      expect(childLock!.verify('secret-pass'), isTrue);
    });
  });
}