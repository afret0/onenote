import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../clip/clip_server.dart';
import '../data/app_db.dart';
import '../data/attachment_store.dart';
import '../data/bg_shape_kinds.dart';
import '../data/bg_theme.dart';
import '../data/font_catalog.dart';
import '../data/font_store.dart';
import '../data/password_lock.dart';
import '../lock/biometrics.dart';
import '../richtext/markdown_codec.dart';
import '../sync/diff3.dart';
import '../sync/remote_store.dart';
import '../sync/sync_engine.dart';
import '../window_setup.dart' show isDesktopWindow;
import 'lock_attempts.dart';

enum NoteScopeKind { all, notebook, trash }

class NoteScope {
  const NoteScope.all() : kind = NoteScopeKind.all, notebookId = null;
  const NoteScope.trash() : kind = NoteScopeKind.trash, notebookId = null;
  const NoteScope.notebook(String this.notebookId)
      : kind = NoteScopeKind.notebook;

  final NoteScopeKind kind;
  final String? notebookId;

  bool sameAs(NoteScope other) =>
      kind == other.kind && notebookId == other.notebookId;
}

class AppState extends ChangeNotifier {
  AppState(this.db,
      {RemoteStore? syncStoreOverride,
      this.fontStoreOverride,
      this.spaceId,
      AppDb? globalDb})
      : globalDb = globalDb ?? db {
    sync = SyncEngine(db,
        attachments: () => attachments, storeOverride: syncStoreOverride);
    sync.addListener(_onSyncChanged);
    attempts = LockAttempts(this.globalDb);
  }

  static const sidebarMinWidth = 200.0;
  static const sidebarMaxWidth = 400.0;
  static const sidebarDefaultWidth = 268.0;
  static const listMinWidth = 240.0;
  static const listMaxWidth = 480.0;
  static const listDefaultWidth = 320.0;
  static const contentMinWidth = 360.0;
  static const uiFontInter = 'inter';
  static const uiFontMiSans = 'misans';
  static const uiFontCascadia = 'cascadia';
  static const localFontPrefix = 'local:';
  static const fontScaleMin = 0.85;
  static const fontScaleMax = 1.4;
  static const fontScaleDefault = 1.0;
  static const noteFontSizeMin = 14.0;
  static const noteFontSizeMax = 24.0;
  static const noteFontSizeDefault = 18.0;
  static const narrowStartupNote = 'note';
  static const narrowStartupList = 'list';
  static const bgThemeDefault = shellBgLavender;
  static const bgScopePane = 'pane';
  static const bgScopeFull = 'full';
  static const bgScopeEmpty = 'empty';
  static const bgScopeDefault = bgScopeFull;
  static const clipPortDefault = 41190;
  static const clipPortMin = 1024;
  static const clipPortMax = 65535;
  static const lockLeasePresets = [5, 10, 15, 30, 60, 0];
  static const lockLeaseDefaultMinutes = 10;
  static const _leaseSweepInterval = Duration(seconds: 5);
  static const _notebookScopePrefix = 'notebook:';
  static const _appLeaseKey = 'app';
  static const _appActivityThrottleMs = 15000;

  final AppDb db;
  final AppDb globalDb;
  final String? spaceId;
  late final LockAttempts attempts;

  late final SyncEngine sync;

  AttachmentStore? attachments;
  LocalFontStore? fonts;
  final LocalFontStore? fontStoreOverride;

  List<Notebook> notebooks = [];
  NoteScope scope = const NoteScope.all();
  List<Note> notes = [];
  String? openNoteId;
  Set<String> searchScope = {};
  Map<String, String> lastOpenNote = {};
  String narrowStartup = narrowStartupNote;
  String bgTheme = bgThemeDefault;
  String bgScope = bgScopeDefault;
  Set<String> bgShapes = shellBgAllShapeIds.toSet();
  String defaultNoteFormat = AppDb.noteFormatMarkdown;
  bool _startupRestorePending = true;
  double sidebarWidth = sidebarDefaultWidth;
  double listWidth = listDefaultWidth;
  String uiFont = uiFontMiSans;
  double fontScale = fontScaleDefault;
  double noteFontSize = noteFontSizeDefault;
  bool clipEnabled = false;
  int clipPort = clipPortDefault;
  String clipToken = '';
  String? clipError;
  ClipServer? _clipServer;
  int lockLeaseMinutes = lockLeaseDefaultMinutes;
  bool appBackgroundLock = true;
  bool appBlurLock = true;
  bool lockBio = true;
  bool trustSystemLock = false;
  PasswordLock? appLock;
  PrivacySpaceRef? privacyRef;
  final Map<String, int> _unlockUntil = {};
  int _lastAppActivityTouch = 0;
  bool _sweepingLeases = false;
  Map<String, Note> _noteIndex = {};
  Timer? _leaseSweep;
  static const _leaseForever = 9007199254740991;
  VoidCallback? lockHandler;
  Future<void> Function()? onAppLocking;
  Future<void> Function()? destroyChildSpaceHandler;
  VoidCallback? switchSpaceHandler;

  bool get systemLockTrusted =>
      trustSystemLock && Biometrics.systemAppLockSupported;

  bool get isChildSpace => spaceId != null && spaceId!.isNotEmpty;

  Future<void> init() async {
    if (!kIsWeb) {
      attachments = await AttachmentStore.open(spaceId: spaceId);
      await purgeAttachments();
    } else {
      developer.log('skip, web 端附件存储未启用, 原因: 附件随同步阶段支持 web');
    }
    final savedLease =
        int.tryParse(await db.getSetting(AppDb.lockLeaseMinutesKey) ?? '');
    if (savedLease != null && lockLeasePresets.contains(savedLease)) {
      lockLeaseMinutes = savedLease;
    } else if (savedLease != null) {
      developer.log(
          'skip, 自动上锁时长非法回退默认, raw: $savedLease, fallback: $lockLeaseMinutes');
    }
    appBackgroundLock =
        await db.getSetting(AppDb.appBackgroundLockKey) != '0';
    final savedBlur = await db.getSetting(AppDb.appBlurLockKey);
    if (savedBlur != null) {
      appBlurLock = savedBlur != '0';
    } else {
      appBlurLock = appBackgroundLock;
      developer.log('done, 失焦即锁继承后台开关值, enabled: $appBlurLock');
    }
    lockBio = await globalDb.getSetting(AppDb.lockBioKey) != '0';
    trustSystemLock =
        await globalDb.getSetting(AppDb.trustSystemLockKey) == '1';
    await reloadLockMarkers();
    notebooks = await db.listNotebooks();
    sidebarWidth = _loadedDouble(await db.getSetting(AppDb.paneWidthSidebarKey),
        sidebarDefaultWidth, sidebarMinWidth, sidebarMaxWidth);
    listWidth = _loadedDouble(await db.getSetting(AppDb.paneWidthListKey),
        listDefaultWidth, listMinWidth, listMaxWidth);
    final savedFont = await db.getSetting(AppDb.uiFontKey);
    if (!kIsWeb) {
      fonts = fontStoreOverride ?? await LocalFontStore.open();
      await fonts!.loadRegistry(db);
      await fonts!.registerAll();
    }
    if (savedFont == uiFontInter ||
        savedFont == uiFontMiSans ||
        savedFont == uiFontCascadia ||
        _isRegisteredLocalFont(savedFont)) {
      uiFont = savedFont!;
    } else if (savedFont != null) {
      developer.log('skip, 字体设置非法回退默认, raw: $savedFont, fallback: $uiFont');
    }
    final savedFormat = await db.getSetting(AppDb.defaultNoteFormatKey);
    if (savedFormat == AppDb.noteFormatMarkdown ||
        savedFormat == AppDb.noteFormatRichtext) {
      defaultNoteFormat = savedFormat!;
    } else if (savedFormat != null) {
      developer.log(
          'skip, 默认笔记格式非法回退默认, raw: $savedFormat, fallback: $defaultNoteFormat');
    }
    fontScale = _loadedDouble(await db.getSetting(AppDb.uiFontScaleKey),
        fontScaleDefault, fontScaleMin, fontScaleMax);
    noteFontSize = _loadedDouble(await db.getSetting(AppDb.noteFontSizeKey),
        noteFontSizeDefault, noteFontSizeMin, noteFontSizeMax);
    final saved = await db.getSetting(AppDb.searchScopeKey);
    if (saved != null && saved.isNotEmpty) {
      searchScope = saved
          .split(',')
          .where((id) => notebooks.any((n) => n.id == id))
          .toSet();
    }
    final savedStartup = await db.getSetting(AppDb.narrowStartupKey);
    if (savedStartup == narrowStartupNote ||
        savedStartup == narrowStartupList) {
      narrowStartup = savedStartup!;
    } else if (savedStartup != null) {
      developer.log(
          'skip, 窄屏启动设置非法回退默认, raw: $savedStartup, fallback: $narrowStartup');
    }
    final savedBgTheme = await db.getSetting(AppDb.bgThemeKey);
    if (savedBgTheme != null && isKnownShellBgTheme(savedBgTheme)) {
      bgTheme = savedBgTheme;
    } else if (savedBgTheme != null) {
      developer.log(
          'skip, 背景主题设置非法回退默认, raw: $savedBgTheme, fallback: $bgTheme');
    }
    final savedBgScope = await db.getSetting(AppDb.bgScopeKey);
    if (savedBgScope == bgScopePane ||
        savedBgScope == bgScopeFull ||
        savedBgScope == bgScopeEmpty) {
      bgScope = savedBgScope!;
    } else if (savedBgScope != null) {
      developer.log(
          'skip, 背景范围设置非法回退默认, raw: $savedBgScope, fallback: $bgScope');
    }
    final savedBgShapes = await db.getSetting(AppDb.bgShapesKey);
    final sanitizedShapes = sanitizeShellBgShapes(savedBgShapes);
    if (sanitizedShapes != null) {
      bgShapes = sanitizedShapes.isEmpty
          ? <String>{}
          : sanitizedShapes.split(',').toSet();
    } else if (savedBgShapes != null) {
      developer.log(
          'skip, 背景形状设置非法回退全选, raw: $savedBgShapes');
    }
    if (isDesktopWindow) {
      clipEnabled = await db.getSetting(AppDb.clipEnabledKey) == '1';
      clipPort = _loadedDouble(await db.getSetting(AppDb.clipPortKey),
              clipPortDefault.toDouble(), clipPortMin.toDouble(), clipPortMax.toDouble())
          .round();
      clipToken = await db.getSetting(AppDb.clipTokenKey) ?? '';
      if (clipToken.isEmpty) {
        clipToken = _newClipToken();
        await db.setSetting(AppDb.clipTokenKey, clipToken);
        developer.log('done, 首次生成剪藏配对令牌, tokenLength: ${clipToken.length}');
      }
    }
    final savedScope = _parseScope(await db.getSetting(AppDb.lastViewScopeKey));
    if (savedScope != null) {
      scope = savedScope;
      developer.log(
          'done, 启动恢复上次作用域, scope: ${scope.kind.name}, notebookId: ${scope.notebookId}');
    }
    for (final entry in (await db.listLastOpenNotes()).entries) {
      if (entry.key == AppDb.allNotesScopeKey ||
          notebooks.any((n) => n.id == entry.key)) {
        lastOpenNote[entry.key] = entry.value;
      }
    }
    await refresh();
    if (appLock?.active == true && !systemLockTrusted) {
      grantAppUnlock();
    }
    if (clipEnabled) {
      await _startClipServer();
    }
    await sync.init();
    unawaited(sync.requestSync('startup').then(_applyOutcome));
  }

  bool _disposed = false;

  bool get isDisposed => _disposed;

  void _onSyncChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> reloadLockMarkers() async {
    appLock = PasswordLock.parse(await db.getSetting(AppDb.appLockKey));
    privacyRef =
        PrivacySpaceRef.parse(await db.getSetting(AppDb.privacySpaceKey));
  }

  Future<void> _applyOutcome(SyncOutcome outcome) async {
    if (_disposed) {
      return;
    }
    if (outcome.changedLocal) {
      developer.log('hit, 同步改动了本地数据刷新界面, reason: 同步回调');
      await reloadLockMarkers();
      await refresh();
    }
  }

  Future<void> _pullBeforeWrite(String op) async {
    final outcome = await sync.requestSync('beforeWrite:$op');
    if (outcome.error != null) {
      developer.log(
          'skip, 写前同步失败放行离线写入, op: $op, err: ${outcome.error}');
    }
    await _applyOutcome(outcome);
  }

  void _pushAfterWrite(String op) {
    unawaited(sync.requestSync('afterWrite:$op').then(_applyOutcome));
  }

  @override
  void dispose() {
    _disposed = true;
    _leaseSweep?.cancel();
    _leaseSweep = null;
    unawaited(_clipServer?.stop());
    _clipServer = null;
    sync.removeListener(_onSyncChanged);
    sync.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    notebooks = await db.listNotebooks();
    _noteIndex = {for (final n in await db.listAllNotes()) n.id: n};
    if (scope.kind == NoteScopeKind.notebook &&
        !notebooks.any((n) => n.id == scope.notebookId)) {
      developer.log('hit, 当前笔记本已不存在回到全部, notebookId: ${scope.notebookId}');
      scope = const NoteScope.all();
    }
    if (scope.kind == NoteScopeKind.notebook &&
        isNotebookLocked(scope.notebookId!)) {
      developer.log(
          'hit, 当前笔记本已上锁回到全部, notebookId: ${scope.notebookId}');
      scope = const NoteScope.all();
    }
    final openId = openNoteId;
    if (openId != null) {
      final openNote = _noteIndex[openId];
      if (openNote == null || openNote.deletedAt != null) {
        developer.log('hit, 打开中的笔记已不在列表关闭, noteId: $openId');
        openNoteId = null;
      } else if (isNoteLocked(openId)) {
        developer.log('hit, 打开中的笔记已上锁关闭, noteId: $openId');
        openNoteId = null;
      }
    }
    notes = switch (scope.kind) {
      NoteScopeKind.all => await db.listNotes(),
      NoteScopeKind.notebook =>
        await db.listNotes(notebookId: scope.notebookId),
      NoteScopeKind.trash => await db.listTrash(),
    };
    _pruneUnlocks();
    notifyListeners();
  }

  void _pruneUnlocks() {
    final aliveNoteIds = {for (final n in notebooks) n.id};
    _unlockUntil.removeWhere((key, _) =>
        key.startsWith(_notebookScopePrefix) &&
        !aliveNoteIds.contains(key.substring(_notebookScopePrefix.length)));
  }

  PasswordLock? notebookLock(String notebookId) =>
      PasswordLock.parse(_notebook(notebookId)?.lock);

  PasswordLock? noteLock(String noteId) =>
      PasswordLock.parse(_noteIndex[noteId]?.lock);

  bool _leaseHeld(String key) {
    final until = _unlockUntil[key];
    if (until == null) {
      return false;
    }
    if (until <= db.clock()) {
      _unlockUntil.remove(key);
      return false;
    }
    return true;
  }

  bool isNotebookLocked(String notebookId) {
    if (systemLockTrusted) {
      return false;
    }
    final lock = notebookLock(notebookId);
    if (lock == null || !lock.active) {
      return false;
    }
    return !_leaseHeld('$_notebookScopePrefix$notebookId');
  }

  bool isNoteLocked(String noteId) {
    if (systemLockTrusted) {
      return false;
    }
    final note = _noteIndex[noteId];
    if (note == null) {
      return false;
    }
    if (isNotebookLocked(note.notebookId)) {
      return true;
    }
    final lock = PasswordLock.parse(note.lock);
    if (lock == null || !lock.active) {
      return false;
    }
    return !_leaseHeld('note:$noteId');
  }

  void grantUnlock(String key, {bool notify = true}) {
    if (lockLeaseMinutes <= 0) {
      _unlockUntil[key] = _leaseForever;
    } else {
      _unlockUntil[key] = db.clock() + lockLeaseMinutes * 60000;
      _leaseSweep ??=
          Timer.periodic(_leaseSweepInterval, (_) => sweepLeases());
    }
    developer.log(
        'done, 解锁租期已授予, key: $key, leaseMinutes: $lockLeaseMinutes');
    if (notify) {
      notifyListeners();
    }
  }

  void grantNotebookUnlock(String notebookId) =>
      grantUnlock('$_notebookScopePrefix$notebookId');

  void grantNoteUnlock(String noteId) => grantUnlock('note:$noteId');

  void grantAppUnlock() => grantUnlock(_appLeaseKey);

  Note? noteById(String noteId) => _noteIndex[noteId];

  void touchLease(String key) {
    if (_unlockUntil.containsKey(key)) {
      grantUnlock(key, notify: false);
    }
  }

  void touchNote(String noteId) {
    if (isNoteLocked(noteId)) {
      return;
    }
    touchLease('note:$noteId');
    final note = _noteIndex[noteId];
    if (note != null) {
      touchLease('$_notebookScopePrefix${note.notebookId}');
    }
  }

  void touchAppActivity() {
    if (!_unlockUntil.containsKey(_appLeaseKey)) {
      return;
    }
    final now = db.clock();
    if (now - _lastAppActivityTouch < _appActivityThrottleMs) {
      return;
    }
    _lastAppActivityTouch = now;
    _unlockUntil[_appLeaseKey] = lockLeaseMinutes <= 0
        ? _leaseForever
        : now + lockLeaseMinutes * 60000;
  }

  void sweepLeases() {
    if (_sweepingLeases) {
      return;
    }
    final now = db.clock();
    final expired = [
      for (final entry in _unlockUntil.entries)
        if (entry.value <= now) entry.key,
    ];
    if (expired.isEmpty) {
      return;
    }
    _sweepingLeases = true;
    for (final key in expired) {
      _unlockUntil.remove(key);
    }
    developer.log(
        'hit, 解锁租期到期自动上锁, expired: ${expired.join(",")}');
    if (expired.contains(_appLeaseKey) && appLock?.active == true) {
      developer.log('hit, App 空闲租期到期回到锁屏');
      unawaited(lockApp().whenComplete(() => _sweepingLeases = false));
      return;
    }
    if (expired.every((k) => k.startsWith(_notebookScopePrefix))) {
      final openId = openNoteId;
      final openNote = openId == null ? null : _noteIndex[openId];
      if (openNote == null ||
          !expired.contains('$_notebookScopePrefix${openNote.notebookId}')) {
        _sweepingLeases = false;
        notifyListeners();
        return;
      }
    }
    unawaited(_closeForRelock().whenComplete(() => _sweepingLeases = false));
  }

  Future<void> _closeForRelock() async {
    final openId = openNoteId;
    if (openId != null && isNoteLocked(openId)) {
      await onAppLocking?.call();
      openNoteId = null;
      developer.log('hit, 租期到期关闭打开中的笔记, noteId: $openId');
    }
    if (scope.kind == NoteScopeKind.notebook &&
        isNotebookLocked(scope.notebookId!)) {
      scope = const NoteScope.all();
      await refresh();
      return;
    }
    notifyListeners();
  }

  Future<void> lockApp() async {
    await onAppLocking?.call();
    if (_disposed) {
      developer.log('skip, 重复锁定请求落在已销毁状态上');
      return;
    }
    _unlockUntil.clear();
    _leaseSweep?.cancel();
    _leaseSweep = null;
    openNoteId = null;
    developer.log('recv, 应用已锁定清空全部解锁租期');
    notifyListeners();
    lockHandler?.call();
  }

  Future<void> setLockLeaseMinutes(int minutes) async {
    if (!lockLeasePresets.contains(minutes) || minutes == lockLeaseMinutes) {
      return;
    }
    lockLeaseMinutes = minutes;
    await db.setSetting(AppDb.lockLeaseMinutesKey, '$minutes');
    if (minutes <= 0) {
      _leaseSweep?.cancel();
      _leaseSweep = null;
      for (final key in _unlockUntil.keys.toList()) {
        _unlockUntil[key] = _leaseForever;
      }
    } else {
      final until = db.clock() + minutes * 60000;
      for (final key in _unlockUntil.keys.toList()) {
        _unlockUntil[key] = until;
      }
      _leaseSweep ??=
          Timer.periodic(_leaseSweepInterval, (_) => sweepLeases());
    }
    developer.log('done, 自动上锁时长已更新, minutes: $minutes');
    notifyListeners();
  }

  Future<void> setAppBackgroundLock(bool enabled) async {
    if (enabled == appBackgroundLock) {
      return;
    }
    appBackgroundLock = enabled;
    await db.setSetting(AppDb.appBackgroundLockKey, enabled ? '1' : '0');
    developer.log('done, 切后台即锁已更新, enabled: $enabled');
    notifyListeners();
  }

  Future<void> setAppBlurLock(bool enabled) async {
    if (enabled == appBlurLock) {
      return;
    }
    appBlurLock = enabled;
    await db.setSetting(AppDb.appBlurLockKey, enabled ? '1' : '0');
    developer.log('done, 失焦即锁已更新, enabled: $enabled');
    notifyListeners();
  }

  Future<void> setLockBio(bool enabled) async {
    if (enabled == lockBio) {
      return;
    }
    lockBio = enabled;
    await globalDb.setSetting(AppDb.lockBioKey, enabled ? '1' : '0');
    developer.log('done, 生物识别解锁已更新, enabled: $enabled');
    notifyListeners();
  }

  Future<void> setTrustSystemLock(bool enabled) async {
    if (enabled == trustSystemLock) {
      return;
    }
    trustSystemLock = enabled;
    await globalDb.setSetting(AppDb.trustSystemLockKey, enabled ? '1' : '0');
    if (systemLockTrusted) {
      _unlockUntil.remove(_appLeaseKey);
    } else if (appLock?.active == true) {
      grantAppUnlock();
    }
    developer.log('done, 信任系统应用锁已更新, enabled: $enabled');
    notifyListeners();
  }

  Future<void> markBioSpace() async {
    await globalDb.setSetting(AppDb.lockBioSpaceKey, spaceId ?? '');
  }

  Future<void> setNotebookPassword(String id, String password) async {
    await _pullBeforeWrite('setNotebookPassword');
    final lock = PasswordLock.create(password, db.clock());
    await db.setNotebookLock(id, lock.encode());
    await refresh();
    grantUnlock('$_notebookScopePrefix$id');
    _pushAfterWrite('setNotebookPassword');
  }

  Future<void> removeNotebookPassword(String id) async {
    await _pullBeforeWrite('removeNotebookPassword');
    await db.setNotebookLock(id, null);
    _unlockUntil.remove('$_notebookScopePrefix$id');
    await refresh();
    _pushAfterWrite('removeNotebookPassword');
  }

  Future<void> setNotePassword(String id, String password) async {
    await _pullBeforeWrite('setNotePassword');
    final lock = PasswordLock.create(password, db.clock());
    await db.setNoteLock(id, lock.encode());
    await refresh();
    grantUnlock('note:$id');
    _pushAfterWrite('setNotePassword');
  }

  Future<void> removeNotePassword(String id) async {
    await _pullBeforeWrite('removeNotePassword');
    await db.setNoteLock(id, null);
    _unlockUntil.remove('note:$id');
    await refresh();
    _pushAfterWrite('removeNotePassword');
  }

  Future<void> setAppPassword(String password) async {
    await _pullBeforeWrite('setAppPassword');
    final lock = PasswordLock.create(password, db.clock());
    await db.setSetting(AppDb.appLockKey, lock.encode());
    appLock = lock;
    if (!systemLockTrusted) {
      grantAppUnlock();
    }
    if (isChildSpace) {
      await _writeBackSpaceLock(lock);
    }
    _pushAfterWrite('setAppPassword');
    developer.log('done, App 密码已设置');
    notifyListeners();
  }

  Future<void> _writeBackSpaceLock(PasswordLock lock) async {
    final parentId = await db.getSetting(AppDb.spaceParentKey) ?? '';
    final parentDb = parentId.isEmpty
        ? globalDb
        : AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(parentId)));
    try {
      final ref = PrivacySpaceRef.parse(
          await parentDb.getSetting(AppDb.privacySpaceKey));
      if (ref == null || !ref.active || ref.id != spaceId) {
        developer.log(
            'skip, 父级注册表无本空间记录不回写, spaceId: $spaceId, parentSpaceId: $parentId');
        return;
      }
      final updated = PrivacySpaceRef(
          id: ref.id, lock: lock, createAt: ref.createAt);
      await parentDb.setSetting(AppDb.privacySpaceKey, updated.encode());
      developer.log(
          'done, 子空间密码已回写父级注册表, spaceId: $spaceId, parentSpaceId: $parentId');
    } finally {
      if (parentId.isNotEmpty) {
        await parentDb.close();
      }
    }
  }

  Future<void> removeAppPassword() async {
    if (isChildSpace) {
      final handler = destroyChildSpaceHandler;
      if (handler != null) {
        await handler();
      }
      return;
    }
    final privacy = PrivacySpaceRef.parse(
        await db.getSetting(AppDb.privacySpaceKey));
    if (privacy != null && privacy.active) {
      developer.log('skip, 存在隐私空间禁止移除 App 密码');
      throw StateError('privacy space exists');
    }
    await _pullBeforeWrite('removeAppPassword');
    final cleared = PasswordLock.clearedAt(db.clock());
    await db.setSetting(AppDb.appLockKey, cleared.encode());
    appLock = cleared;
    _unlockUntil.remove(_appLeaseKey);
    _pushAfterWrite('removeAppPassword');
    developer.log('done, App 密码已移除');
    notifyListeners();
  }

  Future<PrivacySpaceRef> createPrivacySpace(String password) async {
    if (appLock == null || !appLock!.active) {
      developer.log('skip, 未设置 App 密码不能创建隐私空间');
      throw StateError('app password required');
    }
    final existing = PrivacySpaceRef.parse(
        await db.getSetting(AppDb.privacySpaceKey));
    if (existing != null && existing.active) {
      developer.log('skip, 隐私空间已存在不重复创建');
      throw StateError('privacy space exists');
    }
    await _pullBeforeWrite('createPrivacySpace');
    final id = const Uuid().v4();
    final now = db.clock();
    final ref = PrivacySpaceRef(
        id: id, lock: PasswordLock.create(password, now), createAt: now);
    await sync.provisionPrivacySpace(ref);
    await db.setSetting(AppDb.privacySpaceKey, ref.encode());
    privacyRef = ref;
    _pushAfterWrite('createPrivacySpace');
    developer.log('done, 隐私空间已创建, spaceId: $id');
    notifyListeners();
    return ref;
  }

  Future<void> deletePrivacySpace() async {
    final ref = PrivacySpaceRef.parse(
        await db.getSetting(AppDb.privacySpaceKey));
    if (ref == null || !ref.active) {
      return;
    }
    await _pullBeforeWrite('deletePrivacySpace');
    await sync.destroyPrivacySpaceData(ref.id);
    final cleared = PrivacySpaceRef.clearedAt(db.clock());
    await db.setSetting(AppDb.privacySpaceKey, cleared.encode());
    privacyRef = cleared;
    _pushAfterWrite('deletePrivacySpace');
    developer.log('done, 隐私空间已销毁, spaceId: ${ref.id}');
    notifyListeners();
  }

  bool get startupRestorePending => _startupRestorePending;

  Future<void> resolveStartupRestore({required bool isWide}) async {
    if (!_startupRestorePending) {
      return;
    }
    _startupRestorePending = false;
    if (!isWide && narrowStartup == narrowStartupList) {
      developer.log('skip, 窄屏启动设置为先看列表, scope: ${scope.kind.name}');
      notifyListeners();
      return;
    }
    final remembered = await db.getSetting(AppDb.lastViewNoteKey);
    if (openNoteId != null) {
      return;
    }
    final hit = notes.where((n) => n.id == remembered).firstOrNull;
    if (hit == null || isNoteLocked(hit.id)) {
      if (remembered != null) {
        developer.log(
            'skip, 上次打开的笔记已不在列表或已上锁, scope: ${scope.kind.name}, staleNoteId: $remembered, locked: ${hit != null}');
      }
      notifyListeners();
      return;
    }
    openNoteId = hit.id;
    developer.log(
        'done, 启动恢复上次页面, scope: ${scope.kind.name}, notebookId: ${scope.notebookId}, noteId: ${hit.id}');
    notifyListeners();
  }

  Future<void> selectScope(NoteScope next, {bool verified = false}) async {
    _startupRestorePending = false;
    if (!verified &&
        next.kind == NoteScopeKind.notebook &&
        isNotebookLocked(next.notebookId!)) {
      developer.log(
          'skip, 笔记本已上锁先解锁再进入, notebookId: ${next.notebookId}');
      notifyListeners();
      return;
    }
    scope = next;
    openNoteId = null;
    if (next.kind == NoteScopeKind.notebook) {
      touchLease('$_notebookScopePrefix${next.notebookId}');
    }
    await refresh();
    await _persistView();
  }

  void autoOpenCurrentScope() {
    final id = _resolveAutoOpen();
    if (id == null || id == openNoteId) {
      return;
    }
    openNoteId = id;
    developer.log(
        'hit, 宽屏自动打开笔记, scope: ${scope.kind.name}, notebookId: ${scope.notebookId}, noteId: $id');
    notifyListeners();
  }

  Future<Notebook> createNotebook(String name) async {
    await _pullBeforeWrite('createNotebook');
    final notebook = await db.createNotebook(name);
    await refresh();
    _pushAfterWrite('createNotebook');
    return notebook;
  }

  Future<void> renameNotebook(String id, String name) async {
    if (isNotebookLocked(id)) {
      developer.log('skip, 笔记本已上锁拦截重命名, notebookId: $id');
      return;
    }
    await _pullBeforeWrite('renameNotebook');
    await db.renameNotebook(id, name);
    await refresh();
    _pushAfterWrite('renameNotebook');
  }

  Future<void> setNotebookColor(String id, int color) async {
    if (isNotebookLocked(id)) {
      developer.log('skip, 笔记本已上锁拦截改色, notebookId: $id');
      return;
    }
    await _pullBeforeWrite('setNotebookColor');
    await db.setNotebookColor(id, color);
    await refresh();
    _pushAfterWrite('setNotebookColor');
  }

  Future<void> moveNotebook(String id, int delta) async {
    await _pullBeforeWrite('moveNotebook');
    await db.moveNotebook(id, delta);
    await refresh();
    _pushAfterWrite('moveNotebook');
  }

  Future<void> moveNote(String id, int delta) async {
    await _pullBeforeWrite('moveNote');
    await db.moveNote(id, delta);
    await refresh();
    _pushAfterWrite('moveNote');
  }

  Future<void> deleteNotebook(String id) async {
    if (isNotebookLocked(id)) {
      developer.log('skip, 笔记本已上锁拦截删除, notebookId: $id');
      return;
    }
    await _pullBeforeWrite('deleteNotebook');
    await db.deleteNotebook(id);
    lastOpenNote.remove(id);
    await db.clearLastOpenNote(id);
    await refresh();
    await _persistView();
    _pushAfterWrite('deleteNotebook');
  }

  Future<Note?> createNote() async {
    if (notebooks.isEmpty) {
      developer.log('skip, 没有笔记本无法新建笔记, notebookCount: 0');
      return null;
    }
    final target = scope.kind == NoteScopeKind.notebook
        ? scope.notebookId!
        : notebooks.first.id;
    if (isNotebookLocked(target)) {
      developer.log('skip, 目标笔记本已上锁无法新建, notebookId: $target');
      return null;
    }
    await _pullBeforeWrite('createNote');
    final note = await db.createNote(target, format: defaultNoteFormat);
    await refresh();
    await openNote(note.id);
    _pushAfterWrite('createNote');
    return note;
  }

  Future<Note> clipNote(
      {required String notebookId,
      required String title,
      required String markdown,
      String? sourceUrl}) async {
    if (!notebooks.any((n) => n.id == notebookId)) {
      throw ClipException(404, '笔记本不存在，请在插件里刷新后重选');
    }
    if (isNotebookLocked(notebookId)) {
      throw ClipException(403, '笔记本已上锁，请先在应用内解锁');
    }
    final body = markdown.trim();
    final url = sourceUrl?.trim() ?? '';
    if (body.isEmpty && url.isEmpty) {
      throw ClipException(400, '剪藏内容为空');
    }
    final link = url.isEmpty ? '' : '<$url>';
    final content =
        body.isEmpty ? link : (link.isEmpty ? body : '$link\n\n$body');
    await _pullBeforeWrite('clipNote');
    final note =
        await db.createNote(notebookId, title: title.trim(), content: content);
    await refresh();
    _pushAfterWrite('clipNote');
    return note;
  }

  Future<bool> saveNote(String id, String title, String content,
      {bool coalesce = true}) async {
    final before = await db.getNote(id);
    final base = await db.syncBaseContent(id);
    await _pullBeforeWrite('saveNote');
    final current = await db.findNote(id);
    if (current == null) {
      developer.log('hit, 保存时远端已删除该笔记按本地改动优先复活, noteId: $id');
      await db.applyRemoteNote(id, before.notebookId, title, content,
          before.sortKey, before.createAt, db.clock(), before.deletedAt,
          format: before.format);
      await db.removeTombstone(id);
      await refresh();
      _pushAfterWrite('saveNote');
      return true;
    }
    final nextTitle = title == before.title ? current.title : title;
    var nextContent = content;
    List<Map<String, dynamic>>? conflictSegments;
    if (content == before.content) {
      nextContent = current.content;
    } else if (current.content != before.content) {
      final merge = diff3Merge(
          base?.content ?? before.content, content, current.content);
      if (merge.hasConflict) {
        conflictSegments = [
          for (final segment in merge.segments)
            segment.isConflict
                ? {
                    'conflict': true,
                    'local': segment.local,
                    'remote': segment.remote,
                  }
                : {'conflict': false, 'text': segment.text},
        ];
      } else {
        nextContent = merge.autoMerged;
        developer.log(
            'done, 保存时远端已更新 diff3 自动合并, noteId: $id, mergedLength: ${nextContent.length}');
      }
    }
    final saved =
        await db.saveNote(id, nextTitle, nextContent, coalesce: coalesce);
    if (conflictSegments != null) {
      final stateRow = (await db.syncStateMap())[id];
      final remoteMeta = stateRow == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              jsonDecode(stateRow.baseJson) as Map<String, dynamic>)
            ..remove('content');
      await db.setConflict(id, {
        'remoteMeta': remoteMeta,
        'remoteContent': current.content,
        'localUpdateAt': (await db.getNote(id)).updateAt,
        'segments': conflictSegments,
      });
      developer.log(
          'hit, 保存内容与远端更新冲突进入裁决面板, noteId: $id, conflictCount: ${conflictSegments.where((s) => s['conflict'] == true).length}');
    }
    if (saved || conflictSegments != null) {
      await refresh();
      _pushAfterWrite('saveNote');
    }
    return saved;
  }

  Future<bool> restoreVersion(String noteId, String versionId) async {
    await _pullBeforeWrite('restoreVersion');
    final restored = await db.restoreVersion(noteId, versionId);
    if (restored) {
      await refresh();
      _pushAfterWrite('restoreVersion');
    }
    return restored;
  }

  Future<void> resolveConflict(String noteId, List<bool> pickLocal) async {
    await sync.resolveConflict(noteId, pickLocal);
    await refresh();
  }

  Future<void> openNote(String id, {bool verified = false}) async {
    _startupRestorePending = false;
    if (!verified && isNoteLocked(id)) {
      developer.log('skip, 笔记已上锁先解锁再打开, noteId: $id');
      notifyListeners();
      return;
    }
    openNoteId = id;
    touchNote(id);
    notifyListeners();
    final note = notes.where((n) => n.id == id).firstOrNull;
    if (note != null) {
      await _rememberOpen(note);
    }
    await _persistView();
  }

  Future<void> _rememberOpen(Note note) async {
    developer.log(
        'done, 记录作用域最近打开, notebookId: ${note.notebookId}, noteId: ${note.id}');
    lastOpenNote[note.notebookId] = note.id;
    await db.setLastOpenNote(note.notebookId, note.id);
    if (scope.kind == NoteScopeKind.all) {
      lastOpenNote[AppDb.allNotesScopeKey] = note.id;
      await db.setLastOpenNote(AppDb.allNotesScopeKey, note.id);
    }
  }

  Future<void> closeNote() async {
    _startupRestorePending = false;
    openNoteId = null;
    notifyListeners();
    await _persistView();
  }

  Future<void> trashNote(String id, {bool verified = false}) async {
    if (!verified && isNoteLocked(id)) {
      developer.log('skip, 笔记已上锁拦截移入回收站, noteId: $id');
      return;
    }
    await _pullBeforeWrite('trashNote');
    await db.softDeleteNote(id);
    if (openNoteId == id) {
      openNoteId = null;
    }
    await refresh();
    await _persistView();
    _pushAfterWrite('trashNote');
  }

  Future<void> restoreNote(String id, {bool verified = false}) async {
    if (!verified && isNoteLocked(id)) {
      developer.log('skip, 笔记已上锁拦截恢复, noteId: $id');
      return;
    }
    await _pullBeforeWrite('restoreNote');
    await db.restoreNote(id);
    await refresh();
    await _persistView();
    _pushAfterWrite('restoreNote');
  }

  Future<void> hardDeleteNote(String id, {bool verified = false}) async {
    if (!verified && isNoteLocked(id)) {
      developer.log('skip, 笔记已上锁拦截彻底删除, noteId: $id');
      return;
    }
    await _pullBeforeWrite('hardDeleteNote');
    await db.hardDeleteNote(id);
    await db.addTombstone(id, AppDb.syncKindNote);
    if (openNoteId == id) {
      openNoteId = null;
    }
    await refresh();
    await _persistView();
    _pushAfterWrite('hardDeleteNote');
  }

  Future<SyncOutcome> syncNow(String reason) async {
    final outcome = await sync.requestSync(reason);
    await _applyOutcome(outcome);
    return outcome;
  }

  Future<SyncOutcome> rebuildFromRemote() async {
    final outcome = await sync.rebuildFromRemote();
    await refresh();
    return outcome;
  }

  Future<Map<String, dynamic>?> conflictPayload(String noteId) =>
      db.getConflict(noteId);

  Future<void> purgeAttachments() async {
    final store = attachments;
    if (store == null) {
      return;
    }
    await store.purgeUnreferenced(await db.allAttachmentRefs());
  }

  Future<List<Note>> search(String query) => db.searchNotes(query, searchScope);

  Future<void> setSearchScope(Set<String> ids) async {
    final allIds = notebooks.map((n) => n.id).toSet();
    final coversAll = ids.isNotEmpty && allIds.every(ids.contains);
    searchScope = coversAll ? <String>{} : ids;
    if (coversAll) {
      developer.log('hit, 勾选覆盖全部笔记本, 归一为搜索全部, count: ${ids.length}');
    }
    await db.setSetting(AppDb.searchScopeKey, searchScope.join(','));
    notifyListeners();
  }

  Future<void> setNarrowStartup(String value) async {
    if (value != narrowStartupNote && value != narrowStartupList) {
      developer.log('skip, 未知窄屏启动标识不写入, narrowStartup: $value');
      return;
    }
    if (value == narrowStartup) {
      return;
    }
    narrowStartup = value;
    await db.setSetting(AppDb.narrowStartupKey, value);
    developer.log('done, 窄屏启动页面已切换, narrowStartup: $value');
    notifyListeners();
  }

  Future<void> setBgTheme(String value) async {
    if (!isKnownShellBgTheme(value)) {
      developer.log('skip, 未知背景主题标识不写入, bgTheme: $value');
      return;
    }
    if (value == bgTheme) {
      return;
    }
    developer.log('done, 背景主题已切换, $bgTheme -> $value');
    bgTheme = value;
    await db.setSetting(AppDb.bgThemeKey, value);
    notifyListeners();
  }

  Future<void> setBgScope(String value) async {
    if (value != bgScopePane &&
        value != bgScopeFull &&
        value != bgScopeEmpty) {
      developer.log('skip, 未知背景范围标识不写入, bgScope: $value');
      return;
    }
    if (value == bgScope) {
      return;
    }
    developer.log('done, 背景范围已切换, $bgScope -> $value');
    bgScope = value;
    await db.setSetting(AppDb.bgScopeKey, value);
    notifyListeners();
  }

  Future<void> setBgShapes(Set<String> ids) async {
    for (final id in ids) {
      if (!isKnownShellBgShape(id)) {
        developer.log('skip, 未知背景形状标识不写入, bgShape: $id');
        return;
      }
    }
    final canonical =
        shellBgShapeKinds.where((k) => ids.contains(k.id)).map((k) => k.id);
    final value = canonical.join(',');
    final current = shellBgShapeKinds
        .where((k) => bgShapes.contains(k.id))
        .map((k) => k.id)
        .join(',');
    if (value == current) {
      return;
    }
    developer.log('done, 背景形状已切换, $current -> $value');
    bgShapes = ids.toSet();
    await db.setSetting(AppDb.bgShapesKey, value);
    notifyListeners();
  }

  Future<void> setDefaultNoteFormat(String format) async {
    if (format != AppDb.noteFormatMarkdown &&
        format != AppDb.noteFormatRichtext) {
      developer.log('skip, 默认笔记格式非法不写入, raw: $format');
      return;
    }
    if (format == defaultNoteFormat) {
      return;
    }
    defaultNoteFormat = format;
    await db.setSetting(AppDb.defaultNoteFormatKey, format);
    developer.log('done, 默认笔记格式已切换, defaultNoteFormat: $format');
    notifyListeners();
  }

  Future<void> setNoteFormat(String id, String format) async {
    if (format != AppDb.noteFormatMarkdown &&
        format != AppDb.noteFormatRichtext) {
      developer.log('skip, 笔记格式非法不写入, noteId: $id, raw: $format');
      return;
    }
    if (isNoteLocked(id)) {
      developer.log('skip, 笔记已上锁拦截格式切换, noteId: $id');
      return;
    }
    final note = await db.getNote(id);
    if (note.format == format) {
      developer.log('skip, 笔记格式未变化, noteId: $id, format: $format');
      return;
    }
    if (format == AppDb.noteFormatRichtext) {
      final normalized = richtextNormalize(note.content);
      if (normalized != note.content) {
        developer.log(
            'hit, 转富文本先规范化内容并记版本, noteId: $id, oldLength: ${note.content.length}, newLength: ${normalized.length}');
        await saveNote(id, note.title, normalized, coalesce: false);
      }
    }
    await _pullBeforeWrite('setNoteFormat');
    await db.setNoteFormat(id, format);
    await refresh();
    _pushAfterWrite('setNoteFormat');
    developer.log('done, 笔记格式已切换, noteId: $id, format: $format');
  }

  Future<void> setClipEnabled(bool enabled) async {
    if (enabled == clipEnabled) {
      return;
    }
    clipEnabled = enabled;
    await db.setSetting(AppDb.clipEnabledKey, enabled ? '1' : '0');
    if (enabled) {
      await _startClipServer();
    } else {
      await _clipServer?.stop();
      _clipServer = null;
      clipError = null;
      developer.log('done, 剪藏桥接已关闭');
      notifyListeners();
    }
  }

  Future<bool> setClipPort(int port) async {
    if (port < clipPortMin || port > clipPortMax) {
      developer.log(
          'skip, 剪藏端口越界不写入, port: $port, min: $clipPortMin, max: $clipPortMax');
      return false;
    }
    if (port == clipPort) {
      return true;
    }
    clipPort = port;
    await db.setSetting(AppDb.clipPortKey, '$port');
    developer.log('done, 剪藏端口已更新, port: $port');
    if (clipEnabled) {
      await _startClipServer();
    } else {
      notifyListeners();
    }
    return true;
  }

  Future<void> regenerateClipToken() async {
    clipToken = _newClipToken();
    await db.setSetting(AppDb.clipTokenKey, clipToken);
    developer.log('done, 剪藏配对令牌已重新生成, tokenLength: ${clipToken.length}');
    notifyListeners();
  }

  Future<void> _startClipServer() async {
    await _clipServer?.stop();
    _clipServer = null;
    final server = ClipServer(this);
    try {
      await server.start(clipPort);
      _clipServer = server;
      clipError = null;
      developer.log('done, 剪藏桥接已启动, port: $clipPort');
    } on SocketException catch (err) {
      clipError = '端口 $clipPort 启动失败：${err.osError?.message ?? err.message}';
      developer.log('fail, 剪藏桥接启动失败, port: $clipPort, err: $err');
    }
    notifyListeners();
  }

  String _newClipToken() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void updateSidebarWidth(double width) {
    final next = width.clamp(sidebarMinWidth, sidebarMaxWidth).toDouble();
    if (next == sidebarWidth) {
      return;
    }
    sidebarWidth = next;
    notifyListeners();
  }

  void updateListWidth(double width) {
    final next = width.clamp(listMinWidth, listMaxWidth).toDouble();
    if (next == listWidth) {
      return;
    }
    listWidth = next;
    notifyListeners();
  }

  bool _isRegisteredLocalFont(String? font) =>
      font != null &&
      font.startsWith(localFontPrefix) &&
      fonts?.has(font.substring(localFontPrefix.length)) == true;

  Future<void> setUiFont(String font) async {
    if (font != uiFontInter &&
        font != uiFontMiSans &&
        font != uiFontCascadia &&
        !_isRegisteredLocalFont(font)) {
      developer.log('skip, 未知字体标识不写入, font: $font');
      return;
    }
    if (font == uiFont) {
      return;
    }
    uiFont = font;
    await db.setSetting(AppDb.uiFontKey, font);
    developer.log('done, 界面字体已切换, uiFont: $font');
    notifyListeners();
  }

  Future<List<LocalFont>> importLocalFonts(List<String> paths) async {
    final store = fonts;
    if (store == null) {
      developer.log('skip, web 端无本地字体存储, count: ${paths.length}');
      return [];
    }
    final imported = await store.importFiles(paths);
    developer.log(
        'done, 本地字体导入完成, count: ${imported.length}, names: ${imported.map((f) => f.name).join(',')}');
    notifyListeners();
    return imported;
  }

  Future<LocalFont?> downloadCatalogFont(FontCatalogEntry catalog,
      {void Function(int received, int total)? onProgress}) async {
    final store = fonts;
    if (store == null) {
      developer.log('skip, web 端无本地字体存储, catalog: ${catalog.id}');
      return null;
    }
    final entry = await store.download(catalog, onProgress: onProgress);
    notifyListeners();
    return entry;
  }

  Future<void> deleteLocalFont(String id) async {
    final store = fonts;
    if (store == null) {
      return;
    }
    if (uiFont == '$localFontPrefix$id') {
      await setUiFont(uiFontMiSans);
    }
    await store.delete(id);
    notifyListeners();
  }

  void updateFontScale(double scale) {
    final next =
        (scale.clamp(fontScaleMin, fontScaleMax) * 100).roundToDouble() / 100;
    if (next == fontScale) {
      return;
    }
    fontScale = next;
    notifyListeners();
  }

  void updateNoteFontSize(double size) {
    final next = size.clamp(noteFontSizeMin, noteFontSizeMax).roundToDouble();
    if (next == noteFontSize) {
      return;
    }
    noteFontSize = next;
    notifyListeners();
  }

  Future<void> persistFontSizes() async {
    await db.setSetting(
        AppDb.uiFontScaleKey, fontScale.toStringAsFixed(2));
    await db.setSetting(
        AppDb.noteFontSizeKey, noteFontSize.round().toString());
    developer.log(
        'done, 字号设置已持久化, fontScale: $fontScale, noteFontSize: $noteFontSize');
  }

  Future<void> persistPaneWidths() async {
    await db.setSetting(
        AppDb.paneWidthSidebarKey, sidebarWidth.round().toString());
    await db.setSetting(AppDb.paneWidthListKey, listWidth.round().toString());
    developer.log(
        'done, 栏宽已持久化, sidebar: $sidebarWidth, list: $listWidth');
  }

  double _loadedDouble(String? raw, double fallback, double min, double max) {
    final parsed = raw == null ? null : double.tryParse(raw);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      if (raw != null) {
        developer.log('skip, 数值设置非法回退默认, raw: $raw, fallback: $fallback');
      }
      return fallback;
    }
    return parsed.clamp(min, max).toDouble();
  }

  Future<void> _persistView() async {
    final encoded = switch (scope.kind) {
      NoteScopeKind.all => AppDb.allNotesScopeKey,
      NoteScopeKind.trash => AppDb.trashScopeKey,
      NoteScopeKind.notebook => '$_notebookScopePrefix${scope.notebookId}',
    };
    await db.setSetting(AppDb.lastViewScopeKey, encoded);
    final id = openNoteId;
    if (id == null) {
      await db.deleteSetting(AppDb.lastViewNoteKey);
    } else {
      await db.setSetting(AppDb.lastViewNoteKey, id);
    }
  }

  NoteScope? _parseScope(String? raw) {
    if (raw == null) {
      return null;
    }
    if (raw == AppDb.allNotesScopeKey) {
      return const NoteScope.all();
    }
    if (raw == AppDb.trashScopeKey) {
      return const NoteScope.trash();
    }
    if (raw.startsWith(_notebookScopePrefix)) {
      final id = raw.substring(_notebookScopePrefix.length);
      if (notebooks.any((n) => n.id == id)) {
        return NoteScope.notebook(id);
      }
    }
    developer.log('skip, 上次页面作用域非法或笔记本已删回退全部, raw: $raw');
    return null;
  }

  String? _resolveAutoOpen() {
    if (scope.kind == NoteScopeKind.trash || notes.isEmpty) {
      return null;
    }
    final remembered = lastOpenNote[_lastOpenKey];
    final hit = notes.where((n) => n.id == remembered).firstOrNull;
    if (hit != null && !isNoteLocked(hit.id)) {
      return hit.id;
    }
    if (remembered != null) {
      developer.log(
          'skip, 记忆的笔记已不在列表或已上锁回退第一篇, scopeKey: $_lastOpenKey, staleNoteId: $remembered');
    }
    return notes.where((n) => !isNoteLocked(n.id)).firstOrNull?.id;
  }

  String get _lastOpenKey => scope.kind == NoteScopeKind.notebook
      ? scope.notebookId!
      : AppDb.allNotesScopeKey;

  Notebook? _notebook(String notebookId) =>
      notebooks.where((n) => n.id == notebookId).firstOrNull;

  String notebookName(String notebookId) =>
      _notebook(notebookId)?.name ?? '?';

  int notebookColor(String notebookId) =>
      _notebook(notebookId)?.color ?? notebookPalette.first;
}