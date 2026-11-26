import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/font_catalog.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/settings_page.dart';
import 'package:onenote/ui/theme.dart';

void main() {
  Future<AppState> seed(WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync('onenote_settings_font');
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
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: SettingsPage(state: state),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('font picker offers Cascadia and local font entries',
      (tester) async {
    final state = await seed(tester);
    await pumpSettings(tester, state);

    await tester.tap(find.text('界面字体'));
    await tester.pumpAndSettle();
    expect(find.text('Cascadia Code PL'), findsOneWidget);
    expect(find.text('导入本地字体…'), findsOneWidget);
    expect(find.text('在线获取字体…'), findsOneWidget);

    await tester.tap(find.text('Cascadia Code PL'));
    await tester.pumpAndSettle();
    expect(state.uiFont, AppState.uiFontCascadia);
    expect(find.text('Cascadia Code PL'), findsOneWidget);

    await tester.tap(find.text('界面字体'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在线获取字体…'));
    await tester.pumpAndSettle();
    expect(find.text('霞鹜文楷'), findsOneWidget);
    expect(find.text('思源黑体'), findsOneWidget);
    expect(find.text('思源宋体'), findsOneWidget);
    expect(find.text('朱雀仿宋'), findsOneWidget);
    expect(find.text('霞鹜文楷屏幕版'), findsOneWidget);
    expect(find.text('Maple Mono 中文'), findsOneWidget);
    expect(find.text('下载'), findsNWidgets(fontCatalog.length));
  });

  testWidgets('imported local font can be selected and deleted',
      (tester) async {
    final state = await seed(tester);
    final source = File('${Directory.systemTemp.createTempSync('onenote_font_src').path}/Pick-Regular.ttf')
      ..writeAsBytesSync(Uint8List.fromList([1, 2]));
    addTearDown(() => source.parent.deleteSync(recursive: true));
    await tester.runAsync(() async {
      await state.importLocalFonts([source.path]);
    });
    await pumpSettings(tester, state);

    await tester.tap(find.text('界面字体'));
    await tester.pumpAndSettle();
    expect(find.text('Pick'), findsOneWidget);
    expect(find.text('本地导入'), findsOneWidget);

    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(state.uiFont.startsWith(AppState.localFontPrefix), isTrue);

    await tester.tap(find.text('界面字体'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.byIcon(Icons.delete_outline)));
      await tester.pumpAndSettle();
      expect(find.text('删除字体'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 200 && state.fonts!.fonts.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
    });
    expect(state.fonts!.fonts, isEmpty);
    expect(state.uiFont, AppState.uiFontMiSans);
  });
}