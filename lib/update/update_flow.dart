import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_version.dart';
import '../data/app_db.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/update_dialog.dart';
import 'update_checker.dart';

Future<void> checkUpdateSilently(AppDb db, BuildContext context) async {
  if (kIsWeb) return;
  final current = await loadAppVersion();
  final release = await fetchLatestRelease();
  if (release == null || !context.mounted) return;
  final skipped = await db.getSetting(updateSkippedVersionKey);
  if (!shouldUpdate(current, release.version, skipped)) {
    developer.log(
        'skip, 启动检查无需提醒, current: $current, latest: ${release.version}, skipped: ${skipped ?? ''}');
    return;
  }
  if (!context.mounted) return;
  developer.log('hit, 启动检查发现新版本, latest: ${release.version}');
  final t = inkOf(context);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(seconds: 12),
    content: Row(
      children: [
        Expanded(child: Text('发现新版本 v${release.version}')),
        TextButton(
          onPressed: () async {
            await db.setSetting(updateSkippedVersionKey, release.version);
            developer.log(
                'done, 启动提醒里跳过版本, version: ${release.version}');
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            }
          },
          child: Text('跳过',
              style: TextStyle(color: t.inkMuted)),
        ),
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            showUpdateDialog(context, db: db, release: release);
          },
          child: Text('查看', style: TextStyle(color: t.accentText)),
        ),
      ],
    ),
  ));
}

Future<void> checkUpdateManually(BuildContext context, AppState state) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(
    content: Text('正在检查更新…'),
    duration: Duration(seconds: 30),
  ));
  final current = await loadAppVersion();
  final release = await fetchLatestRelease();
  messenger.hideCurrentSnackBar();
  if (!context.mounted) return;
  if (release == null) {
    messenger.showSnackBar(
        const SnackBar(content: Text('检查更新失败，请稍后重试')));
    return;
  }
  if (compareVersions(release.version, current) > 0) {
    await showUpdateDialog(context, db: state.db, release: release);
  } else {
    developer.log('done, 手动检查已是最新, current: $current');
    messenger.showSnackBar(SnackBar(content: Text('已是最新版本 $current')));
  }
}