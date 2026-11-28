import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/lock/app_focus.dart';
import 'package:onenote/sync/sync_engine.dart';
import 'package:onenote/ui/lock_screen.dart';
import 'package:onenote/ui/theme.dart';

import 'fake_local_auth.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  late LocalAuthPlatform originalAuth;
  final dbs = <AppDb>[];

  setUp(() async {
    originalAuth = LocalAuthPlatform.instance;
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
    LocalAuthPlatform.instance = originalAuth;
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
    for (var i = 0; i < 20 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('录入指纹自动弹出生物识别直达解锁', (WidgetTester tester) async {
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
    expect(fake.authCalls, 1);
    expect(fake.lastReason, '解锁 onenote');
  });

  testWidgets('录入面容同样自动弹出认证', (WidgetTester tester) async {
    final fake = FakeLocalAuth(enrolled: const [BiometricType.face]);
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
    expect(fake.authCalls, 1);
  });

  testWidgets('生物识别未通过回退密码重试', (WidgetTester tester) async {
    final fake = FakeLocalAuth(authResult: false);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
    });
    AppDb? entered;
    await pumpGateRaw(tester, db, (d, s) => entered = d);
    await pumpUntil(tester,
        () => find.text('生物识别未通过，请输入密码').evaluate().isNotEmpty);
    expect(find.text('生物识别未通过，请输入密码'), findsOneWidget);
    expect(fake.authCalls, 1);
    expect(entered, isNull);

    await tester.enterText(find.byType(TextField), 'right-pass');
    await tester.tap(find.text('解锁'));
    await tester.pump();
    await tester.pump();
    expect(entered, same(db));
  });

  testWidgets('未录入生物识别不自动弹, 指纹按钮手动可用', (WidgetTester tester) async {
    final fake = FakeLocalAuth(enrolled: const []);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pass', 1000).encode());
    });
    AppDb? entered;
    await pumpGateRaw(tester, db, (d, s) => entered = d);
    await pumpUntil(tester, () => find.byIcon(Icons.fingerprint).evaluate().isNotEmpty);
    expect(fake.authCalls, 0);
    expect(entered, isNull);

    await tester.tap(find.byIcon(Icons.fingerprint));
    await pumpUntil(tester, () => entered != null);
    expect(entered, same(db));
    expect(fake.authCalls, 1);
  });

  testWidgets('后台锁屏不自动弹指纹, 回到前台才弹', (WidgetTester tester) async {
    final fake = FakeLocalAuth(enrolled: const [BiometricType.fingerprint]);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pass', 1000).encode());
    });
    AppDb? entered;
    AppFocus.debugForeground = false;
    addTearDown(() => AppFocus.debugForeground = null);
    await pumpGateRaw(tester, db, (d, s) => entered = d);
    await pumpUntil(
        tester, () => find.byIcon(Icons.fingerprint).evaluate().isNotEmpty);
    expect(fake.authCalls, 0);
    expect(entered, isNull);

    AppFocus.debugReturnToForeground();
    await pumpUntil(tester, () => entered != null);
    expect(entered, same(db));
    expect(fake.authCalls, 1);
  });

  testWidgets('后台锁屏期间用户已输入密码, 回前台不再自动弹',
      (WidgetTester tester) async {
    final fake = FakeLocalAuth(enrolled: const [BiometricType.fingerprint]);
    LocalAuthPlatform.instance = fake;
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('pass', 1000).encode());
    });
    AppDb? entered;
    AppFocus.debugForeground = false;
    addTearDown(() => AppFocus.debugForeground = null);
    await pumpGateRaw(tester, db, (d, s) => entered = d);
    await pumpUntil(
        tester, () => find.byIcon(Icons.fingerprint).evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.pump();

    AppFocus.debugReturnToForeground();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(fake.authCalls, 0);
    expect(entered, isNull);
  });

  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  }

  testWidgets('输对密码自动解锁无需回车', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
    });
    AppDb? entered;
    await pumpGate(tester, db, (d, s) => entered = d);
    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField), 'right-pass');
      await waitUntil(tester, () => entered != null);
    });
    expect(entered, same(db));
    await tester.runAsync(() async {
      expect(await db.getSetting(AppDb.lockFailCountKey), '0');
    });
  });

  testWidgets('输错同长密码不提示不计次, 回车才计次', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
    });
    AppDb? entered;
    await pumpGate(tester, db, (d, s) => entered = d);
    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField), 'wrong-pass');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    expect(find.text('密码错误，请重试'), findsNothing);
    expect(entered, isNull);
    await tester.runAsync(() async {
      expect(await db.getSetting(AppDb.lockFailCountKey), isNull);
      await tester.tap(find.text('解锁'));
      await waitUntil(tester,
          () => find.text('密码错误，请重试').evaluate().isNotEmpty);
      expect(await db.getSetting(AppDb.lockFailCountKey), '1');
    });
    expect(entered, isNull);
  });

  testWidgets('旧锁无长度不自动提交仍走回车', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      final lock = PasswordLock.create('right-pass', 1000);
      await db.setSetting(
          AppDb.appLockKey,
          jsonEncode({
            'salt': lock.salt,
            'hash': lock.hash,
            'updateAt': lock.updateAt
          }));
    });
    AppDb? entered;
    await pumpGate(tester, db, (d, s) => entered = d);
    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField), 'right-pass');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    expect(entered, isNull);
    await tester.tap(find.text('解锁'));
    await tester.pump();
    await tester.pump();
    expect(entered, same(db));
  });

  testWidgets('隐私空间长密码输到根密码长度不打断', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('wxyz', 1000).encode());
      final ref = PrivacySpaceRef(
          id: 'gate-space-auto',
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
      await tester.enterText(find.byType(TextField), 'abcd');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      expect(enteredSpace, isNull);
      expect(find.text('密码错误，请重试'), findsNothing);
      expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'abcd');
      await tester.enterText(find.byType(TextField), 'secret-pass');
      await waitUntil(tester, () => enteredSpace != null);
    });
    expect(enteredSpace, 'gate-space-auto');
    expect(entered, isNotNull);
    expect(entered, isNot(same(db)));
    track(entered!);
  });

  testWidgets('隐私空间密码连切五次不触发冷却', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('daily-pass', 1000).encode());
      final ref = PrivacySpaceRef(
          id: 'gate-space-loop',
          lock: PasswordLock.create('secret-pass', 2000),
          createAt: 2000);
      final engine = SyncEngine(db);
      await engine.provisionPrivacySpace(ref);
      engine.dispose();
      await db.setSetting(AppDb.privacySpaceKey, ref.encode());
    });
    for (var round = 0; round < AppDb.lockFailMax; round++) {
      AppDb? entered;
      String? enteredSpace;
      await tester.pumpWidget(MaterialApp(
        key: ValueKey('gate-loop-$round'),
        theme: buildInkTheme(Brightness.dark),
        home: LockGate(globalDb: db, onUnlocked: (d, s) {
          entered = d;
          enteredSpace = s;
        }),
      ));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.enterText(find.byType(TextField), 'secret-pass');
        await waitUntil(tester, () => enteredSpace != null);
      });
      expect(enteredSpace, 'gate-space-loop',
          reason: '第 ${round + 1} 次用空间密码解锁应成功');
      expect(find.textContaining('错误次数过多'), findsNothing);
      track(entered!);
      await tester.runAsync(() async {
        expect(await db.getSetting(AppDb.lockFailCountKey), '0');
        expect(await db.getSetting(AppDb.lockCooldownUntilKey), isNull);
      });
    }
  });

  testWidgets('双锁全不匹配一次提交只计一次错误', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('daily-pass', 1000).encode());
      final ref = PrivacySpaceRef(
          id: 'gate-space-miss',
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
      await tester.enterText(find.byType(TextField), 'wrong-pass');
      await tester.tap(find.text('解锁'));
      await waitUntil(tester,
          () => find.text('密码错误，请重试').evaluate().isNotEmpty);
      expect(await db.getSetting(AppDb.lockFailCountKey), '1');
    });
    expect(enteredSpace, isNull);
    expect(entered, isNull);
    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField), 'daily-pass');
      await waitUntil(tester, () => entered != null);
      expect(await db.getSetting(AppDb.lockFailCountKey), '0');
    });
    expect(entered, same(db));
  });

  testWidgets('密码框自动聚焦不走系统密码框, 掩码显示可揭示', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
    });
    await pumpGate(tester, db, (d, s) {});
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isTrue);
    expect(field.obscureText, isFalse);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.pump();
    final spanContext = tester.element(find.byType(EditableText));
    expect(
        editable.controller
            .buildTextSpan(context: spanContext, withComposing: false)
            .text,
        '••••••');
    expect(editable.controller.text, 'abc123');

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(
        editable.controller
            .buildTextSpan(context: spanContext, withComposing: false)
            .text,
        'abc123');
  });

  testWidgets('锁定页密码框一键清空且焦点不丢', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
    });
    await pumpGate(tester, db, (d, s) {});
    IconButton clearButton() => tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.clear), matching: find.byType(IconButton)));
    expect(clearButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.pump();
    expect(clearButton().onPressed, isNotNull);
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(clearButton().onPressed, isNull);
  });

  testWidgets('锁定页点眼睛不抢输入框焦点', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
    });
    await pumpGate(tester, db, (d, s) {});
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .focusNode!
            .hasFocus,
        isTrue);
  });

  testWidgets('锁定页掩码态 Cmd+A 全选', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final db = track(AppDb(NativeDatabase.memory()));
      await tester.runAsync(() async {
        await db.setSetting(
            AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
      });
      await pumpGate(tester, db, (d, s) {});
      await tester.enterText(find.byType(TextField), 'abc123');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 6);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('锁定页掩码态 Ctrl+A 全选', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final db = track(AppDb(NativeDatabase.memory()));
      await tester.runAsync(() async {
        await db.setSetting(
            AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
      });
      await pumpGate(tester, db, (d, s) {});
      await tester.enterText(find.byType(TextField), 'abc123');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 6);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('锁定页掩码态全选后菜单无复制剪切', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('right-pass', 1000).encode());
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': 'clip'};
      }
      if (call.method == 'Clipboard.hasStrings') {
        return <String, dynamic>{'value': true};
      }
      return null;
    });
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpGate(tester, db, (d, s) {});
    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.pump();
    final state =
        tester.state<EditableTextState>(find.byType(EditableText));
    state.widget.controller.selection =
        const TextSelection(baseOffset: 0, extentOffset: 6);
    await tester.pumpAndSettle();
    state.showToolbar();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Paste'), findsOneWidget);
  });

  testWidgets('旧锁无长度停笔后兜底自动进入', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      final full = PasswordLock.create('abcd', 1000);
      await db.setSetting(
          AppDb.appLockKey,
          PasswordLock(
                  salt: full.salt, hash: full.hash, updateAt: 1000)
              .encode());
    });
    AppDb? entered;
    await pumpGate(tester, db, (d, s) => entered = d);
    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();
    expect(entered, isNull);
    await pumpUntil(tester, () => entered != null);
    expect(entered, same(db));
  });

  testWidgets('兜底静默校验输错不提示不计次不清空', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      final full = PasswordLock.create('abcd', 1000);
      await db.setSetting(
          AppDb.appLockKey,
          PasswordLock(
                  salt: full.salt, hash: full.hash, updateAt: 1000)
              .encode());
    });
    AppDb? entered;
    await pumpGate(tester, db, (d, s) => entered = d);
    await tester.enterText(find.byType(TextField), 'wxyz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(entered, isNull);
    expect(find.text('密码错误，请重试'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'wxyz');
    await tester.runAsync(() async {
      expect(await db.getSetting(AppDb.lockFailCountKey), isNull);
    });
  });

  testWidgets('回车解锁成功补记长度并更新时间戳', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      final full = PasswordLock.create('abcd', 1000);
      await db.setSetting(
          AppDb.appLockKey,
          PasswordLock(
                  salt: full.salt, hash: full.hash, updateAt: 1000)
              .encode());
    });
    AppDb? entered;
    await pumpGate(tester, db, (d, s) => entered = d);
    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(entered, same(db));
    await tester.runAsync(() async {
      final lock =
          PasswordLock.parse(await db.getSetting(AppDb.appLockKey));
      expect(lock!.len, 4);
      expect(lock.updateAt, greaterThan(1000));
      expect(lock.verify('abcd'), isTrue);
    });
  });

  testWidgets('隐私空间旧锁回车解锁补记父子标记', (WidgetTester tester) async {
    final db = track(AppDb(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await db.setSetting(
          AppDb.appLockKey, PasswordLock.create('daily-pass', 1000).encode());
      final full = PasswordLock.create('secret-pass', 2000);
      final ref = PrivacySpaceRef(
          id: 'gate-space-old',
          lock: PasswordLock(
              salt: full.salt, hash: full.hash, updateAt: 2000),
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
    expect(enteredSpace, 'gate-space-old');
    track(entered!);
    await tester.runAsync(() async {
      final childLock =
          PasswordLock.parse(await entered!.getSetting(AppDb.appLockKey));
      expect(childLock!.len, 11);
      expect(childLock.updateAt, greaterThan(2000));
      final ref = PrivacySpaceRef.parse(
          await db.getSetting(AppDb.privacySpaceKey));
      expect(ref!.lock.len, 11);
      expect(ref.lock.updateAt, greaterThan(2000));
    });
  });
}