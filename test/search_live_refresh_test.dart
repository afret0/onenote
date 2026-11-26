import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/state/app_state.dart';
import 'package:onenote/ui/home_page.dart';
import 'package:onenote/ui/theme.dart';
import 'package:onenote/ui/widgets.dart';

void main() {
  testWidgets('搜索结果随笔记修改实时重建：删掉命中内容后列表剔除该笔记',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('onenote_search_refresh_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    late Note alpha;
    await tester.runAsync(() async {
      final work = await db.createNotebook('工作');
      alpha = await db.createNote(work.id, title: '甲', content: '独有词甲');
      now += 1000;
      await db.createNote(work.id, title: '乙', content: '无关内容');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: HomePage(state: state),
    ));
    await tester.pumpAndSettle();

    Future<void> settleReal() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    await tester.enterText(find.byType(TextField).first, '独有词甲');
    await settleReal();
    expect(find.widgetWithText(NoteCard, '甲'), findsOneWidget);
    expect(find.widgetWithText(NoteCard, '乙'), findsNothing);

    await tester.runAsync(() async {
      now += 1000;
      await state.saveNote(alpha.id, '甲', '命中内容已被删除');
    });
    await settleReal();
    expect(find.widgetWithText(NoteCard, '甲'), findsNothing);
    expect(find.text('没有匹配的笔记'), findsOneWidget);

    await tester.runAsync(() async {
      now += 1000;
      await state.saveNote(alpha.id, '甲', '独有词甲又回来了');
    });
    await settleReal();
    expect(find.widgetWithText(NoteCard, '甲'), findsOneWidget);
  });
}