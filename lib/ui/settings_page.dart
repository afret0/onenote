import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../state/app_state.dart';
import 'dialogs.dart';
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

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _loadRetention();
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
    await _loadRetention();
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
                  if (state.uiFont == option.$1)
                    Icon(Icons.check, size: 18, color: inkOf(context).accentText),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await state.setUiFont(picked);
    }
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

  Future<void> _toggleScope(String notebookId, bool checked) async {
    final next = {...state.searchScope};
    if (checked) {
      next.add(notebookId);
    } else {
      next.remove(notebookId);
    }
    await state.setSearchScope(next);
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
          _SectionTitle('字体'),
          _SettingCard(children: [
            _SettingRow(
              icon: Icons.font_download_outlined,
              title: '界面字体',
              subtitle: '本应用包含小米 MiSans 字体，依其许可免费商用',
              action: state.uiFont == AppState.uiFontInter
                  ? 'Inter'
                  : 'MiSans',
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
          _SectionTitle('即将上线'),
          _SettingCard(children: [
            _DisabledRow(
                icon: Icons.lock_outline,
                title: '加密与锁定',
                subtitle: '端到端加密 · 密码 / 生物识别 · 笔记本单独锁定'),
            Divider(height: 1, color: t.hairline),
            _DisabledRow(
                icon: Icons.extension_outlined,
                title: '网页剪藏',
                subtitle: 'Chrome 插件 · 本地桥接直入应用'),
          ]),
        ]),
        _group([
          _SectionTitle('搜索范围'),
          Text(
            state.searchScope.isEmpty
                ? '当前搜索全部笔记本。勾选后只搜索所选笔记本。'
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
                value: state.searchScope.contains(state.notebooks[i].id),
                onChanged: (checked) =>
                    _toggleScope(state.notebooks[i].id, checked ?? false),
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
          if (state.searchScope.isNotEmpty) ...[
            const SizedBox(height: spaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => state.setSearchScope({}),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('恢复为搜索全部'),
              ),
            ),
          ],
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
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