import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/app_db.dart';
import '../data/attachment_store.dart';
import '../data/password_lock.dart';
import 'diff3.dart';
import 'oss_store.dart';
import 'remote_store.dart';
import 'sync_manifest.dart';
import 'webdav_store.dart';

class SyncOutcome {
  const SyncOutcome({
    required this.ran,
    this.changedLocal = false,
    this.uploadedNotes = 0,
    this.downloadedNotes = 0,
    this.uploadedAssets = 0,
    this.downloadedAssets = 0,
    this.conflicts = 0,
    this.error,
  });

  final bool ran;
  final bool changedLocal;
  final int uploadedNotes;
  final int downloadedNotes;
  final int uploadedAssets;
  final int downloadedAssets;
  final int conflicts;
  final String? error;

  bool get ok => ran && error == null;
}

class SyncEngine extends ChangeNotifier {
  SyncEngine(this.db,
      {AttachmentStore? Function()? attachments, this.storeOverride})
      : _attachments = attachments ?? (() => null);

  final AppDb db;
  final AttachmentStore? Function() _attachments;
  final RemoteStore? storeOverride;

  static const manifestFile = 'manifest.json';

  bool syncing = false;
  String? lastError;
  int? lastSyncAt;
  int remoteNoteCount = 0;
  int remoteNotebookCount = 0;
  int pollMinutes = 0;
  Set<String> conflictIds = {};

  RemoteStore? _store;
  String? _storeFingerprint;
  Timer? _pollTimer;
  Future<SyncOutcome>? _inFlight;
  bool _disposed = false;
  _CycleStats _stats = _CycleStats();

  Future<void> init() async {
    conflictIds = await db.conflictNoteIds();
    lastSyncAt = int.tryParse(await db.getSetting(AppDb.syncLastAtKey) ?? '');
    final cachedRaw = await db.getSetting(AppDb.syncManifestCacheKey);
    if (cachedRaw != null) {
      try {
        final cached = SyncManifest.decode(cachedRaw);
        remoteNoteCount = cached.notes.length;
        remoteNotebookCount = cached.notebooks.length;
      } catch (err) {
        developer.log('skip, 缓存 manifest 解析失败计数保持零, err: $err');
      }
    }
    await reloadConfig();
    developer.log(
        'done, 同步引擎就绪, pollMinutes: $pollMinutes, conflicts: ${conflictIds.length}');
  }

  Future<RemoteStore?> buildStore() async {
    if (storeOverride != null) {
      return storeOverride;
    }
    return _storeFromSettings(await db.allSettings());
  }

  RemoteStore? _storeFromSettings(Map<String, String> settings) {
    final protocol = settings[AppDb.syncProtocolKey] ?? AppDb.syncProtocolOff;
    if (protocol == AppDb.syncProtocolWebdav) {
      final url = (settings[AppDb.syncWebdavUrlKey] ?? '').trim();
      final user = settings[AppDb.syncWebdavUserKey] ?? '';
      if (url.isEmpty || user.isEmpty) {
        developer.log(
            'skip, WebDAV 配置不完整不建 store, urlEmpty: ${url.isEmpty}, userEmpty: ${user.isEmpty}');
        return null;
      }
      return WebdavStore(
        baseUrl: url,
        username: user,
        password: settings[AppDb.syncWebdavPassKey] ?? '',
        rootPath: WebdavStore.normalizeRoot(
            settings[AppDb.syncWebdavPathKey] ?? ''),
      );
    }
    if (protocol == AppDb.syncProtocolOss) {
      final endpoint = (settings[AppDb.syncOssEndpointKey] ?? '').trim();
      final bucket = (settings[AppDb.syncOssBucketKey] ?? '').trim();
      final ak = settings[AppDb.syncOssAkKey] ?? '';
      if (endpoint.isEmpty || bucket.isEmpty || ak.isEmpty) {
        developer.log(
            'skip, OSS 配置不完整不建 store, endpointEmpty: ${endpoint.isEmpty}, bucketEmpty: ${bucket.isEmpty}, akEmpty: ${ak.isEmpty}');
        return null;
      }
      return OssStore(
        endpoint: endpoint,
        bucket: bucket,
        accessKeyId: ak,
        accessKeySecret: settings[AppDb.syncOssSkKey] ?? '',
        prefix: OssStore.normalizePrefix(
            settings[AppDb.syncOssPrefixKey] ?? ''),
      );
    }
    return null;
  }

  Map<String, String> _childSyncSettings(
      Map<String, String> parent, String spaceId) {
    final child = <String, String>{};
    for (final key in const [
      AppDb.syncProtocolKey,
      AppDb.syncWebdavUrlKey,
      AppDb.syncWebdavUserKey,
      AppDb.syncWebdavPassKey,
      AppDb.syncWebdavPathKey,
      AppDb.syncOssEndpointKey,
      AppDb.syncOssBucketKey,
      AppDb.syncOssAkKey,
      AppDb.syncOssSkKey,
      AppDb.syncOssPrefixKey,
      AppDb.syncPollMinutesKey,
    ]) {
      final value = parent[key];
      if (value != null) {
        child[key] = value;
      }
    }
    final path = parent[AppDb.syncWebdavPathKey];
    if (path != null) {
      child[AppDb.syncWebdavPathKey] =
          '${WebdavStore.normalizeRoot(path)}/spaces/$spaceId';
    }
    final prefix = parent[AppDb.syncOssPrefixKey];
    if (prefix != null) {
      child[AppDb.syncOssPrefixKey] =
          '${OssStore.normalizePrefix(prefix)}/spaces/$spaceId';
    }
    return child;
  }

  Future<void> provisionPrivacySpace(PrivacySpaceRef ref) async {
    final parentSettings = await db.allSettings();
    final child = AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(ref.id)));
    try {
      final childLock =
          PasswordLock.parse(await child.getSetting(AppDb.appLockKey));
      if (childLock == null || ref.lock.updateAt > childLock.updateAt) {
        await child.setSetting(AppDb.appLockKey, ref.lock.encode());
      } else {
        developer.log(
            'skip, 子空间本地密码更新不回退, spaceId: ${ref.id}, childUpdateAt: ${childLock.updateAt}, refUpdateAt: ${ref.lock.updateAt}');
      }
      await child.setSetting(AppDb.spaceIdKey, ref.id);
      await child.setSetting(
          AppDb.spaceParentKey, parentSettings[AppDb.spaceIdKey] ?? '');
      for (final entry
          in _childSyncSettings(parentSettings, ref.id).entries) {
        await child.setSetting(entry.key, entry.value);
      }
      developer.log(
          'done, 隐私空间数据库已就绪, spaceId: ${ref.id}, parentSpaceId: ${parentSettings[AppDb.spaceIdKey] ?? ''}, protocol: ${parentSettings[AppDb.syncProtocolKey] ?? AppDb.syncProtocolOff}');
    } finally {
      await child.close();
    }
  }

  Future<void> destroyPrivacySpaceData(String spaceId) async {
    final parentSettings = await db.allSettings();
    final store =
        _storeFromSettings(_childSyncSettings(parentSettings, spaceId));
    if (store != null) {
      final read = await store.read(manifestFile);
      if (!read.missing && read.object != null) {
        final manifest = SyncManifest.decode(utf8.decode(read.object!.bytes));
        for (final id in manifest.notes.keys) {
          await store.remove(contentFileOf(id));
        }
        for (final assetId in manifest.assets) {
          await store.remove(assetFileOf(assetId));
        }
        await store.remove(manifestFile);
        developer.log(
            'done, 远端隐私空间数据已清理, spaceId: $spaceId, notes: ${manifest.notes.length}, assets: ${manifest.assets.length}');
      } else {
        developer.log('skip, 远端无隐私空间 manifest 只清本地, spaceId: $spaceId');
      }
    } else {
      developer.log('skip, 未配置同步远端只清本地空间, spaceId: $spaceId');
    }
    final child = AppDb(AppDb.openExecutor(name: AppDb.spaceDbName(spaceId)));
    try {
      await child.wipeSpaceData();
    } finally {
      await child.close();
    }
    developer.log('done, 隐私空间本地数据已销毁, spaceId: $spaceId');
  }

  Future<void> syncLockMarkers() async {
    final store = _store ?? await buildStore();
    if (store == null) {
      developer.log('skip, 未配置同步远端锁屏直接用本地密码标记');
      return;
    }
    try {
      final cachedEtag = await db.getSetting(AppDb.syncManifestEtagKey);
      final read = await store.read(manifestFile,
          ifNoneMatch: cachedEtag == null || cachedEtag.isEmpty
              ? null
              : cachedEtag);
      if (read.missing) {
        developer.log('skip, 远端无 manifest 锁屏用本地密码标记');
        return;
      }
      final SyncManifest remote;
      if (read.notModified) {
        final cachedRaw = await db.getSetting(AppDb.syncManifestCacheKey);
        if (cachedRaw == null) {
          developer.log('skip, manifest 304 但无缓存用本地密码标记');
          return;
        }
        remote = SyncManifest.decode(cachedRaw);
      } else {
        remote = SyncManifest.decode(utf8.decode(read.object!.bytes));
      }
      await _adoptLockMarkers(
          _newerLock(
              PasswordLock.parse(await db.getSetting(AppDb.appLockKey)),
              remote.appLock == null
                  ? null
                  : PasswordLock.fromJson(remote.appLock!)),
          _newerPrivacy(
              PrivacySpaceRef.parse(
                  await db.getSetting(AppDb.privacySpaceKey)),
              remote.privacy == null
                  ? null
                  : PrivacySpaceRef.fromJson(remote.privacy!)));
      developer.log('done, 锁屏前密码标记已对齐远端');
    } catch (err) {
      developer.log('skip, 锁屏前拉取密码标记失败回退本地离线解锁, err: $err');
    }
  }

  PasswordLock? _newerLock(PasswordLock? local, PasswordLock? remote) {
    if (local == null) {
      return remote;
    }
    if (remote == null) {
      return local;
    }
    return remote.updateAt > local.updateAt ? remote : local;
  }

  PrivacySpaceRef? _newerPrivacy(
      PrivacySpaceRef? local, PrivacySpaceRef? remote) {
    if (local == null) {
      return remote;
    }
    if (remote == null) {
      return local;
    }
    return remote.lock.updateAt > local.lock.updateAt ? remote : local;
  }

  Future<void> _adoptLockMarkers(
      PasswordLock? appLock, PrivacySpaceRef? privacy) async {
    final desiredApp = appLock?.encode();
    if (desiredApp != await db.getSetting(AppDb.appLockKey)) {
      if (desiredApp == null) {
        await db.deleteSetting(AppDb.appLockKey);
      } else {
        await db.setSetting(AppDb.appLockKey, desiredApp);
      }
      _stats.changedLocal = true;
      developer.log(
          'done, App 密码标记已随远端更新, active: ${appLock?.active ?? false}, cleared: ${appLock?.cleared ?? false}');
    }
    final desiredPrivacy = privacy?.encode();
    if (desiredPrivacy == await db.getSetting(AppDb.privacySpaceKey)) {
      return;
    }
    if (desiredPrivacy == null) {
      await db.deleteSetting(AppDb.privacySpaceKey);
    } else {
      await db.setSetting(AppDb.privacySpaceKey, desiredPrivacy);
    }
    _stats.changedLocal = true;
    if (privacy != null && privacy.active) {
      await provisionPrivacySpace(privacy);
    }
    developer.log(
        'done, 隐私空间标记已随远端更新, active: ${privacy?.active ?? false}, spaceId: ${privacy?.id ?? ''}');
  }

  Future<void> reloadConfig() async {
    final raw = await db.getSetting(AppDb.syncPollMinutesKey);
    final parsed = int.tryParse(raw ?? '') ?? 0;
    if (raw != null && (parsed < 0 || parsed > AppDb.syncPollMinutesMax)) {
      developer.log(
          'skip, 轮询分钟数非法回退关闭, raw: $raw, max: ${AppDb.syncPollMinutesMax}');
    }
    pollMinutes = parsed < 0 || parsed > AppDb.syncPollMinutesMax ? 0 : parsed;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (pollMinutes > 0) {
      _pollTimer = Timer.periodic(Duration(minutes: pollMinutes), (_) {
        developer.log('hit, 定时轮询触发同步, pollMinutes: $pollMinutes');
        requestSync('poll');
      });
      developer.log('done, 定时轮询已启动, pollMinutes: $pollMinutes');
    } else {
      developer.log('skip, 定时轮询关闭, pollMinutes: 0');
    }
    _store = await buildStore();
    _storeFingerprint = await _fingerprint();
    _safeNotify();
  }

  Future<String> _fingerprint() async {
    const keys = [
      AppDb.syncProtocolKey,
      AppDb.syncWebdavUrlKey,
      AppDb.syncWebdavUserKey,
      AppDb.syncWebdavPassKey,
      AppDb.syncWebdavPathKey,
      AppDb.syncOssEndpointKey,
      AppDb.syncOssBucketKey,
      AppDb.syncOssAkKey,
      AppDb.syncOssSkKey,
      AppDb.syncOssPrefixKey,
    ];
    final values = [for (final key in keys) await db.getSetting(key) ?? ''];
    return values.join('|');
  }

  Future<SyncOutcome> requestSync(String reason) async {
    if (_disposed) {
      return const SyncOutcome(ran: false);
    }
    while (_inFlight != null) {
      developer.log('hit, 同步进行中等待完成后合并执行, reason: $reason');
      await _inFlight;
      if (_disposed) {
        return const SyncOutcome(ran: false);
      }
    }
    final future = _run(reason);
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }
  }

  void _ensureAlive() {
    if (_disposed) {
      throw const _SyncAborted();
    }
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<SyncOutcome> _run(String reason) async {
    var outcome = const SyncOutcome(ran: true);
    var started = false;
    try {
      _ensureAlive();
      if (_store == null) {
        developer.log('skip, 未配置同步远端不执行, reason: $reason');
        return const SyncOutcome(ran: false);
      }
      final fingerprint = await _fingerprint();
      _ensureAlive();
      if (fingerprint != _storeFingerprint) {
        _store = await buildStore();
        _storeFingerprint = fingerprint;
      }
      final store = _store;
      if (store == null) {
        developer.log('skip, 同步配置已失效不执行, reason: $reason');
        return const SyncOutcome(ran: false);
      }
      syncing = true;
      started = true;
      lastError = null;
      _stats = _CycleStats();
      _safeNotify();
      developer.log('recv, 同步开始, reason: $reason, remote: ${store.describe}');
      await db.purgeExpired();
      final attachments = _attachments();
      if (attachments != null) {
        await attachments.purgeUnreferenced(await db.allAttachmentRefs());
      }
      _ensureAlive();
      await _syncOnce(store);
      _ensureAlive();
      lastSyncAt = db.clock();
      await db.setSetting(AppDb.syncLastAtKey, '$lastSyncAt');
      outcome = SyncOutcome(
        ran: true,
        changedLocal: _stats.changedLocal,
        uploadedNotes: _stats.uploadedNotes,
        downloadedNotes: _stats.downloadedNotes,
        uploadedAssets: _stats.uploadedAssets,
        downloadedAssets: _stats.downloadedAssets,
        conflicts: (await db.conflictNoteIds()).length,
      );
      developer.log(
          'done, 同步完成, reason: $reason, changedLocal: ${outcome.changedLocal}, uploadedNotes: ${outcome.uploadedNotes}, downloadedNotes: ${outcome.downloadedNotes}, uploadedAssets: ${outcome.uploadedAssets}, downloadedAssets: ${outcome.downloadedAssets}, conflicts: ${outcome.conflicts}');
    } on _SyncAborted {
      developer.log('skip, 引擎已释放中止本轮同步, reason: $reason');
      outcome = const SyncOutcome(ran: false);
    } catch (err) {
      lastError = '$err';
      outcome = SyncOutcome(ran: true, error: '$err');
      developer.log('fail, 同步失败本地数据保持不动, reason: $reason, err: $err');
    } finally {
      if (started) {
        syncing = false;
        if (!_disposed) {
          try {
            conflictIds = await db.conflictNoteIds();
          } catch (err) {
            developer.log('skip, 收尾读取冲突失败忽略, err: $err');
          }
        }
        _safeNotify();
      }
    }
    return outcome;
  }

  Future<void> _syncOnce(RemoteStore store) async {
    final cachedRaw = await db.getSetting(AppDb.syncManifestCacheKey);
    final cachedEtag = await db.getSetting(AppDb.syncManifestEtagKey);
    _ensureAlive();
    final read = await store.read(manifestFile,
        ifNoneMatch: cachedRaw != null ? cachedEtag : null);
    SyncManifest remote;
    String? remoteRaw;
    String? remoteEtag;
    if (read.missing) {
      developer.log('hit, 远端无 manifest 视为首次同步只上传不删除');
      remote = SyncManifest();
    } else if (read.notModified) {
      remote = SyncManifest.decode(cachedRaw!);
      remoteRaw = cachedRaw;
      remoteEtag = cachedEtag;
      developer.log('hit, manifest 未变更走 304 零正文流量');
    } else {
      remoteRaw = utf8.decode(read.object!.bytes);
      remoteEtag = read.object!.etag;
      remote = SyncManifest.decode(remoteRaw);
    }
    await _pull(store, remote);
    final pushed = await _push(store, remote, remoteRaw);
    if (pushed != null) {
      await db.setSetting(AppDb.syncManifestCacheKey, pushed.raw);
      await db.setSetting(AppDb.syncManifestEtagKey, pushed.etag ?? '');
    } else if (remoteRaw != null) {
      await db.setSetting(AppDb.syncManifestCacheKey, remoteRaw);
      await db.setSetting(AppDb.syncManifestEtagKey, remoteEtag ?? '');
    }
    final shown = pushed != null ? SyncManifest.decode(pushed.raw) : remote;
    remoteNoteCount = shown.notes.length;
    remoteNotebookCount = shown.notebooks.length;
  }

  Map<String, dynamic> _decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  Map<String, dynamic> _stripContent(Map<String, dynamic> json) =>
      Map<String, dynamic>.from(json)..remove('content');

  Map<String, dynamic> _stripVolatile(Map<String, dynamic> json) =>
      Map<String, dynamic>.from(json)
        ..remove('deviceId')
        ..remove('deviceName');

  bool _samePayload(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(_stripVolatile(a)) == jsonEncode(_stripVolatile(b));

  Map<String, dynamic> _localNotebookJson(
          Notebook notebook, String deviceId, String deviceName) =>
      {
        'id': notebook.id,
        'name': notebook.name,
        'color': notebook.color,
        if (notebook.sortKey != null) 'sortKey': notebook.sortKey,
        if (notebook.lock != null) 'lock': notebook.lock,
        'createAt': notebook.createAt,
        'updateAt': notebook.updateAt,
        'deviceId': deviceId,
        'deviceName': deviceName,
      };

  Map<String, dynamic> _localNoteJson(Note note, List<String> assets,
          String deviceId, String deviceName) =>
      {
        'id': note.id,
        'notebookId': note.notebookId,
        'title': note.title,
        if (note.sortKey != null) 'sortKey': note.sortKey,
        if (note.lock != null) 'lock': note.lock,
        if (note.format != 'markdown') 'format': note.format,
        'createAt': note.createAt,
        'updateAt': note.updateAt,
        if (note.deletedAt != null) 'deletedAt': note.deletedAt,
        'deviceId': deviceId,
        'deviceName': deviceName,
        if (assets.isNotEmpty) 'assets': assets,
      };

  Future<void> _pull(RemoteStore store, SyncManifest remote) async {
    final states = await db.syncStateMap();
    final localNotes = {
      for (final note in await db.listAllNotes()) note.id: note,
    };
    final localNotebooks = {
      for (final notebook in await db.listNotebooks()) notebook.id: notebook,
    };
    if (remote.isEmpty &&
        states.isNotEmpty &&
        (localNotes.isNotEmpty || localNotebooks.isNotEmpty)) {
      developer.log(
          'skip, 远端 manifest 为空但本地有数据, 保护本地绝不删除只走推送重建, noteCount: ${localNotes.length}, notebookCount: ${localNotebooks.length}');
      return;
    }
    final localTombstones = {
      for (final tomb in await db.listTombstones()) tomb.id: tomb,
    };
    final deviceId = await db.deviceId();
    final deviceName = await _deviceName();

    for (final tomb in remote.tombstones.values) {
      _ensureAlive();
      if (tomb.kind != AppDb.syncKindNote &&
          tomb.kind != AppDb.syncKindNotebook) {
        developer.log('skip, 未知墓碑类型忽略, id: ${tomb.id}, kind: ${tomb.kind}');
        continue;
      }
      final state = states[tomb.id];
      if (tomb.kind == AppDb.syncKindNote) {
        final local = localNotes[tomb.id];
        if (local != null) {
          final base = state == null ? null : _decode(state.baseJson);
          final localChangedSinceBase =
              base == null || local.updateAt > (base['updateAt'] as int);
          if (localChangedSinceBase) {
            developer.log(
                'hit, 远端已删但本地基线后有改动按本地优先复活, noteId: ${tomb.id}, localUpdateAt: ${local.updateAt}, remoteDeletedAt: ${tomb.deletedAt}');
            await db.removeTombstone(tomb.id);
            continue;
          }
          await db.applyRemoteHardDeleteNote(tomb.id);
          await db.addTombstoneAt(tomb.id, tomb.kind, tomb.deletedAt);
          localNotes.remove(tomb.id);
          _stats.changedLocal = true;
          continue;
        }
      } else {
        final local = localNotebooks[tomb.id];
        if (local != null) {
          final notesInside =
              localNotes.values.where((n) => n.notebookId == tomb.id).length;
          final base = state == null ? null : _decode(state.baseJson);
          final localChangedSinceBase =
              base == null || local.updateAt > (base['updateAt'] as int);
          if (localChangedSinceBase || notesInside > 0) {
            developer.log(
                'hit, 远端已删笔记本但本地有改动或非空按本地优先保留, notebookId: ${tomb.id}, notesInside: $notesInside');
            await db.removeTombstone(tomb.id);
            continue;
          }
          await db.applyRemoteHardDeleteNotebook(tomb.id);
          await db.addTombstoneAt(tomb.id, tomb.kind, tomb.deletedAt);
          localNotebooks.remove(tomb.id);
          _stats.changedLocal = true;
          continue;
        }
      }
      final localTomb = localTombstones[tomb.id];
      if (localTomb == null || localTomb.deletedAt < tomb.deletedAt) {
        await db.addTombstoneAt(tomb.id, tomb.kind, tomb.deletedAt);
        localTombstones[tomb.id] =
            Tombstone(id: tomb.id, kind: tomb.kind, deletedAt: tomb.deletedAt);
        _stats.changedLocal = true;
      }
    }

    for (final entry in remote.notebooks.values) {
      _ensureAlive();
      if (remote.tombstones.containsKey(entry.id)) {
        continue;
      }
      final local = localNotebooks[entry.id];
      final localTomb = localTombstones[entry.id];
      final state = states[entry.id];
      final remoteJson = entry.toJson();
      if (localTomb != null && localTomb.deletedAt >= entry.updateAt) {
        continue;
      }
      if (local == null) {
        await db.applyRemoteNotebook(entry.id, entry.name, entry.color,
            entry.sortKey, entry.createAt, entry.updateAt,
            lock: entry.lock);
        await db.setSyncState(entry.id, AppDb.syncKindNotebook, remoteJson);
        if (localTomb != null) {
          await db.removeTombstone(entry.id);
        }
        _stats.changedLocal = true;
        continue;
      }
      final localJson = _localNotebookJson(local, deviceId, deviceName);
      if (_samePayload(localJson, remoteJson)) {
        if (state == null ||
            !_samePayload(_decode(state.baseJson), localJson)) {
          await db.setSyncState(entry.id, AppDb.syncKindNotebook, localJson);
        }
        continue;
      }
      final base = state == null ? null : _decode(state.baseJson);
      final localChanged = base == null || !_samePayload(base, localJson);
      final remoteChanged = base == null || !_samePayload(base, remoteJson);
      if (localChanged && !remoteChanged) {
        continue;
      }
      if (!localChanged ||
          (remoteChanged && entry.updateAt > local.updateAt)) {
        await db.applyRemoteNotebook(entry.id, entry.name, entry.color,
            entry.sortKey, entry.createAt, entry.updateAt,
            lock: entry.lock);
        await db.setSyncState(entry.id, AppDb.syncKindNotebook, remoteJson);
        _stats.changedLocal = true;
        developer.log(
            'done, 笔记本拉取远端, notebookId: ${entry.id}, localChanged: $localChanged, remoteUpdateAt: ${entry.updateAt}');
        continue;
      }
      developer.log(
          'hit, 笔记本双端改动本地更新时间不早于远端保留本地待推送, notebookId: ${entry.id}, localUpdateAt: ${local.updateAt}, remoteUpdateAt: ${entry.updateAt}');
    }

    for (final entry in remote.notes.values) {
      _ensureAlive();
      if (remote.tombstones.containsKey(entry.id)) {
        continue;
      }
      if (!remote.notebooks.containsKey(entry.notebookId) &&
          !localNotebooks.containsKey(entry.notebookId)) {
        developer.log(
            'skip, 远端笔记的笔记本缺失本轮不拉取, noteId: ${entry.id}, notebookId: ${entry.notebookId}');
        continue;
      }
      final local = localNotes[entry.id];
      final localTomb = localTombstones[entry.id];
      final state = states[entry.id];
      final base = state == null ? null : _decode(state.baseJson);
      final remoteMeta = entry.toJson();
      if (localTomb != null && localTomb.deletedAt >= entry.updateAt) {
        continue;
      }
      if (local == null) {
        final content = await _readContent(store, entry.id);
        await _downloadAssets(store, remote, entry.assets);
        await db.applyRemoteNote(entry.id, entry.notebookId, entry.title,
            content, entry.sortKey, entry.createAt, entry.updateAt,
            entry.deletedAt,
            lock: entry.lock, format: entry.format);
        await db.setSyncState(
            entry.id, AppDb.syncKindNote, {...remoteMeta, 'content': content});
        if (localTomb != null) {
          await db.removeTombstone(entry.id);
        }
        _stats.changedLocal = true;
        _stats.downloadedNotes++;
        continue;
      }
      final localRefs =
          AttachmentStore.referencedIds(local.content).toList()..sort();
      final localMeta = _localNoteJson(local, localRefs, deviceId, deviceName);
      final fullLocal = {...localMeta, 'content': local.content};
      final baseMeta = base == null ? null : _stripContent(base);
      if (base != null &&
          _samePayload(baseMeta!, remoteMeta) &&
          local.content == base['content']) {
        continue;
      }
      final remoteContent = await _readContent(store, entry.id);
      final fullRemote = {...remoteMeta, 'content': remoteContent};
      if (local.content == remoteContent &&
          _samePayload(localMeta, remoteMeta)) {
        await db.setSyncState(entry.id, AppDb.syncKindNote, fullLocal);
        continue;
      }
      final localChanged = base == null || !_samePayload(base, fullLocal);
      final remoteChanged = base == null || !_samePayload(base, fullRemote);
      if (localChanged && !remoteChanged) {
        continue;
      }
      if (!localChanged) {
        await _downloadAssets(store, remote, entry.assets);
        await db.applyRemoteNote(entry.id, entry.notebookId, entry.title,
            remoteContent, entry.sortKey, entry.createAt, entry.updateAt,
            entry.deletedAt,
            lock: entry.lock, format: entry.format);
        await db.setSyncState(entry.id, AppDb.syncKindNote, fullRemote);
        _stats.changedLocal = true;
        _stats.downloadedNotes++;
        developer.log('done, 笔记拉取远端更新, noteId: ${entry.id}');
        continue;
      }
      final merge = diff3Merge(
          base?['content'] as String? ?? '', local.content, remoteContent);
      final resolvedMeta =
          entry.updateAt >= local.updateAt ? remoteMeta : localMeta;
      if (!merge.hasConflict) {
        final merged = merge.autoMerged;
        await _downloadAssets(store, remote, entry.assets);
        final mergedUpdateAt = db.clock();
        await db.applyRemoteNote(
            entry.id,
            resolvedMeta['notebookId'] as String,
            resolvedMeta['title'] as String,
            merged,
            resolvedMeta['sortKey'] as int?,
            local.createAt,
            mergedUpdateAt,
            resolvedMeta['deletedAt'] as int?,
            lock: resolvedMeta['lock'] as String?,
            format: resolvedMeta['format'] as String? ?? 'markdown');
        await db.setSyncState(entry.id, AppDb.syncKindNote, {
          ...resolvedMeta,
          'updateAt': mergedUpdateAt,
          'content': merged,
        });
        _stats.changedLocal = true;
        developer.log(
            'done, 笔记双端改动 diff3 自动合并成功待推送, noteId: ${entry.id}, mergedLength: ${merged.length}');
        continue;
      }
      await db.setConflict(entry.id, {
        'remoteMeta': remoteMeta,
        'remoteContent': remoteContent,
        'localUpdateAt': local.updateAt,
        'segments': [
          for (final segment in merge.segments)
            segment.isConflict
                ? {
                    'conflict': true,
                    'local': segment.local,
                    'remote': segment.remote,
                  }
                : {'conflict': false, 'text': segment.text},
        ],
      });
      await _downloadAssets(store, remote, entry.assets);
      _stats.changedLocal = true;
      developer.log(
          'hit, 笔记双端改动存在冲突块进入裁决面板, noteId: ${entry.id}, conflictCount: ${merge.conflictCount}');
    }

    final mergedApp = _newerLock(
        PasswordLock.parse(await db.getSetting(AppDb.appLockKey)),
        remote.appLock == null
            ? null
            : PasswordLock.fromJson(remote.appLock!));
    final mergedPrivacy = _newerPrivacy(
        PrivacySpaceRef.parse(await db.getSetting(AppDb.privacySpaceKey)),
        remote.privacy == null
            ? null
            : PrivacySpaceRef.fromJson(remote.privacy!));
    await _adoptLockMarkers(mergedApp, mergedPrivacy);
  }

  Future<String> _readContent(RemoteStore store, String noteId) async {
    final read = await store.read(contentFileOf(noteId));
    if (read.missing) {
      developer.log('fail, 远端笔记正文文件缺失按空内容处理, noteId: $noteId');
      return '';
    }
    return utf8.decode(read.object!.bytes);
  }

  Future<void> _downloadAssets(
      RemoteStore store, SyncManifest remote, List<String> ids) async {
    final attachments = _attachments();
    if (attachments == null || ids.isEmpty) {
      return;
    }
    for (final id in ids) {
      if (await attachments.fileOf(id).exists()) {
        continue;
      }
      final read = await store.read(assetFileOf(id));
      if (read.missing) {
        developer.log('fail, 远端附件文件缺失跳过, assetId: $id');
        continue;
      }
      await attachments.save(read.object!.bytes, remote.assetNames[id] ?? id);
      _stats.downloadedAssets++;
      developer.log(
          'done, 附件已下载, assetId: $id, size: ${read.object!.bytes.length}');
    }
  }

  Future<String> _deviceName() async {
    final saved = await db.getSetting(AppDb.syncDeviceNameKey);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    if (!kIsWeb) {
      try {
        final host = Platform.localHostname;
        if (host.isNotEmpty) {
          return host;
        }
      } catch (err) {
        developer.log('skip, 读取主机名失败用默认设备名, err: $err');
      }
    }
    return '未命名设备';
  }

  Future<_PushResult?> _push(
      RemoteStore store, SyncManifest remote, String? remoteRaw) async {
    final deviceId = await db.deviceId();
    final deviceName = await _deviceName();
    final states = await db.syncStateMap();
    final conflicts = await db.conflictNoteIds();
    final attachments = _attachments();
    final mergedApp = _newerLock(
        PasswordLock.parse(await db.getSetting(AppDb.appLockKey)),
        remote.appLock == null
            ? null
            : PasswordLock.fromJson(remote.appLock!));
    final mergedPrivacy = _newerPrivacy(
        PrivacySpaceRef.parse(await db.getSetting(AppDb.privacySpaceKey)),
        remote.privacy == null
            ? null
            : PrivacySpaceRef.fromJson(remote.privacy!));
    await _adoptLockMarkers(mergedApp, mergedPrivacy);
    final merged = SyncManifest(
      updatedAt: remote.updatedAt,
      notebooks: {...remote.notebooks},
      notes: {...remote.notes},
      assets: {...remote.assets},
      assetNames: {...remote.assetNames},
      tombstones: {...remote.tombstones},
      appLock: mergedApp?.toJson(),
      privacy: mergedPrivacy?.toJson(),
    );
    final referencedAssets = <String>{};

    for (final notebook in await db.listNotebooks()) {
      _ensureAlive();
      final state = states[notebook.id];
      final localJson = _localNotebookJson(notebook, deviceId, deviceName);
      final existing = merged.notebooks[notebook.id];
      final baselineMatches =
          state != null && _samePayload(_decode(state.baseJson), localJson);
      if (baselineMatches &&
          existing != null &&
          _samePayload(existing.toJson(), localJson)) {
        continue;
      }
      merged.notebooks[notebook.id] = RemoteNotebook.fromJson(localJson);
      merged.tombstones.remove(notebook.id);
      await db.setSyncState(notebook.id, AppDb.syncKindNotebook, localJson);
    }

    for (final note in await db.listAllNotes()) {
      _ensureAlive();
      final refs = AttachmentStore.referencedIds(note.content).toList()..sort();
      referencedAssets.addAll(refs);
      if (conflicts.contains(note.id)) {
        developer.log('skip, 笔记存在未裁决冲突不推送, noteId: ${note.id}');
        continue;
      }
      final state = states[note.id];
      final localMeta = _localNoteJson(note, refs, deviceId, deviceName);
      final fullLocal = {...localMeta, 'content': note.content};
      final existing = merged.notes[note.id];
      final baselineMatches =
          state != null && _samePayload(_decode(state.baseJson), fullLocal);
      if (baselineMatches &&
          existing != null &&
          _samePayload(existing.toJson(), localMeta)) {
        merged.assets.addAll(refs);
        continue;
      }
      for (final assetId in refs) {
        if (merged.assets.contains(assetId)) {
          continue;
        }
        final bytes = await attachments?.read(assetId);
        if (bytes == null) {
          developer.log(
              'skip, 本地附件缺失无法上传, noteId: ${note.id}, assetId: $assetId');
          continue;
        }
        await store.write(assetFileOf(assetId), bytes);
        merged.assets.add(assetId);
        _stats.uploadedAssets++;
        final name = await attachments?.nameOf(assetId);
        if (name != null && name.isNotEmpty) {
          merged.assetNames[assetId] = name;
        }
        developer.log(
            'done, 附件已上传, assetId: $assetId, size: ${bytes.length}');
      }
      await store.write(contentFileOf(note.id),
          Uint8List.fromList(utf8.encode(note.content)));
      merged.notes[note.id] = RemoteNote.fromJson(localMeta);
      merged.tombstones.remove(note.id);
      merged.assets.addAll(refs);
      await db.setSyncState(note.id, AppDb.syncKindNote, fullLocal);
      _stats.uploadedNotes++;
      developer.log(
          'done, 笔记已推送, noteId: ${note.id}, contentBytes: ${utf8.encode(note.content).length}');
    }

    final tombstoneCutoff =
        db.clock() - AppDb.tombstoneRetentionDays * AppDb.msPerDay;
    for (final tomb in await db.listTombstones()) {
      _ensureAlive();
      if (tomb.deletedAt < tombstoneCutoff) {
        continue;
      }
      final existing = merged.tombstones[tomb.id];
      if (existing == null || existing.deletedAt < tomb.deletedAt) {
        merged.tombstones[tomb.id] = RemoteTombstone(
            id: tomb.id, kind: tomb.kind, deletedAt: tomb.deletedAt);
      }
      merged.notebooks.remove(tomb.id);
      if (merged.notes.remove(tomb.id) != null &&
          !remote.tombstones.containsKey(tomb.id)) {
        await store.remove(contentFileOf(tomb.id));
      }
    }
    for (final id in merged.tombstones.keys.toList()) {
      if (merged.notes.containsKey(id) || merged.notebooks.containsKey(id)) {
        merged.tombstones.remove(id);
        await db.removeTombstone(id);
        developer.log('hit, 实体已复活移除远端墓碑, id: $id');
      }
    }

    final liveAssets = <String>{...referencedAssets};
    for (final entry in merged.notes.values) {
      liveAssets.addAll(entry.assets);
    }
    for (final assetId in merged.assets.toList()) {
      if (!liveAssets.contains(assetId)) {
        await store.remove(assetFileOf(assetId));
        merged.assets.remove(assetId);
        developer.log('done, 远端孤儿附件已清理, assetId: $assetId');
      }
    }
    for (final id in merged.assetNames.keys.toList()) {
      if (!merged.assets.contains(id)) {
        merged.assetNames.remove(id);
      }
    }

    merged.updatedAt = db.clock();
    final raw = merged.encode();
    if (remoteRaw == null && merged.isEmpty) {
      developer.log('skip, 本地与远端均为空不写 manifest');
      return null;
    }
    if (remoteRaw != null) {
      final previous = SyncManifest.decode(remoteRaw);
      previous.updatedAt = merged.updatedAt;
      if (previous.encode() == raw) {
        developer.log('skip, 本地远端均无变化不写 manifest 零上传流量');
        return null;
      }
    }
    final etag = await store.write(
        manifestFile, Uint8List.fromList(utf8.encode(raw)));
    developer.log(
        'done, manifest 已推送, notebooks: ${merged.notebooks.length}, notes: ${merged.notes.length}, assets: ${merged.assets.length}, tombstones: ${merged.tombstones.length}');
    return _PushResult(raw: raw, etag: etag);
  }

  Future<void> resolveConflict(String noteId, List<bool> pickLocal) async {
    final payload = await db.getConflict(noteId);
    if (payload == null) {
      developer.log('skip, 冲突已不存在无需裁决, noteId: $noteId');
      return;
    }
    final segments = <Diff3Segment>[];
    for (final raw in (payload['segments'] as List)) {
      final segment = raw as Map<String, dynamic>;
      if (segment['conflict'] == true) {
        segments.add(Diff3Segment.conflict(segment['local'] as String? ?? '',
            segment['remote'] as String? ?? ''));
      } else {
        segments.add(Diff3Segment.stable(segment['text'] as String? ?? ''));
      }
    }
    final merged = Diff3Result(segments).mergedWith(pickLocal);
    final remoteMeta = payload['remoteMeta'] as Map<String, dynamic>;
    final remoteAssets = [
      for (final item in (remoteMeta['assets'] as List? ?? [])) item as String,
    ];
    final store = _store ?? await buildStore();
    if (store != null && remoteAssets.isNotEmpty) {
      final manifest = SyncManifest.decode(
          await db.getSetting(AppDb.syncManifestCacheKey) ?? '{}');
      await _downloadAssets(store, manifest, remoteAssets);
    }
    await db.saveNote(noteId, (await db.getNote(noteId)).title, merged,
        coalesce: false);
    await db.removeConflict(noteId);
    conflictIds = await db.conflictNoteIds();
    _safeNotify();
    developer.log(
        'done, 冲突已按块裁决合并, noteId: $noteId, blocks: ${pickLocal.length}, mergedLength: ${merged.length}');
    await requestSync('conflictResolved');
  }

  Future<SyncOutcome> rebuildFromRemote() async {
    final store = _store ?? await buildStore();
    if (store == null) {
      developer.log('fail, 未配置同步远端无法重建');
      return const SyncOutcome(ran: false, error: '未配置同步远端');
    }
    developer.log('recv, 手动触发以远端为准重建');
    syncing = true;
    lastError = null;
    _safeNotify();
    try {
      final read = await store.read(manifestFile);
      if (read.missing) {
        developer.log('fail, 远端无 manifest 拒绝重建保护本地');
        return const SyncOutcome(ran: true, error: '远端没有同步数据');
      }
      final raw = utf8.decode(read.object!.bytes);
      final remote = SyncManifest.decode(raw);
      await db.wipeForRebuild();
      final attachments = _attachments();
      if (attachments != null) {
        await attachments.purgeUnreferenced({});
      }
      for (final entry in remote.notebooks.values) {
        await db.applyRemoteNotebook(entry.id, entry.name, entry.color,
            entry.sortKey, entry.createAt, entry.updateAt,
            lock: entry.lock);
        await db.setSyncState(
            entry.id, AppDb.syncKindNotebook, entry.toJson());
      }
      for (final entry in remote.notes.values) {
        final content = await _readContent(store, entry.id);
        await _downloadAssets(store, remote, entry.assets);
        await db.applyRemoteNote(entry.id, entry.notebookId, entry.title,
            content, entry.sortKey, entry.createAt, entry.updateAt,
            entry.deletedAt,
            lock: entry.lock, format: entry.format);
        await db.setSyncState(entry.id, AppDb.syncKindNote,
            {...entry.toJson(), 'content': content});
      }
      for (final tomb in remote.tombstones.values) {
        await db.addTombstoneAt(tomb.id, tomb.kind, tomb.deletedAt);
      }
      await _adoptLockMarkers(
          remote.appLock == null
              ? null
              : PasswordLock.fromJson(remote.appLock!),
          remote.privacy == null
              ? null
              : PrivacySpaceRef.fromJson(remote.privacy!));
      await db.setSetting(AppDb.syncManifestCacheKey, raw);
      await db.setSetting(AppDb.syncManifestEtagKey, read.object!.etag ?? '');
      lastSyncAt = db.clock();
      await db.setSetting(AppDb.syncLastAtKey, '$lastSyncAt');
      developer.log(
          'done, 以远端为准重建完成, notebooks: ${remote.notebooks.length}, notes: ${remote.notes.length}, assets: ${remote.assets.length}');
      return SyncOutcome(
        ran: true,
        changedLocal: true,
        downloadedNotes: remote.notes.length,
      );
    } catch (err) {
      lastError = '$err';
      developer.log('fail, 以远端为准重建失败, err: $err');
      return SyncOutcome(ran: true, error: '$err');
    } finally {
      syncing = false;
      if (!_disposed) {
        conflictIds = await db.conflictNoteIds();
      }
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}

class _SyncAborted implements Exception {
  const _SyncAborted();
}

class _CycleStats {
  bool changedLocal = false;
  int uploadedNotes = 0;
  int downloadedNotes = 0;
  int uploadedAssets = 0;
  int downloadedAssets = 0;
}

class _PushResult {
  _PushResult({required this.raw, required this.etag});

  final String raw;
  final String? etag;
}