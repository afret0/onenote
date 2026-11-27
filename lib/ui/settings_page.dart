import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../data/app_db.dart';
import '../data/bg_shape_kinds.dart';
import '../data/bg_theme.dart';
import '../data/font_store.dart';
import '../lock/biometrics.dart';
import '../state/app_state.dart';
import '../update/update_flow.dart';
import '../window_setup.dart' show isDesktopWindow;
import 'dialogs.dart';
import 'font_catalog_dialog.dart';
import 'password_prompts.dart';
import 'shell_background.dart';
import 'sync_settings_page.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _trashDays = AppDb.defaultRetentionDays;
  int _versionDays = AppDb.defaultRetentionDays;
  String _syncProtocol = AppDb.syncProtocolOff;
  bool _bioAvailable = false;
  String _appVersion = '';
  int _versionTaps = 0;
  bool _privacyEntryUnlocked = false;

  static const int _privacyUnlockTaps = 10;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _loadRetention();
    _loadBio();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await loadAppVersion();
    if (mounted && version.isNotEmpty) {
      setState(() => _appVersion = version);
    }
  }

  Future<void> _loadBio() async {
    if (!Biometrics.supported) {
      return;
    }
    final available = await Biometrics.available();
    if (mounted) {
      setState(() => _bioAvailable = available);
    }
  }

  Future<void> _loadRetention() async {
    final trash = await state.db.retentionDays(AppDb.trashRetentionKey);
    final version = await state.db.retentionDays(AppDb.versionRetentionKey);
    final protocol = await state.db.getSetting(AppDb.syncProtocolKey);
    if (mounted) {
      setState(() {
        _trashDays = trash;
        _versionDays = version;
        _syncProtocol =
            protocol == null || protocol.isEmpty ? AppDb.syncProtocolOff : protocol;
      });
    }
  }

  Future<void> _openSyncSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SyncSettingsPage(state: state)),
    );
    if (!mounted || state.isDisposed) {
      developer.log('skip, 同步子页返回时已上锁不再读库');
      return;
    }
    await _loadRetention();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _onVersionTap() {
    if (_privacyEntryUnlocked) {
      return;
    }
    _versionTaps += 1;
    final remaining = _privacyUnlockTaps - _versionTaps;
    if (remaining > 3) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (remaining <= 0) {
      developer.log('done, 隐私空间入口已解锁显示, taps: $_privacyUnlockTaps');
      setState(() {
        _privacyEntryUnlocked = true;
        _versionTaps = 0;
      });
      messenger.showSnackBar(
          const SnackBar(content: Text('隐私空间入口已显示')));
      return;
    }
    messenger.showSnackBar(
        SnackBar(content: Text('再点击 $remaining 次显示隐私空间入口')));
  }

  Future<void> _setAppPassword() async {
    final existing = state.appLock;
    final hasPassword = existing != null && existing.active;
    if (hasPassword) {
      final current = await promptPassword(
        context,
        title: '验证当前密码',
        subtitle: '修改应用密码前先验证',
        attempts: state.attempts,
        lock: existing,
        confirmLabel: '验证',
      );
      if (current == null || !mounted) {
        return;
      }
    }
    final password = await promptNewPassword(
      context,
      title: hasPassword ? '修改应用密码' : '设置应用密码',
      subtitle: '启动与切后台后需输入密码，密码随同步在其它设备生效',
    );
    if (password != null) {
      await state.setAppPassword(password);
    }
  }

  Future<void> _removeAppPassword() async {
    final existing = state.appLock;
    if (existing == null || !existing.active) {
      return;
    }
    if (state.privacyRef != null && state.privacyRef!.active) {
      _snack('请先销毁隐私空间，再移除应用密码');
      return;
    }
    final current = await promptPassword(
      context,
      title: '移除应用密码',
      subtitle: '先验证当前密码',
      attempts: state.attempts,
      lock: existing,
      confirmLabel: '验证',
    );
    if (current == null || !mounted) {
      return;
    }
    final ok = await confirm(context,
        title: '移除应用密码',
        message: '移除后所有设备打开应用都不再需要密码。',
        confirmLabel: '移除');
    if (ok) {
      await state.removeAppPassword();
    }
  }

  Future<void> _pickLease() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('自动上锁时长'),
        children: [
          for (final minutes in AppState.lockLeasePresets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, minutes),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      minutes <= 0 ? '不定时（本次运行内免密）' : '$minutes 分钟',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (state.lockLeaseMinutes == minutes)
                    Icon(Icons.check,
                        size: 18, color: inkOf(context).accentText),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await state.setLockLeaseMinutes(picked);
    }
  }

  Future<void> _createPrivacySpace() async {
    if (state.appLock == null || !state.appLock!.active) {
      _snack('请先设置应用密码，再创建隐私空间');
      return;
    }
    final password = await promptNewPassword(
      context,
      title: '创建隐私空间',
      subtitle: '锁屏输入此密码将打开一份完全独立的数据，与日常空间外观一致',
    );
    if (password == null || !mounted) {
      return;
    }
    try {
      await state.createPrivacySpace(password);
      if (mounted) {
        _snack('隐私空间已创建，锁屏输入新密码即可进入');
      }
    } on StateError {
      if (mounted) {
        _snack('已存在隐私空间');
      }
    }
  }

  Future<void> _destroyPrivacySpace() async {
    final first = await confirm(
      context,
      title: '销毁隐私空间',
      message: '隐私空间内的全部笔记将被永久删除（本地与云端），无法恢复。确定继续？',
      confirmLabel: '继续',
      danger: true,
    );
    if (!first || !mounted) {
      return;
    }
    final second = await confirm(
      context,
      title: '再次确认',
      message: '销毁后该密码将不再打开任何数据，空间无法找回。确定销毁？',
      confirmLabel: '销毁',
      danger: true,
    );
    if (second) {
      await state.deletePrivacySpace();
    }
  }

  Future<void> _editDays(String key, int current, String label) async {
    final input = await promptText(context,
        title: label, label: '保留天数', initial: '$current', hint: '默认 90');
    if (input == null) {
      return;
    }
    final days = int.tryParse(input);
    if (days == null || days <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请输入正整数天数')));
      }
      return;
    }
    await state.db.setSetting(key, '$days');
    await _loadRetention();
  }

  Future<void> _pickFont() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('界面字体'),
        children: [
          for (final option in const [
            (AppState.uiFontMiSans, 'MiSans', '小米开源字体，中文原生支持'),
            (AppState.uiFontInter, 'Inter', '拉丁字体，中文走系统字体'),
            (AppState.uiFontCascadia, 'Cascadia Code PL', '微软开源等宽，中文走系统字体'),
          ])
            _fontOption(context, option.$1, option.$2, option.$3),
          if (state.fonts != null)
            for (final font in state.fonts!.fonts)
              _fontOption(
                  context,
                  '${AppState.localFontPrefix}${font.id}',
                  font.name,
                  font.kind == LocalFontStore.downloadKind ? '在线下载' : '本地导入',
                  deleteSentinel: '__delete__${font.id}'),
          const Divider(height: 1),
          SimpleDialogOption(
            onPressed:
                kIsWeb ? null : () => Navigator.pop(context, '__import__'),
            child: _fontActionRow(context, Icons.upload_file_outlined, '导入本地字体…',
                kIsWeb ? 'web 端暂不支持' : '选择 ttf / otf 文件，同名自动合并字重'),
          ),
          SimpleDialogOption(
            onPressed:
                kIsWeb ? null : () => Navigator.pop(context, '__catalog__'),
            child: _fontActionRow(context, Icons.cloud_download_outlined, '在线获取字体…',
                kIsWeb ? 'web 端暂不支持' : '开源字体按需下载，不进安装包'),
          ),
        ],
      ),
    );
    if (!mounted || picked == null) {
      return;
    }
    if (picked == '__import__') {
      await _importLocalFonts();
      return;
    }
    if (picked == '__catalog__') {
      await showDialog<void>(
          context: context, builder: (_) => FontCatalogDialog(state: state));
      return;
    }
    if (picked.startsWith('__delete__')) {
      await _deleteLocalFont(picked.substring('__delete__'.length));
      return;
    }
    await state.setUiFont(picked);
  }

  Widget _fontOption(BuildContext context, String value, String name, String desc,
      {String? deleteSentinel}) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.bodyMedium),
                Text(desc,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: inkOf(context).inkMuted)),
              ],
            ),
          ),
          if (state.uiFont == value)
            Icon(Icons.check, size: 18, color: inkOf(context).accentText),
          if (deleteSentinel != null)
            Semantics(
              button: true,
              label: '删除字体',
              child: IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: inkOf(context).inkMuted),
                style: const ButtonStyle(
                    mouseCursor:
                        WidgetStatePropertyAll(SystemMouseCursors.click)),
                onPressed: () => Navigator.pop(context, deleteSentinel),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fontActionRow(
      BuildContext context, IconData icon, String title, String desc) {
    final t = inkOf(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: t.accentText),
        const SizedBox(width: spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              Text(desc,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _importLocalFonts() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        allowMultiple: true);
    final paths = result?.files
            .map((f) => f.path)
            .whereType<String>()
            .toList() ??
        [];
    if (paths.isEmpty) {
      return;
    }
    try {
      final imported = await state.importLocalFonts(paths);
      if (!mounted || imported.isEmpty) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '已导入 ${imported.map((f) => f.name).join('、')}，可在界面字体中选择')));
    } catch (err) {
      developer.log('fail, 导入本地字体失败, count: ${paths.length}, err: $err');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败：$err')));
    }
  }

  Future<void> _deleteLocalFont(String id) async {
    final font = state.fonts?.byId(id);
    if (font == null) {
      return;
    }
    final ok = await confirm(context,
        title: '删除字体',
        message: '删除「${font.name}」的本地文件？正在使用时会回退 MiSans。',
        confirmLabel: '删除',
        danger: true);
    if (!ok || !mounted) {
      return;
    }
    await state.deleteLocalFont(id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已删除 ${font.name}')));
  }

  String _fontLabel() {
    if (state.uiFont == AppState.uiFontInter) {
      return 'Inter';
    }
    if (state.uiFont == AppState.uiFontCascadia) {
      return 'Cascadia Code PL';
    }
    if (state.uiFont.startsWith(AppState.localFontPrefix)) {
      final font = state.fonts
          ?.byId(state.uiFont.substring(AppState.localFontPrefix.length));
      return font?.name ?? 'MiSans';
    }
    return 'MiSans';
  }

  Future<void> _pickNarrowStartup() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('窄屏启动页面'),
        children: [
          for (final option in const [
            (AppState.narrowStartupNote, '上次打开的笔记', '启动直接进入上次浏览的页面'),
            (AppState.narrowStartupList, '笔记列表', '启动先看列表，手动点开笔记'),
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
                  if (state.narrowStartup == option.$1)
                    Icon(Icons.check, size: 18, color: inkOf(context).accentText),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await state.setNarrowStartup(picked);
    }
  }

  String _bgScopeLabel() {
    switch (state.bgScope) {
      case AppState.bgScopeFull:
        return '全部区域';
      case AppState.bgScopeEmpty:
        return '仅空态';
      default:
        return '侧栏与列表';
    }
  }

  String _bgShapesLabel() {
    if (state.bgShapes.isEmpty) {
      return '不使用';
    }
    if (state.bgShapes.length == shellBgShapeKinds.length) {
      return '全部';
    }
    return '${state.bgShapes.length} 种';
  }

  Future<void> _pickBgShapes() async {
    final initial = state.bgShapes.toSet();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = inkOf(dialogContext);
        var selected = initial;
        return StatefulBuilder(
          builder: (context, setDialogState) => SimpleDialog(
            title: const Text('图案形状'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(spaceLg, 0, spaceLg, spaceSm),
                child: Text(
                  '勾选背景里出现的形状；全不选为素纸底。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: t.inkMuted),
                ),
              ),
              for (final kind in shellBgShapeKinds)
                CheckboxListTile(
                  value: selected.contains(kind.id),
                  title: Text(kind.name,
                      style: Theme.of(context).textTheme.bodyMedium),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: t.accent,
                  onChanged: (checked) async {
                    final next = state.bgShapes.toSet();
                    if (checked == true) {
                      next.add(kind.id);
                    } else {
                      next.remove(kind.id);
                    }
                    await state.setBgShapes(next);
                    if (context.mounted) {
                      setDialogState(() => selected = state.bgShapes.toSet());
                    }
                  },
                ),
              const SizedBox(height: spaceSm),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickBgTheme() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('背景主题'),
        children: [
          _bgThemeOption(shellBgNone, '不使用', null),
          for (final theme in shellBgThemes)
            _bgThemeOption(theme.id, theme.name, theme),
        ],
      ),
    );
    if (picked != null) {
      await state.setBgTheme(picked);
    }
  }

  Widget _bgThemeOption(String id, String name, ShellBgTheme? theme) {
    final t = inkOf(context);
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, id),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 40,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(radiusSm),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radiusSm),
              border: Border.all(color: t.hairline),
            ),
            child: theme == null ? null : ShellBackground(themeId: theme.id),
          ),
          const SizedBox(width: spaceMd),
          Expanded(
            child: Text(name, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (state.bgTheme == id)
            Icon(Icons.check, size: 18, color: t.accentText),
        ],
      ),
    );
  }

  Future<void> _pickBgScope() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('背景范围'),
        children: [
          for (final option in const [
            (AppState.bgScopePane, '侧栏与列表', '侧栏与列表间隙透出，正文与卡片保持实色'),
            (AppState.bgScopeFull, '全部区域', '含正文在内全部透出，图案极淡不影响阅读'),
            (AppState.bgScopeEmpty, '仅空态', '仅空态占位区透出，其余全部实色'),
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
                  if (state.bgScope == option.$1)
                    Icon(Icons.check, size: 18, color: inkOf(context).accentText),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await state.setBgScope(picked);
    }
  }

  Future<void> _pickDefaultNoteFormat() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('新建笔记格式'),
        children: [
          for (final option in const [
            (AppDb.noteFormatMarkdown, 'Markdown', '源码编辑，渲染态预览，适合纯文本'),
            (AppDb.noteFormatRichtext, '富文本', '所见即所得编辑，支持表格与工具栏'),
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
                  if (state.defaultNoteFormat == option.$1)
                    Icon(Icons.check, size: 18, color: inkOf(context).accentText),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await state.setDefaultNoteFormat(picked);
    }
  }

  Future<void> _editClipPort() async {
    final input = await promptText(context,
        title: '桥接端口',
        label: '端口（1024–65535）',
        initial: '${state.clipPort}',
        hint: '默认 41190');
    if (input == null) {
      return;
    }
    final port = int.tryParse(input);
    final ok = port != null && await state.setClipPort(port);
    if (!mounted) {
      return;
    }
    final message = !ok
        ? '请输入 1024–65535 的整数端口'
        : state.clipError;
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _copyClipToken() async {
    await Clipboard.setData(ClipboardData(text: state.clipToken));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配对令牌已复制，粘贴到插件设置里')));
    }
  }

  Future<void> _regenerateClipToken() async {
    final ok = await confirm(context,
        title: '重新生成配对令牌',
        message: '旧令牌立即失效，需要在插件设置里重新粘贴新令牌。',
        confirmLabel: '重新生成');
    if (ok) {
      await state.regenerateClipToken();
    }
  }

  Future<void> _showClipInstall() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('安装 Chrome 剪藏插件'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: spaceLg),
            child: SelectableText(
              '1. 打开 chrome://extensions，开启右上角「开发者模式」\n'
              '2. 点「加载已解压的扩展程序」，选择仓库里的 extension/chrome 目录\n'
              '3. 打开插件弹窗的设置，确认端口为 ${state.clipPort}，粘贴配对令牌\n'
              '4. 保持本应用运行且剪藏服务已启用，即可剪藏网页',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.7),
            ),
          ),
          const SizedBox(height: spaceMd),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: spaceLg),
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ),
          ),
          const SizedBox(height: spaceSm),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: t.paper,
          title: const Text('设置'),
          leading: Transform.translate(
            offset: const Offset(spaceSm, spaceSm),
            child: Semantics(
              button: true,
              label: '返回',
              child: IconButton(
                onPressed: () => Navigator.maybePop(context),
                style: const ButtonStyle(
                  mouseCursor:
                      WidgetStatePropertyAll(SystemMouseCursors.click),
                ),
                icon: const Icon(Icons.arrow_back_ios),
              ),
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1400
                ? 3
                : constraints.maxWidth >= 900
                    ? 2
                    : 1;
            final sections = _sections(context, t);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: columns * 640.0 + (columns - 1) * spaceLg),
                child: ListView(
                  padding: const EdgeInsets.all(spaceLg),
                  children: [
                    if (columns == 1)
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) const SizedBox(height: spaceLg),
                        sections[i],
                      ]
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var c = 0; c < columns; c++) ...[
                            if (c > 0) const SizedBox(width: spaceLg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _columnChildren(sections, c, columns),
                              ),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: spaceXxl),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _columnChildren(
      List<Widget> sections, int index, int columns) {
    final base = sections.length ~/ columns;
    final extra = sections.length % columns;
    final start = index * base + (index < extra ? index : extra);
    final end = start + base + (index < extra ? 1 : 0);
    return [
      for (var i = start; i < end; i++) ...[
        if (i > start) const SizedBox(height: spaceLg),
        sections[i],
      ],
    ];
  }

  Widget _group(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: children);

  List<Widget> _sections(BuildContext context, InkTokens t) => [
        _group([
          _SectionTitle('外观'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.font_download_outlined,
              title: '界面字体',
              subtitle: '本应用包含小米 MiSans 字体，依其许可免费商用；Inter/Cascadia 依 OFL',
              action: _fontLabel(),
              onTap: _pickFont,
            ),
            Divider(height: 1, color: t.hairline),
            _SliderRow(
              icon: Icons.format_size,
              title: '全局字号',
              subtitle: '标题栏 / 笔记本栏 / 列表 / 正文等比缩放',
              value: state.fontScale,
              min: AppState.fontScaleMin,
              max: AppState.fontScaleMax,
              divisions: 11,
              valueLabel: '${(state.fontScale * 100).round()}%',
              onChanged: state.updateFontScale,
              onChangeEnd: (_) => state.persistFontSizes(),
            ),
            Divider(height: 1, color: t.hairline),
            _SliderRow(
              icon: Icons.subject,
              title: '笔记正文字号',
              subtitle: '渲染与编辑生效，正文内标题按原比例联动',
              value: state.noteFontSize,
              min: AppState.noteFontSizeMin,
              max: AppState.noteFontSizeMax,
              divisions: 10,
              valueLabel: '${state.noteFontSize.round()}px',
              onChanged: state.updateNoteFontSize,
              onChangeEnd: (_) => state.persistFontSizes(),
            ),
            Divider(height: 1, color: t.hairline),
            _SettingRow(
              icon: Icons.wallpaper_outlined,
              title: '背景主题',
              subtitle: '柔光几何填充图案，明暗主题自动适配',
              action: shellBgThemeOf(state.bgTheme)?.name ?? '不使用',
              onTap: _pickBgTheme,
            ),
            Divider(height: 1, color: t.hairline),
            _SettingRow(
              icon: Icons.layers_outlined,
              title: '背景范围',
              subtitle: '图案在哪些区域透出，正文实色最护眼',
              action: _bgScopeLabel(),
              onTap: _pickBgScope,
            ),
            Divider(height: 1, color: t.hairline),
            _SettingRow(
              icon: Icons.category_outlined,
              title: '图案形状',
              subtitle: '勾选背景里出现哪些形状，全不选为素纸底',
              action: _bgShapesLabel(),
              onTap: _pickBgShapes,
            ),
          ]),
        ]),
        _group([
          _SectionTitle('启动'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.restore_page_outlined,
              title: '窄屏启动页面',
              subtitle: '手机 / 小窗启动时显示哪个页面，宽屏始终恢复上次页面',
              action: state.narrowStartup == AppState.narrowStartupList
                  ? '笔记列表'
                  : '上次笔记',
              onTap: _pickNarrowStartup,
            ),
          ]),
        ]),
        _group([
          _SectionTitle('笔记'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.edit_note_outlined,
              title: '新建笔记格式',
              subtitle: '仅影响新建笔记，已有笔记可在列表右键单独转换',
              action: state.defaultNoteFormat == AppDb.noteFormatRichtext
                  ? '富文本'
                  : 'Markdown',
              onTap: _pickDefaultNoteFormat,
            ),
          ]),
        ]),
        _group([
          _SectionTitle('数据保留'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.delete_outline,
              title: '回收站保留',
              subtitle: '删除的笔记保留 $_trashDays 天后自动清除',
              action: '$_trashDays 天',
              onTap: () => _editDays(
                  AppDb.trashRetentionKey, _trashDays, '回收站保留天数'),
            ),
            Divider(height: 1, color: t.hairline),
            _SettingRow(
              icon: Icons.history,
              title: '版本历史保留',
              subtitle: '每次保存自动记录版本（内容不变不记录），保留 $_versionDays 天',
              action: '$_versionDays 天',
              onTap: () => _editDays(
                  AppDb.versionRetentionKey, _versionDays, '版本历史保留天数'),
            ),
          ]),
        ]),
        _group([
          _SectionTitle('同步'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.sync,
              title: 'WebDAV / OSS 同步',
              subtitle: '增量同步 · 启动 + 手动 + 编辑与写入前后 + 定时轮询',
              action: switch (_syncProtocol) {
                AppDb.syncProtocolWebdav => 'WebDAV',
                AppDb.syncProtocolOss => 'OSS',
                _ => '未开启',
              },
              onTap: _openSyncSettings,
            ),
          ]),
        ]),
        _group([
          _SectionTitle('密码与隐私'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.lock_outline,
              title: '应用密码',
              subtitle: state.isChildSpace
                  ? '当前处于隐私空间，密码改动同步到所有设备'
                  : '启动与切后台后需输入密码，密码随同步生效',
              action: state.appLock?.active == true ? '修改' : '设置',
              onTap: _setAppPassword,
            ),
            if (state.appLock?.active == true) ...[
              Divider(height: 1, color: t.hairline),
              _SettingRow(
                icon: Icons.lock_open_outlined,
                title: state.isChildSpace ? '销毁此隐私空间' : '移除应用密码',
                subtitle: state.isChildSpace
                    ? '移除密码即销毁本空间全部数据，不可恢复'
                    : '移除后所有设备打开应用不再需要密码',
                action: '',
                onTap: state.isChildSpace
                    ? () => state.removeAppPassword()
                    : _removeAppPassword,
              ),
              Divider(height: 1, color: t.hairline),
              _SettingRow(
                icon: Icons.timer_outlined,
                title: '自动上锁',
                subtitle: '解锁后无操作超过该时长自动重新上锁，任何操作都会续期',
                action: state.lockLeaseMinutes <= 0
                    ? '不定时'
                    : '${state.lockLeaseMinutes} 分钟',
                onTap: _pickLease,
              ),
              Divider(height: 1, color: t.hairline),
              _SwitchRow(
                icon: Icons.visibility_off_outlined,
                title: '切后台即锁',
                subtitle: '应用退到后台时立即锁定',
                value: state.appBackgroundLock,
                onChanged: state.setAppBackgroundLock,
              ),
              if (isDesktopWindow) ...[
                Divider(height: 1, color: t.hairline),
                _SwitchRow(
                  icon: Icons.center_focus_weak_outlined,
                  title: '失焦即锁',
                  subtitle: '窗口失去焦点时立即锁定',
                  value: state.appBlurLock,
                  onChanged: state.setAppBlurLock,
                ),
              ],
              if (_bioAvailable) ...[
                Divider(height: 1, color: t.hairline),
                _SwitchRow(
                  icon: Icons.fingerprint,
                  title: '生物识别解锁',
                  subtitle: '锁屏与笔记本/笔记解锁可用指纹 / 面容 / 系统密码快速解锁',
                  value: state.lockBio,
                  onChanged: state.setLockBio,
                ),
              ],
              if (Biometrics.systemAppLockSupported) ...[
                Divider(height: 1, color: t.hairline),
                _SwitchRow(
                  icon: Icons.face_outlined,
                  title: '信任系统应用锁',
                  subtitle:
                      '先在系统设置把本应用加入应用锁（可人脸）；开启后启动/回前台/设置/笔记本/单篇解锁都交给系统锁，本应用不再重复验证；隐私空间仍用密码区分数据',
                  value: state.trustSystemLock,
                  onChanged: state.setTrustSystemLock,
                ),
              ],
              Divider(height: 1, color: t.hairline),
              _SettingRow(
                icon: Icons.lock_clock,
                title: '立即锁定',
                subtitle: '马上回到锁屏，清空全部免密租期',
                action: '',
                onTap: () => state.lockApp(),
              ),
            ],
            if (_privacyEntryUnlocked) ...[
              if (state.privacyRef?.active == true) ...[
                Divider(height: 1, color: t.hairline),
                _SettingRow(
                  icon: Icons.login_outlined,
                  title: '进入隐私空间',
                  subtitle: '回到锁屏输入隐私空间密码，打开那份独立数据',
                  action: '',
                  onTap: () => state.switchSpaceHandler?.call(),
                ),
                Divider(height: 1, color: t.hairline),
                _SettingRow(
                  icon: Icons.delete_forever_outlined,
                  title: '销毁隐私空间',
                  subtitle: '永久删除隐私空间的全部本地与云端数据',
                  action: '',
                  onTap: _destroyPrivacySpace,
                ),
              ] else ...[
                Divider(height: 1, color: t.hairline),
                _SettingRow(
                  icon: Icons.enhanced_encryption_outlined,
                  title: '创建隐私空间',
                  subtitle: '另一个密码打开一份独立数据，外观与日常空间一致',
                  action: '',
                  onTap: _createPrivacySpace,
                ),
              ],
            ],
          ]),
        ]),
        if (isDesktopWindow)
          _group([
            _SectionTitle('剪藏'),
            _SettingCard(children: [
              InkWell(
                onTap: () => state.setClipEnabled(!state.clipEnabled),
                borderRadius: BorderRadius.circular(radiusLg),
                child: Padding(
                  padding: const EdgeInsets.all(spaceMd),
                  child: Row(
                    children: [
                      Icon(Icons.content_paste_outlined,
                          size: 20, color: t.inkMuted),
                      const SizedBox(width: spaceMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('启用剪藏服务',
                                style:
                                    Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 2),
                            Text('Chrome 插件经 127.0.0.1 直连本应用，不经云端',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: t.inkMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: spaceSm),
                      Switch(
                        value: state.clipEnabled,
                        onChanged: (value) => state.setClipEnabled(value),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.clipError != null) ...[
                Divider(height: 1, color: t.hairline),
                Padding(
                  padding: const EdgeInsets.all(spaceMd),
                  child: Text(state.clipError!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.danger)),
                ),
              ],
              Divider(height: 1, color: t.hairline),
              _SettingRow(
                icon: Icons.lan_outlined,
                title: '桥接端口',
                subtitle: '插件连接 127.0.0.1 使用的端口，改动立即生效',
                action: '${state.clipPort}',
                onTap: _editClipPort,
              ),
              Divider(height: 1, color: t.hairline),
              _SettingRow(
                icon: Icons.key_outlined,
                title: '配对令牌',
                subtitle: '点击复制，粘贴到插件设置完成配对',
                action: state.clipToken.isEmpty ? '生成中…' : '',
                detail: state.clipToken,
                onTap: _copyClipToken,
              ),
              Divider(height: 1, color: t.hairline),
              _SettingRow(
                icon: Icons.autorenew,
                title: '重新生成令牌',
                subtitle: '旧令牌立即失效，插件需重新粘贴',
                action: '',
                onTap: _regenerateClipToken,
              ),
              Divider(height: 1, color: t.hairline),
              _SettingRow(
                icon: Icons.extension_outlined,
                title: '安装 Chrome 插件',
                subtitle: '开发者模式加载仓库 extension/chrome 目录',
                action: '',
                onTap: _showClipInstall,
              ),
            ]),
          ]),
        _group([
          _SectionTitle('即将上线'),
          _SettingCard(children: [
            _DisabledRow(
                icon: Icons.enhanced_encryption_outlined,
                title: '正文端到端加密',
                subtitle: '正文加密后再上云，与已上线的密码锁、隐私空间无关'),
          ]),
        ]),
        _group([
          _SectionTitle('搜索范围'),
          Text(
            state.searchScope.isEmpty
                ? '当前搜索全部笔记本（全不选或全选均为全部）。'
                : '当前只搜索勾选的 ${state.searchScope.length} 个笔记本。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: t.inkMuted),
          ),
          const SizedBox(height: spaceSm),
          _SettingCard(children: [
            for (var i = 0; i < state.notebooks.length; i++) ...[
              if (i > 0) Divider(height: 1, color: t.hairline),
              CheckboxListTile(
                value: state.searchScope.isEmpty ||
                    state.searchScope.contains(state.notebooks[i].id),
                onChanged: (checked) {
                  final allIds =
                      state.notebooks.map((n) => n.id).toSet();
                  final current = state.searchScope.isEmpty
                      ? allIds
                      : {...state.searchScope};
                  if (checked ?? false) {
                    current.add(state.notebooks[i].id);
                  } else {
                    current.remove(state.notebooks[i].id);
                  }
                  state.setSearchScope(current);
                },
                title: Text(state.notebooks[i].name),
                secondary: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: Color(state.notebooks[i].color),
                      shape: BoxShape.circle),
                ),
                controlAffinity: ListTileControlAffinity.trailing,
              ),
            ],
            if (state.notebooks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(spaceMd),
                child: Text('还没有笔记本',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: t.inkFaint)),
              ),
          ]),
        ]),
        _group([
          _SectionTitle('关于'),
          _SettingCard(children: [
            InkWell(
              onTap: _onVersionTap,
              borderRadius: BorderRadius.circular(radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(spaceMd),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: t.inkMuted),
                    const SizedBox(width: spaceMd),
                    Expanded(
                      child: Text('版本',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    const SizedBox(width: spaceSm),
                    Text(_appVersion,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                                color: t.accentText,
                                fontFamily: monoFamily,
                                fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: t.hairline),
            _SettingRow(
              icon: Icons.system_update_outlined,
              title: '检查更新',
              subtitle: '从 GitHub Release 获取新版本，可应用内安装',
              action: '',
              onTap: () => checkUpdateManually(context, state),
            ),
          ]),
        ]),
      ];
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: spaceSm),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(letterSpacing: -0.1)),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
        child: Column(children: children),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    this.detail = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusLg),
      child: Padding(
        padding: const EdgeInsets.all(spaceMd),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.inkMuted),
            const SizedBox(width: spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.inkMuted)),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: t.accentText,
                            fontFamily: monoFamily,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: spaceSm),
            Text(action,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(
                        color: t.accentText, fontWeight: FontWeight.w600)),
            Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(radiusLg),
      child: Padding(
        padding: const EdgeInsets.all(spaceMd),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.inkMuted),
            const SizedBox(width: spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.inkMuted)),
                ],
              ),
            ),
            const SizedBox(width: spaceSm),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return Padding(
      padding: const EdgeInsets.all(spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: t.inkMuted),
          ),
          const SizedBox(width: spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    Text(valueLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                                color: t.accentText,
                                fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: t.inkMuted)),
                Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisabledRow extends StatelessWidget {
  const _DisabledRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = inkOf(context);
    return Opacity(
      opacity: 0.55,
      child: Padding(
        padding: const EdgeInsets.all(spaceMd),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.inkMuted),
            const SizedBox(width: spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: t.inkMuted)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: spaceSm, vertical: 3),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(radiusSm),
              ),
              child: Text('开发中',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          ],
        ),
      ),
    );
  }
}