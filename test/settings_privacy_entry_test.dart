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
  Future<AppState> seed(WidgetTester tester) async {
    final dir =
        Directory.systemTemp.createTempSync('onenote_privacy_entry_test');
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
    await tester.runAsync(() async {
      await db.createNotebook('工作');
      await state.init();
    });
    return state;
  }

  Future<void> pumpSettings(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: SettingsPage(state: state),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapVersion(WidgetTester tester) async {
    await tester.tap(find.text('版本'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('隐私空间入口默认隐藏, 连点版本 10 次才显示并提示进度', (tester) async {
    tester.view.physicalSize = const Size(800, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await seed(tester);
    await pumpSettings(tester, state);

    expect(find.text('版本'), findsOneWidget);
    expect(find.text('创建隐私空间'), findsNothing);
    expect(find.text('销毁隐私空间'), findsNothing);

    for (var i = 0; i < 6; i++) {
      await tapVersion(tester);
    }
    expect(find.text('创建隐私空间'), findsNothing);
    expect(find.textContaining('再点击'), findsNothing);

    await tapVersion(tester);
    expect(find.text('再点击 3 次显示隐私空间入口'), findsOneWidget);
    expect(find.text('创建隐私空间'), findsNothing);

    await tapVersion(tester);
    await tapVersion(tester);
    expect(find.text('再点击 1 次显示隐私空间入口'), findsOneWidget);
    expect(find.text('创建隐私空间'), findsNothing);

    await tapVersion(tester);
    await tester.pumpAndSettle();
    expect(find.text('隐私空间入口已显示'), findsOneWidget);
    expect(find.text('创建隐私空间'), findsOneWidget);
  });

  testWidgets('解锁仅本次设置页内有效, 重新进入恢复隐藏', (tester) async {
    tester.view.physicalSize = const Size(800, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await seed(tester);
    await pumpSettings(tester, state);

    for (var i = 0; i < 10; i++) {
      await tapVersion(tester);
    }
    await tester.pumpAndSettle();
    expect(find.text('创建隐私空间'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pumpSettings(tester, state);
    expect(find.text('创建隐私空间'), findsNothing);
  });

  testWidgets('已有隐私空间时销毁入口同样隐藏, 解锁后可见', (tester) async {
    tester.view.physicalSize = const Size(800, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await seed(tester);
    await tester.runAsync(() async {
      await state.setAppPassword('1234');
      await state.createPrivacySpace('5678');
    });
    await pumpSettings(tester, state);

    expect(find.text('销毁隐私空间'), findsNothing);
    for (var i = 0; i < 10; i++) {
      await tapVersion(tester);
    }
    await tester.pumpAndSettle();
    expect(find.text('销毁隐私空间'), findsOneWidget);
    expect(find.text('创建隐私空间'), findsNothing);
  });

  testWidgets('已有隐私空间解锁后显示进入入口, 点击触发切空间', (tester) async {
    tester.view.physicalSize = const Size(800, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await seed(tester);
    await tester.runAsync(() async {
      await state.setAppPassword('1234');
      await state.createPrivacySpace('5678');
    });
    var switched = 0;
    state.switchSpaceHandler = () => switched++;
    await pumpSettings(tester, state);
    expect(find.text('进入隐私空间'), findsNothing);
    for (var i = 0; i < 10; i++) {
      await tapVersion(tester);
    }
    await tester.pumpAndSettle();
    final row = find.text('进入隐私空间');
    expect(row, findsOneWidget);
    expect(find.text('销毁隐私空间'), findsOneWidget);
    await tester.tap(row);
    await tester.pump();
    expect(switched, 1);
  });
}
