import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../state/app_state.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_manifest.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  AppState get state => widget.state;

  String _protocol = AppDb.syncProtocolOff;
  bool _loaded = false;
  bool _saving = false;
  bool _obscureSecret = true;

  final _webdavUrl = TextEditingController();
  final _webdavUser = TextEditingController();
  final _webdavPass = TextEditingController();
  final _webdavPath = TextEditingController();
  final _ossEndpoint = TextEditingController();
  final _ossBucket = TextEditingController();
  final _ossAk = TextEditingController();
  final _ossSk = TextEditingController();
  final _ossPrefix = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _webdavUrl,
      _webdavUser,
      _webdavPass,
      _webdavPath,
      _ossEndpoint,
      _ossBucket,
      _ossAk,
      _ossSk,
      _ossPrefix,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final values = <String, String>{};
    for (final key in [
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
    ]) {
      values[key] = await state.db.getSetting(key) ?? '';
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _protocol = values[AppDb.syncProtocolKey]!.isEmpty
          ? AppDb.syncProtocolOff
          : values[AppDb.syncProtocolKey]!;
      _webdavUrl.text = values[AppDb.syncWebdavUrlKey]!;
      _webdavUser.text = values[AppDb.syncWebdavUserKey]!;
      _webdavPass.text = values[AppDb.syncWebdavPassKey]!;
      _webdavPath.text = values[AppDb.syncWebdavPathKey]!;
      _ossEndpoint.text = values[AppDb.syncOssEndpointKey]!;
      _ossBucket.text = values[AppDb.syncOssBucketKey]!;
      _ossAk.text = values[AppDb.syncOssAkKey]!;
      _ossSk.text = values[AppDb.syncOssSkKey]!;
      _ossPrefix.text = values[AppDb.syncOssPrefixKey]!;
      _loaded = true;
    });
  }

  Future<void> _pickProtocol() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('同步协议'),
        children: [
          for (final option in const [
            (AppDb.syncProtocolOff, '关闭', '不同步，数据只保存在本机'),
            (AppDb.syncProtocolWebdav, 'WebDAV', '坚果云 / Nextcloud / 自建 WebDAV'),
            (AppDb.syncProtocolOss, '阿里云 OSS', '增量传输 · manifest 304 省流量'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.$1),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(option.$2,
                            style: Theme.of(context).textTheme.bodyMedium),
                        Text(option.$3,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: inkOf(context).inkMuted)),
                      ],
                    ),
                  ),
                  if (_protocol == option.$1)
                    Icon(Icons.check,
                        size: 18, color: inkOf(context).accentText),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      setState(() => _protocol = picked);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await state.db.setSetting(AppDb.syncProtocolKey, _protocol);
    await state.db.setSetting(
        AppDb.syncWebdavUrlKey, _webdavUrl.text.trim());
    await state.db.setSetting(
        AppDb.syncWebdavUserKey, _webdavUser.text.trim());
    await state.db.setSetting(AppDb.syncWebdavPassKey, _webdavPass.text);
    await state.db.setSetting(
        AppDb.syncWebdavPathKey, _webdavPath.text.trim());
    await state.db.setSetting(
        AppDb.syncOssEndpointKey, _ossEndpoint.text.trim());
    await state.db.setSetting(
        AppDb.syncOssBucketKey, _ossBucket.text.trim());
    await state.db.setSetting(AppDb.syncOssAkKey, _ossAk.text.trim());
    await state.db.setSetting(AppDb.syncOssSkKey, _ossSk.text);
    await state.db.setSetting(
        AppDb.syncOssPrefixKey, _ossPrefix.text.trim());
    await state.sync.reloadConfig();
    developer.log('done, 同步配置已保存, protocol: $_protocol');
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('同步配置已保存')));
  }

  Future<void> _editPoll() async {
    final input = await promptText(context,
        title: '定时轮询间隔',
        label: '分钟（0 = 关闭，1-${AppDb.syncPollMinutesMax}）',
        initial: '${state.sync.pollMinutes}',
        hint: '0 关闭轮询，仍保留启动 / 手动 / 写前同步');
    if (input == null) {
      return;
    }
    final minutes = int.tryParse(input);
    if (minutes == null ||
        minutes < 0 ||
        minutes > AppDb.syncPollMinutesMax) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('请输入 0-${AppDb.syncPollMinutesMax} 的整数分钟')));
      }
      return;
    }
    await state.db.setSetting(AppDb.syncPollMinutesKey, '$minutes');
    await state.sync.reloadConfig();
    developer.log('done, 轮询间隔已更新, pollMinutes: $minutes');
  }

  Future<void> _editDeviceName() async {
    final current =
        await state.db.getSetting(AppDb.syncDeviceNameKey) ?? '';
    if (!mounted) {
      return;
    }
    final input = await promptText(context,
        title: '设备名称',
        label: '冲突面板中显示的名称',
        initial: current,
        hint: '留空使用本机主机名');
    if (input == null) {
      return;
    }
    await state.db.setSetting(AppDb.syncDeviceNameKey, input);
    developer.log('done, 设备名称已更新, deviceName: $input');
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncNow() async {
    final outcome = await state.syncNow('manual');
    if (!mounted) {
      return;
    }
    final message = !outcome.ran
        ? '未配置同步远端，先填写并保存配置'
        : outcome.error != null
            ? '同步失败：${outcome.error}'
            : '同步完成 · 上传 ${outcome.uploadedNotes} 篇 · 下载 ${outcome.downloadedNotes} 篇'
                ' · 附件上传 ${outcome.uploadedAssets} / 下载 ${outcome.downloadedAssets}';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rebuild() async {
    final store = await state.sync.buildStore();
    if (store == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未配置同步远端，先填写并保存配置')));
      }
      return;
    }
    bool remoteEmpty = false;
    try {
      final read = await store.read(SyncEngine.manifestFile);
      if (read.missing) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('远端没有同步数据，无法重建')));
        }
        return;
      }
      final raw = read.notModified
          ? await state.db.getSetting(AppDb.syncManifestCacheKey) ?? '{}'
          : utf8.decode(read.object!.bytes);
      remoteEmpty = SyncManifest.decode(raw).isEmpty;
    } catch (err) {
      developer.log('fail, 重建前读取远端失败, err: $err');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('读取远端失败：$err')));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final ok = await confirm(context,
        title: '以远端为准重建',
        message: remoteEmpty
            ? '远端当前是空的！继续将清空本机全部笔记、笔记本、版本历史与回收站，且无法恢复。确定继续吗？'
            : '将丢弃本机全部笔记、笔记本、版本历史、回收站与未上传的修改，完全按远端数据重建。此操作不可撤销，确定继续吗？',
        confirmLabel: remoteEmpty ? '清空并重建' : '丢弃本地并重建',
        danger: true);
    if (!ok) {
      return;
    }
    final outcome = await state.rebuildFromRemote();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(outcome.error != null
            ? '重建失败：${outcome.error}'
            : '已按远端重建，共 ${outcome.downloadedNotes} 篇笔记')));
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: t.paper,
          title: const Text('同步'),
          leading: Transform.translate(
            offset: const Offset(spaceSm, spaceSm),
            child: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios),
            ),
          ),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(spaceLg),
                    children: [
                      _statusCard(t),
                      const SizedBox(height: spaceLg),
                      _card([
                        _row(
                          icon: Icons.cloud_outlined,
                          title: '同步协议',
                          subtitle: '同一时间只用一个远端',
                          action: switch (_protocol) {
                            AppDb.syncProtocolWebdav => 'WebDAV',
                            AppDb.syncProtocolOss => '阿里云 OSS',
                            _ => '关闭',
                          },
                          onTap: _pickProtocol,
                        ),
                        if (_protocol == AppDb.syncProtocolWebdav) ...[
                          Divider(height: 1, color: t.hairline),
                          _field('服务器地址', _webdavUrl,
                              hint: 'https://dav.jianguoyun.com/dav'),
                          _field('账号', _webdavUser),
                          _field('密码 / 应用密码', _webdavPass,
                              secret: true),
                          _field('远端目录', _webdavPath,
                              hint: '默认 /onenote'),
                        ],
                        if (_protocol == AppDb.syncProtocolOss) ...[
                          Divider(height: 1, color: t.hairline),
                          _field('Endpoint', _ossEndpoint,
                              hint: 'oss-cn-hangzhou.aliyuncs.com'),
                          _field('Bucket', _ossBucket),
                          _field('AccessKey ID', _ossAk),
                          _field('AccessKey Secret', _ossSk, secret: true),
                          _field('对象前缀', _ossPrefix, hint: '默认 onenote'),
                        ],
                        if (_protocol != AppDb.syncProtocolOff) ...[
                          const SizedBox(height: spaceSm),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                spaceMd, 0, spaceMd, spaceMd),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: _saving ? null : _save,
                                child: Text(_saving ? '保存中…' : '保存配置'),
                              ),
                            ),
                          ),
                        ],
                      ]),
                      const SizedBox(height: spaceLg),
                      _card([
                        _row(
                          icon: Icons.timer_outlined,
                          title: '定时轮询',
                          subtitle:
                              '0 关闭；启动、手动、进入编辑与每次写操作前后的同步不受影响',
                          action: state.sync.pollMinutes == 0
                              ? '关闭'
                              : '${state.sync.pollMinutes} 分钟',
                          onTap: _editPoll,
                        ),
                        Divider(height: 1, color: t.hairline),
                        _deviceRow(t),
                      ]),
                      const SizedBox(height: spaceLg),
                      _card([
                        _row(
                          icon: Icons.sync,
                          title: '立即同步',
                          subtitle: state.sync.syncing
                              ? '同步进行中…'
                              : '手动执行一次增量同步',
                          action: '',
                          onTap:
                              state.sync.syncing ? () {} : _syncNow,
                        ),
                        Divider(height: 1, color: t.hairline),
                        _row(
                          icon: Icons.cloud_download_outlined,
                          title: '以远端为准重建',
                          subtitle:
                              '唯一会清空本地数据的操作：丢弃本机全部数据，按远端重建',
                          action: '',
                          onTap: state.sync.syncing ? () {} : _rebuild,
                          danger: true,
                        ),
                      ]),
                      const SizedBox(height: spaceLg),
                      Text(
                        '安全约定：远端故障或数据为空时，同步绝不会删除本地数据。'
                        '删除通过墓碑传播，保留 ${AppDb.tombstoneRetentionDays} 天；'
                        '远端删除后本地又有修改的笔记会自动复活。',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: t.inkMuted),
                      ),
                      const SizedBox(height: spaceXxl),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _statusCard(InkTokens t) {
    final engine = state.sync;
    final lastAt = engine.lastSyncAt;
    final error = engine.lastError;
    return Container(
      padding: const EdgeInsets.all(spaceMd),
      decoration: BoxDecoration(
        color: error != null
            ? t.danger.withValues(alpha: 0.08)
            : t.surface,
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(color: error != null ? t.danger : t.hairline),
      ),
      child: Row(
        children: [
          Icon(
            error != null
                ? Icons.sync_problem
                : engine.syncing
                    ? Icons.sync
                    : Icons.cloud_done_outlined,
            size: 20,
            color: error != null ? t.danger : t.accentText,
          ),
          const SizedBox(width: spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  engine.syncing
                      ? '正在同步…'
                      : error != null
                          ? '上次同步失败：$error'
                          : lastAt == null
                              ? '还没有同步过'
                              : '上次同步 ${formatDateTime(lastAt)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (engine.conflictIds.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${engine.conflictIds.length} 篇笔记存在冲突待裁决',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: t.danger),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceRow(InkTokens t) {
    return FutureBuilder<String?>(
      future: state.db.getSetting(AppDb.syncDeviceNameKey),
      builder: (context, snapshot) {
        final name = snapshot.data ?? '';
        return _row(
          icon: Icons.devices_outlined,
          title: '设备名称',
          subtitle: '冲突裁决面板里用来区分修改来自哪台设备',
          action: name.isEmpty ? '自动（主机名）' : name,
          onTap: _editDeviceName,
        );
      },
    );
  }

  Widget _card(List<Widget> children) {
    final t = inkOf(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(color: t.hairline),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radiusLg),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      {String hint = '', bool secret = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(spaceMd, spaceSm, spaceMd, 0),
      child: TextField(
        controller: controller,
        obscureText: secret && _obscureSecret,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: secret
              ? IconButton(
                  onPressed: () =>
                      setState(() => _obscureSecret = !_obscureSecret),
                  icon: Icon(
                    _obscureSecret
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required String action,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final t = inkOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusLg),
      child: Padding(
        padding: const EdgeInsets.all(spaceMd),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? t.danger : t.inkMuted),
            const SizedBox(width: spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: danger ? t.danger : null)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.inkMuted)),
                ],
              ),
            ),
            if (action.isNotEmpty) ...[
              const SizedBox(width: spaceSm),
              Text(action,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: t.accentText, fontWeight: FontWeight.w600)),
            ],
            Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}