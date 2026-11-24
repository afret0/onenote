# onenote

个人多端 Markdown 笔记（Flutter：mac / Windows / Linux / Android / Web PWA），WebDAV + OSS 增量同步。参考 OneNote 的组织体验，不做自由画布。

## 提交与 push（项目级常设授权，2026-11-25 用户明确）

- **每次任务完成（验证通过后）自动 `git commit` + `git push origin main`，不再逐次询问**。本授权仅覆盖本仓库，优先于全局「commit 逐次确认」规则；不写进全局白名单。
- 只提交本轮任务范围内的改动（显式列路径或确认 status 后 add），不扫入用户无关的本地文件；instructions 改动随当轮提交一并入库。
- commit message：中文短句描述本轮改动，带 `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` trailer。
- 验证失败（analyze/test/build 红）不提交；push 失败（远程分叉需 rebase、鉴权、hooks）停下报告，不 force push、不 amend 既有提交。

## 已确认的设计决策（用户拍板，不得擅改）

- 层级两级：笔记本 → 笔记；**非空笔记本禁止删除**（回收站里的笔记也算非空）。
- 笔记默认渲染（flutter_markdown_plus），点「编辑」才进源码编辑；**进入编辑前先同步一次**（同步引擎未落地，失败时放行离线编辑）。无 vim。
- 保存自动落库（800ms 防抖 + 完成/返回时保存）；`AppDb.saveNote` 先比对 title+content，**内容不变绝不记版本**。
- 版本历史仅存本地（省同步流量），保留 90 天；回收站软删除保留 90 天。两者天数可在设置页改（settings 表 `versionRetentionDays` / `trashRetentionDays`，缺省 90）。清理在启动 + 轮询时顺带跑（`AppDb.purgeExpired`）。
- 搜索默认全部笔记本，可多选范围（settings 表 `searchScope`，逗号分隔 id，**空 = 全部**）；回收站笔记不进搜索结果。
- 同步：启动 + 手动 + 定时轮询；远端故障/manifest 为空**绝不清本地**，「以远端为准重建」仅设置页手动触发；删除走墓碑。
- 冲突：diff3（行级 + 字符细化）三方合并，本地保存共同祖先快照；冲突以**结构化面板**逐块裁决（设备名 + 时间），笔记正文永不插入 `<<<<<<<` 标记。
- 加密：AES-256-GCM + Argon2id，每笔记本独立密钥；生物识别只解锁本地托管密钥，密码是恢复根；Linux 无生物识别回退密码。
- 剪藏：Chrome MV3 插件 → 应用内 127.0.0.1 桥接服务（Joplin 式），不经云端明文；插件不上架。
- 品牌色 `#D97706` 琥珀金（logo 像素环同色；DTV 已占红 #C14C50、GaDou 占绿，勿撞色）；logo 家族风格对齐 DTV/GaDou（深海军蓝底 + 像素吉祥物 + 彩环 + 右上黄闪电），源图 `assets/images/logo.png` 为满幅方图，应用内用 ClipRRect 圆角。
- macOS 图标必须按 Big Sur 网格：1024 透明画布中央 824×824 圆角方形（半径 ≈184），否则 Dock 里比其他应用图标显大且不和谐；appiconset 由满幅源图程序化加边距生成，勿直接用满幅图。

## 目录与关键文件

- `lib/data/app_db.dart`：drift 表（Notebooks/Notes/NoteVersions/Settings）与全部业务语义；时间戳一律毫秒 int，可注入 clock 便于测试。
- `lib/state/app_state.dart`：列表/作用域/搜索范围状态。
- `lib/ui/theme.dart`：InkTokens 主题扩展（暖纸色 + 墨色 + #C14C50），`accentText` 是保证 4.5:1 的正文用主色变体，文字场景用它、填充用 `accent`。
- `lib/ui/`：home_page（宽屏三栏 / 窄屏 Drawer + 导航）、note_view（渲染/编辑/版本历史）、settings_page、markdown_view。

## 命令与坑

```bash
dart run build_runner build --delete-conflicting-outputs   # 改 app_db.dart 表结构后必跑
flutter analyze && flutter test                            # 最小验证
flutter build web --release                                # web 产物在 build/web
```

- **web 数据库**依赖 `web/sqlite3.wasm` + `web/drift_worker.js` 两个静态文件（已入库）；升级 drift / sqlite3 包后要换成对应版本 release 的同名产物，否则 web 端起不来。
- drift_flutter 0.3.x 的 `DriftWebOptions` 参数名是 `sqlite3Wasm` / `driftWorker`（不是旧文档的 `sqlite3Uri` / `driftWorkerUri`）。
- widget 测试默认画布 800×600 走窄屏布局（侧栏在 Drawer 里），断言侧栏内容前先 `tester.view.physicalSize = const Size(1400, 900)` + `devicePixelRatio = 1.0` + `addTearDown(tester.view.reset)`。
- 字体已实例化为静态字重放 `assets/fonts/`（Inter 400-700、JetBrainsMono 400/500/700，OFL 许可同目录）；中文走系统字体 fallback 链（theme.dart），不内置 CJK 字体。标题用系统 serif（Georgia/Songti）营造编辑感。
- 平台图标由 logo 源图缩放生成（mac appiconset / android mipmap / web icons / windows ico），换 logo 时全平台同步重生成。

## 未实现（下一阶段，动工前先与用户确认边界值）

同步引擎（WebDAV/OSS、manifest 差分、墓碑、轮询间隔）、加密与笔记本锁、diff3 冲突面板、桥接服务与 MV3 插件（端口/token/配对方式待定）、附件对象存储。