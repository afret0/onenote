import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/bg_theme.dart';
import 'package:onenote/data/font_store.dart';
import 'package:onenote/state/app_state.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  late AppDb db;
  late LocalFontStore store;
  late AppState state;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('onenote_bg_state');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    db = AppDb(NativeDatabase.memory());
    store = LocalFontStore.forTest(
        Directory('${supportDir.path}/fonts')..createSync(recursive: true),
        registrar: (family, weights) async {});
    state = AppState(db, fontStoreOverride: store);
  });

  tearDown(() async {
    state.dispose();
    await db.close();
    supportDir.deleteSync(recursive: true);
  });

  test('缺省薰衣草紫与全部区域范围', () async {
    await state.init();
    expect(state.bgTheme, shellBgLavender);
    expect(state.bgScope, AppState.bgScopeFull);
  });

  test('切换主题落库且重启保留并通知', () async {
    await state.init();
    var notified = 0;
    state.addListener(() => notified++);
    await state.setBgTheme(shellBgIndigo);
    expect(state.bgTheme, shellBgIndigo);
    expect(notified, 1);
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgTheme, shellBgIndigo);
  });

  test('不使用是合法值且重启保留', () async {
    await state.init();
    await state.setBgTheme(shellBgNone);
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgTheme, shellBgNone);
  });

  test('未知主题标识被拒绝', () async {
    await state.init();
    await state.setBgTheme('bogus');
    expect(state.bgTheme, shellBgLavender);
    expect(await db.getSetting(AppDb.bgThemeKey), isNull);
  });

  test('存量非法主题回退默认', () async {
    await db.setSetting(AppDb.bgThemeKey, 'bogus');
    await state.init();
    expect(state.bgTheme, shellBgLavender);
  });

  test('范围三档可切换且重启保留', () async {
    await state.init();
    await state.setBgScope(AppState.bgScopeFull);
    expect(state.bgScope, AppState.bgScopeFull);
    await state.setBgScope(AppState.bgScopeEmpty);
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgScope, AppState.bgScopeEmpty);
  });

  test('未知范围标识被拒绝且存量非法回退默认', () async {
    await state.init();
    await state.setBgScope('bogus');
    expect(state.bgScope, AppState.bgScopeFull);
    await db.setSetting(AppDb.bgScopeKey, 'bogus');
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgScope, AppState.bgScopeFull);
  });
}