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
- **可读性优先（项目规矩，2026-11-25 用户明确：这是笔记本应用）**：正文 ≥16px、行高 ≥1.7，正文对比度 ≥4.5:1（文字用 `accentText` 变体）；任何视觉改动不得牺牲可读性。
- 品牌绿 `#2E7D5B`（用户 2026-11-25 指定「好看的绿」，与 GaDou 的蓝绿 teal 区分；DTV 占红 #C14C50）。应用 UI 主色不变。
- **应用图标 = Fluent 2 现代玻璃风（用户 2026-11-25 多轮迭代定稿）**：翡翠渐变 squircle + 磨砂玻璃笔记本页 + 左下深绿玻璃块白色大写 N（与 OneNote 参考同语言、绿色区分）。**像素吉祥物被否**（与纸张编辑感 UI「风格不搭」）；**扁平硬边 Office 风被否**（「太像 80 年代」）；**外圈/圆环轮廓被否**（DTV/GaDou 都是圈，再加圈分不清）。源图 `assets/images/logo.png` 满幅方图（四角透明化），应用内 ClipRRect 圆角。
- macOS 图标按 Big Sur 网格：1024 透明画布中央 824×824 圆角方形（半径 ≈184），appiconset 程序化生成，勿直接用满幅图。**深色底在深色 Dock 里融底显小（真实教训）**：底色要亮、主体要大而简单。
- 笔记本主题色：`notebookPalette` 8 色按创建顺序自动循环（schema v2 color 列，迁移按 createAt 序回填）；**笔记本名称前不放图标，只放主题色圆点**（侧栏/笔记卡/设置页一致）；暂无手动换色入口。
- 附件（2026-11-25 用户拍板）：图片/文件本地内容寻址存储（sha256 去重，`onenote-asset://<64hex>` scheme，单文件 ≤20MB）；入口 = 编辑工具栏按钮 + 粘贴（剪贴板有图先插图）+ 拖拽；**GC 仅删「笔记 + 回收站 + 版本历史均未引用」的资源**，时机 = 启动 + 轮询，且必须在 `purgeExpired` 之后跑；渲染态点附件链接写临时文件用系统默认应用打开；Web 端附件随同步阶段支持（store 在 web 为 null，UI 提示）。

## 目录与关键文件

- `lib/data/app_db.dart`：drift 表（Notebooks/Notes/NoteVersions/Settings）与全部业务语义；时间戳一律毫秒 int，可注入 clock 便于测试；`allAttachmentRefs` 扫笔记 + 全部版本供附件 GC。
- `lib/data/attachment_store.dart`：附件内容寻址存储 + GC（`forTest` 构造可注入目录）。
- `lib/state/app_state.dart`：列表/作用域/搜索范围状态、附件 store 生命周期、`notebookColor`。
- `lib/ui/theme.dart`：InkTokens 主题扩展（暖纸色 + 墨色 + 品牌绿），`accentText` 是保证 4.5:1 的正文用主色变体，文字场景用它、填充用 `accent`。
- `lib/ui/`：home_page（宽屏三栏 / 窄屏 Drawer + 导航）、note_view（渲染/编辑/版本历史/附件上传）、settings_page、markdown_view、attachment_image。

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

同步引擎（WebDAV/OSS、manifest 差分、墓碑、轮询间隔、附件远端同步与 Web 端附件）、加密与笔记本锁、diff3 冲突面板、桥接服务与 MV3 插件（端口/token/配对方式待定）。