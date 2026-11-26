import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/password_lock.dart';
import 'package:onenote/state/lock_attempts.dart';
import 'package:onenote/ui/password_prompts.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  Future<TextEditingController> pumpDialog(WidgetTester tester) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final lock = PasswordLock.create('abcdef', 1000);
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () {
                promptPassword(context,
                    title: '验证应用密码',
                    attempts: LockAttempts(db),
                    lock: lock);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    return tester.widget<TextField>(find.byType(TextField)).controller!;
  }

  FocusNode fieldFocus(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).focusNode!;

  IconButton clearButton(WidgetTester tester) => tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.clear), matching: find.byType(IconButton)));

  testWidgets('清空按钮一键清空并回到输入框焦点', (tester) async {
    final controller = await pumpDialog(tester);
    expect(clearButton(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(clearButton(tester).onPressed, isNotNull);
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(fieldFocus(tester).hasFocus, isTrue);
    expect(clearButton(tester).onPressed, isNull);
  });

  testWidgets('点眼睛切换可见性不抢输入框焦点', (tester) async {
    await pumpDialog(tester);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(fieldFocus(tester).hasFocus, isTrue);
  });

  testWidgets('macOS Cmd+A 全选密码', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final controller = await pumpDialog(tester);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 5);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows Ctrl+A 全选密码', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final controller = await pumpDialog(tester);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 5);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('密码错误后清空并回到输入框焦点', (tester) async {
    final controller = await pumpDialog(tester);
    await tester.enterText(find.byType(TextField), 'wrongx');
    await tester.pump();
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.text('密码错误，请重试'), findsOneWidget);
    expect(controller.text, isEmpty);
    expect(fieldFocus(tester).hasFocus, isTrue);
  });
}