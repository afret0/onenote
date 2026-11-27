import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/bg_theme.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/shell_background.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  Future<AppState> seed(WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync('onenote_settings_bg');
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
      await state.init();
    });
    return state;
  }

  Future<void> pumpSettings(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: SettingsPage(state: state),
    ));
    await tester.pumpAndSettle();
  }

  Finder dialogText(String text) => find.descendant(
      of: find.byType(SimpleDialog), matching: find.text(text));

  testWidgets('外观区块含背景主题与背景范围行', (tester) async {
    final state = await seed(tester);
    await pumpSettings(tester, state);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('字体'), findsNothing);
    expect(find.text('背景主题'), findsOneWidget);
    expect(find.text('背景范围'), findsOneWidget);
    expect(find.text('薰衣草紫'), findsOneWidget);
    expect(find.text('全部区域'), findsOneWidget);
  });

  testWidgets('主题对话框含不使用与六套预览并可切换', (tester) async {
    final state = await seed(tester);
    await pumpSettings(tester, state);

    await tester.tap(find.text('背景主题'));
    await tester.pumpAndSettle();
    expect(dialogText('不使用'), findsOneWidget);
    for (final theme in shellBgThemes) {
      expect(dialogText(theme.name), findsOneWidget);
    }
    expect(
        find.descendant(
            of: find.byType(SimpleDialog),
            matching: find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is ShellBgPainter)),
        findsNWidgets(6));

    await tester.tap(dialogText('黛蓝'));
    await tester.pumpAndSettle();
    expect(state.bgTheme, shellBgIndigo);
    expect(find.text('黛蓝'), findsOneWidget);

    await tester.tap(find.text('背景主题'));
    await tester.pumpAndSettle();
    await tester.tap(dialogText('不使用'));
    await tester.pumpAndSettle();
    expect(state.bgTheme, shellBgNone);
    expect(find.text('不使用'), findsOneWidget);
  });

  testWidgets('范围对话框三档可切换', (tester) async {
    final state = await seed(tester);
    await pumpSettings(tester, state);

    await tester.tap(find.text('背景范围'));
    await tester.pumpAndSettle();
    expect(dialogText('侧栏与列表'), findsOneWidget);
    expect(dialogText('全部区域'), findsOneWidget);
    expect(dialogText('仅空态'), findsOneWidget);

    await tester.tap(dialogText('侧栏与列表'));
    await tester.pumpAndSettle();
    expect(state.bgScope, AppState.bgScopePane);
    expect(find.text('侧栏与列表'), findsOneWidget);
  });
}