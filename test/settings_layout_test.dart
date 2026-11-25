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
    final dir = Directory.systemTemp.createTempSync('onenote_settings_test');
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

  double dx(WidgetTester tester, String title) =>
      tester.getTopLeft(find.text(title)).dx;
  double dy(WidgetTester tester, String title) =>
      tester.getTopLeft(find.text(title)).dy;

  testWidgets('narrow settings stays single column with search scope last',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await seed(tester);
    await pumpSettings(tester, state);

    const titles = ['字体', '启动', '数据保留', '同步', '剪藏', '即将上线', '搜索范围'];
    for (final title in titles) {
      expect(dx(tester, title), dx(tester, '字体'));
    }
    for (var i = 1; i < titles.length; i++) {
      expect(dy(tester, titles[i]), greaterThan(dy(tester, titles[i - 1])));
    }
  });

  testWidgets('settings uses two columns from 900 width',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await seed(tester);
    await pumpSettings(tester, state);

    expect(dx(tester, '启动'), dx(tester, '字体'));
    expect(dx(tester, '数据保留'), dx(tester, '字体'));
    expect(dx(tester, '同步'), dx(tester, '字体'));
    expect(dx(tester, '剪藏'), greaterThan(dx(tester, '字体')));
    expect(dx(tester, '即将上线'), dx(tester, '剪藏'));
    expect(dx(tester, '搜索范围'), dx(tester, '剪藏'));
    expect(dy(tester, '即将上线'), greaterThan(dy(tester, '剪藏')));
    expect(dy(tester, '搜索范围'), greaterThan(dy(tester, '即将上线')));
  });

  testWidgets('settings back button uses click cursor without tooltip',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await seed(tester);
    await pumpSettings(tester, state);

    expect(find.byTooltip('Back'), findsNothing);
    final region = tester.widget<MouseRegion>(find
        .ancestor(
            of: find.byIcon(Icons.arrow_back_ios),
            matching: find.byType(MouseRegion))
        .first);
    expect(region.cursor, SystemMouseCursors.click);
  });

  testWidgets('settings uses three columns from 1400 width',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = await seed(tester);
    await pumpSettings(tester, state);

    expect(dx(tester, '启动'), dx(tester, '字体'));
    expect(dx(tester, '数据保留'), dx(tester, '字体'));
    expect(dx(tester, '剪藏'), greaterThan(dx(tester, '字体')));
    expect(dx(tester, '同步'), dx(tester, '剪藏'));
    expect(dx(tester, '即将上线'), greaterThan(dx(tester, '剪藏')));
    expect(dx(tester, '搜索范围'), dx(tester, '即将上线'));
  });
}