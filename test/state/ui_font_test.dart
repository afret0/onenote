import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenote/data/app_db.dart';
import 'package:onenote/data/font_store.dart';
import 'package:onenote/state/app_state.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory supportDir;
  late AppDb db;
  late LocalFontStore store;
  late AppState state;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('onenote_ui_font');
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

  test('cascadia 内置字体可切换且重启保留', () async {
    await state.init();
    await state.setUiFont(AppState.uiFontCascadia);
    expect(state.uiFont, AppState.uiFontCascadia);
    final fresh = AppState(db, fontStoreOverride: store);
    addTearDown(fresh.dispose);
    await fresh.init();
    expect(fresh.uiFont, AppState.uiFontCascadia);
  });

  test('未注册的本地字体标识被拒绝', () async {
    await state.init();
    await state.setUiFont('${AppState.localFontPrefix}missing');
    expect(state.uiFont, AppState.uiFontMiSans);
  });

  test('导入本地字体可切换，删除使用中的字体回退 MiSans', () async {
    await state.init();
    final source = File('${supportDir.path}/src/Local-Regular.ttf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(Uint8List.fromList([1]));
    final imported = await state.importLocalFonts([source.path]);
    final id = imported.single.id;
    await state.setUiFont('${AppState.localFontPrefix}$id');
    expect(state.uiFont, '${AppState.localFontPrefix}$id');
    await state.deleteLocalFont(id);
    expect(state.uiFont, AppState.uiFontMiSans);
    expect(store.has(id), isFalse);
    expect(await db.getSetting(AppDb.uiFontKey), AppState.uiFontMiSans);
  });

  test('重启后注册表缺失的本地字体回退默认', () async {
    await db.setSetting(AppDb.uiFontKey, '${AppState.localFontPrefix}gone');
    await state.init();
    expect(state.uiFont, AppState.uiFontMiSans);
  });
}