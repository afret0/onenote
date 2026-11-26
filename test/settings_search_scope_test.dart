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
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('默认全选; 取消一个只搜其余; 勾回全选与全不选都归一为全部', (tester) async {
    final supportDir =
        Directory.systemTemp.createTempSync('onenote_scope_ui_test');
    addTearDown(() => supportDir.deleteSync(recursive: true));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    var now = 1700000000000;
    final db = AppDb(NativeDatabase.memory(), clock: () => now);
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    late Notebook work;
    await tester.runAsync(() async {
      now += 1000;
      work = await db.createNotebook('work');
      now += 1000;
      await db.createNotebook('life');
      await state.init();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildInkTheme(Brightness.dark),
      home: SettingsPage(state: state),
    ));
    await tester.pumpAndSettle();

    Finder row(String name) => find.ancestor(
        of: find.text(name), matching: find.byType(CheckboxListTile));
    bool checked(String name) =>
        tester.widget<CheckboxListTile>(row(name)).value ?? false;
    Future<void> tapRow(String name) async {
      await tester.ensureVisible(row(name));
      await tester.pumpAndSettle();
      var notified = false;
      void listener() => notified = true;
      state.addListener(listener);
      await tester.tap(row(name));
      await tester.pump();
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!notified && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      state.removeListener(listener);
      await tester.pumpAndSettle();
    }

    await tester.scrollUntilVisible(
        find.text('当前搜索全部笔记本（全不选或全选均为全部）。'), 300);
    await tester.pumpAndSettle();
    expect(checked('work'), isTrue);
    expect(checked('life'), isTrue);
    expect(find.text('当前搜索全部笔记本（全不选或全选均为全部）。'), findsOneWidget);

    await tapRow('work');
    expect(checked('work'), isFalse);
    expect(checked('life'), isTrue);
    expect(state.searchScope, isNot(contains(work.id)));
    expect(find.text('当前只搜索勾选的 1 个笔记本。'), findsOneWidget);

    await tapRow('work');
    expect(checked('work'), isTrue);
    expect(checked('life'), isTrue);
    expect(state.searchScope, isEmpty);

    await tapRow('work');
    expect(checked('work'), isFalse);
    expect(checked('life'), isTrue);
    await tapRow('life');
    expect(state.searchScope, isEmpty);
    expect(checked('work'), isTrue);
    expect(checked('life'), isTrue);
    expect(find.text('当前搜索全部笔记本（全不选或全选均为全部）。'), findsOneWidget);
  });
}