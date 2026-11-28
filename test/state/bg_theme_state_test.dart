import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/bg_shape_kinds.dart';
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

  test('缺省随机且落库与全部区域范围', () async {
    await state.init();
    expect(state.bgTheme, shellBgRandom);
    expect(state.bgThemeData, isNotNull);
    expect(state.bgScope, AppState.bgScopeFull);
    expect(await db.getSetting(AppDb.bgThemeKey), shellBgRandom);
    expect(await db.getSetting(AppDb.bgRandomThemeKey),
        encodeShellBgTheme(state.bgThemeData!));
  });

  test('缺省随机每次启动重随', () async {
    await state.init();
    final first = encodeShellBgTheme(state.bgThemeData!);
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgTheme, shellBgRandom);
    expect(encodeShellBgTheme(fresh.bgThemeData!), isNot(first));
    expect(await db.getSetting(AppDb.bgRandomThemeKey),
        encodeShellBgTheme(fresh.bgThemeData!));
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

  test('固定主题与不使用重启不重随', () async {
    await state.init();
    await state.setBgTheme(shellBgIndigo);
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgTheme, shellBgIndigo);
    expect(fresh.bgRandomTheme, isNull);
    await fresh.setBgTheme(shellBgNone);
    final none = AppState(db, fontStoreOverride: store);
    addTearDown(none.dispose);
    await none.init();
    expect(none.bgTheme, shellBgNone);
    expect(none.bgRandomTheme, isNull);
  });

  test('随机生成落库且重启重随并通知', () async {
    await state.init();
    var notified = 0;
    state.addListener(() => notified++);
    await state.randomizeBg(rng: Random(7));
    expect(state.bgTheme, shellBgRandom);
    expect(notified, 1);
    expect(await db.getSetting(AppDb.bgRandomThemeKey),
        encodeShellBgTheme(state.bgThemeData!));
    expect(await db.getSetting(AppDb.bgThemeKey), shellBgRandom);
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(encodeShellBgTheme(fresh.bgThemeData!),
        isNot(encodeShellBgTheme(state.bgThemeData!)));
    expect(await db.getSetting(AppDb.bgRandomThemeKey),
        encodeShellBgTheme(fresh.bgThemeData!));
  });

  test('随机连刷替换旧结果且切走固定主题后可切回', () async {
    await state.init();
    await state.randomizeBg(rng: Random(7));
    await state.randomizeBg(rng: Random(8));
    final second = encodeShellBgTheme(state.bgThemeData!);
    expect(await db.getSetting(AppDb.bgRandomThemeKey), second);
    await state.setBgTheme(shellBgIndigo);
    expect(state.bgThemeData!.id, shellBgIndigo);
    await state.setBgTheme(shellBgRandom);
    expect(encodeShellBgTheme(state.bgThemeData!), second);
  });

  test('随机存量非法被忽略且启动重随覆写', () async {
    await db.setSetting(AppDb.bgThemeKey, shellBgRandom);
    await db.setSetting(AppDb.bgRandomThemeKey, 'bogus');
    await state.init();
    expect(state.bgTheme, shellBgRandom);
    expect(state.bgRandomTheme, isNotNull);
    expect(await db.getSetting(AppDb.bgRandomThemeKey),
        encodeShellBgTheme(state.bgThemeData!));
  });

  test('未知主题标识被拒绝', () async {
    await state.init();
    await state.setBgTheme('bogus');
    expect(state.bgTheme, shellBgRandom);
    expect(await db.getSetting(AppDb.bgThemeKey), shellBgRandom);
  });

  test('存量非法主题回退默认', () async {
    await db.setSetting(AppDb.bgThemeKey, 'bogus');
    await state.init();
    expect(state.bgTheme, shellBgRandom);
    expect(state.bgThemeData, isNotNull);
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

  test('形状缺省全选且子集落库重启保留', () async {
    await state.init();
    expect(state.bgShapes, shellBgAllShapeIds.toSet());
    var notified = 0;
    state.addListener(() => notified++);
    await state.setBgShapes({'tri', 'blob'});
    expect(state.bgShapes, {'tri', 'blob'});
    expect(notified, 1);
    expect(await db.getSetting(AppDb.bgShapesKey), 'blob,tri');
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgShapes, {'blob', 'tri'});
  });

  test('形状全不选是合法值且重启保留为素纸底', () async {
    await state.init();
    await state.setBgShapes(<String>{});
    expect(state.bgShapes, isEmpty);
    expect(await db.getSetting(AppDb.bgShapesKey), '');
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgShapes, isEmpty);
  });

  test('未知形状标识被拒绝且同值不重复通知', () async {
    await state.init();
    await state.setBgShapes({'tri', 'bogus'});
    expect(state.bgShapes, shellBgAllShapeIds.toSet());
    expect(await db.getSetting(AppDb.bgShapesKey), isNull);
    var notified = 0;
    state.addListener(() => notified++);
    await state.setBgShapes(shellBgAllShapeIds.toSet());
    expect(notified, 0);
  });

  test('存量非法形状回退全选而空串保留全关', () async {
    await db.setSetting(AppDb.bgShapesKey, 'tri,bogus');
    await state.init();
    expect(state.bgShapes, shellBgAllShapeIds.toSet());
    await db.setSetting(AppDb.bgShapesKey, '');
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.bgShapes, isEmpty);
  });
}