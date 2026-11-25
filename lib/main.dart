import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'data/app_db.dart';
import 'data/password_lock.dart';
import 'lock/background_lock.dart';
import 'state/app_state.dart';
import 'sync/sync_engine.dart';
import 'synthetic_paste.dart';
import 'ui/dialogs.dart';
import 'ui/home_page.dart';
import 'ui/lock_screen.dart';
import 'ui/theme.dart';
import 'window_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SyntheticPaste.install();
  final db = AppDb(AppDb.openExecutor());
  await db.purgeExpired();
  WindowSizeController? windowController;
  if (isDesktopWindow) {
    windowController = WindowSizeController(db);
    await windowController.init();
  }
  runApp(OneNoteApp(db: db, windowController: windowController));
}

class OneNoteApp extends StatefulWidget {
  const OneNoteApp({super.key, required this.db, this.windowController});

  final AppDb db;
  final WindowSizeController? windowController;

  @override
  State<OneNoteApp> createState() => _OneNoteAppState();
}

class _OneNoteAppState extends State<OneNoteApp> {
  AppState? state;
  AppDb? _spaceDb;
  BackgroundLock? _backgroundLock;
  final _navKey = GlobalKey<NavigatorState>();
  bool _relocking = false;

  @override
  void dispose() {
    _backgroundLock?.dispose();
    widget.windowController?.dispose();
    state?.dispose();
    _spaceDb?.close();
    widget.db.close();
    super.dispose();
  }

  void _enter(AppDb db, String? spaceId) {
    final s = AppState(db, spaceId: spaceId, globalDb: widget.db);
    s.lockHandler = _relock;
    s.destroyChildSpaceHandler = () => _destroyCurrentSpace(s);
    setState(() {
      state = s;
      _spaceDb = spaceId == null || spaceId.isEmpty ? null : db;
    });
    s.init();
    _backgroundLock?.dispose();
    _backgroundLock = BackgroundLock.install(_onBackground);
    developer.log('done, 已进入空间, spaceId: ${spaceId ?? ''}');
  }

  void _onBackground() {
    final s = state;
    if (s == null || _relocking) {
      return;
    }
    if (!s.appBackgroundLock || s.appLock?.active != true) {
      developer.log(
          'skip, 后台锁定未启用或未设密码, enabled: ${s.appBackgroundLock}, hasLock: ${s.appLock?.active == true}');
      return;
    }
    s.lockApp();
  }

  void _relock() {
    final s = state;
    if (s == null || _relocking) {
      return;
    }
    _relocking = true;
    final db = _spaceDb;
    _backgroundLock?.dispose();
    _backgroundLock = null;
    setState(() {
      state = null;
      _spaceDb = null;
    });
    s.dispose();
    db?.close();
    _relocking = false;
    developer.log('done, 已回到锁屏');
  }

  Future<void> _destroyCurrentSpace(AppState child) async {
    final context = _navKey.currentContext;
    final spaceId = child.spaceId;
    if (context == null || spaceId == null) {
      return;
    }
    final first = await confirm(
      context,
      title: '销毁隐私空间',
      message: '该空间内的全部笔记将被永久删除（本地与云端），无法恢复。确定继续？',
      confirmLabel: '继续',
      danger: true,
    );
    if (!first || !mounted) {
      developer.log('skip, 用户取消销毁隐私空间第一步, spaceId: $spaceId');
      return;
    }
    final second = await confirm(
      _navKey.currentContext ?? context,
      title: '再次确认',
      message: '销毁后此密码将不再打开任何数据，空间无法找回。确定销毁？',
      confirmLabel: '销毁',
      danger: true,
    );
    if (!second || !mounted) {
      developer.log('skip, 用户取消销毁隐私空间第二步, spaceId: $spaceId');
      return;
    }
    final parentId = await child.db.getSetting(AppDb.spaceParentKey) ?? '';
    final parentDb = parentId.isEmpty
        ? widget.db
        : AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(parentId)));
    try {
      final engine = SyncEngine(parentDb);
      await engine.destroyPrivacySpaceData(spaceId);
      engine.dispose();
      await parentDb.setSetting(AppDb.privacySpaceKey,
          PrivacySpaceRef.clearedAt(parentDb.clock()).encode());
      final push = SyncEngine(parentDb);
      await push.requestSync('destroyPrivacySpace');
      push.dispose();
    } catch (err) {
      developer.log('fail, 销毁隐私空间异常, spaceId: $spaceId, err: $err');
    } finally {
      if (parentId.isNotEmpty) {
        await parentDb.close();
      }
    }
    developer.log('done, 隐私空间已销毁并回锁屏, spaceId: $spaceId');
    _relock();
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final sans = s == null
        ? miSansFamily
        : (s.uiFont == AppState.uiFontInter ? interFamily : miSansFamily);
    final fontScale = s?.fontScale ?? AppState.fontScaleDefault;
    final noteFontSize = s?.noteFontSize ?? AppState.noteFontSizeDefault;
    return MaterialApp(
      title: 'onenote',
      navigatorKey: _navKey,
      theme: buildInkTheme(Brightness.light,
          sans: sans, fontScale: fontScale, noteFontSize: noteFontSize),
      darkTheme: buildInkTheme(Brightness.dark,
          sans: sans, fontScale: fontScale, noteFontSize: noteFontSize),
      themeMode: ThemeMode.dark,
      home: s == null
          ? LockGate(globalDb: widget.db, onUnlocked: _enter)
          : ListenableBuilder(
              listenable: s,
              builder: (context, _) => HomePage(state: s),
            ),
    );
  }
}
