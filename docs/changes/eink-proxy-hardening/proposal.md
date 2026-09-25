# Change: E-Ink 适配、网络代理与稳健性加固

## Proposal

### Why

用户为 EZVenera 提出了三条优化诉求，对应三类真实痛点：

1. **E-Ink 设备适配** — E-Ink（电子墨水）屏幕具有与普通 LCD/OLED
   截然不同的物理特性：刷新慢、残影（ghosting）、无背光、对比度依赖环境光、
   动画过渡在刷新时会产生大量闪烁和拖影。当前 EZVenera 的阅读器
   （`lib/src/pages/reader_page.dart`）大量使用位移动画、页面切换动画、
   `AnimatedContainer` / `AnimatedPositioned` / `AnimatedOpacity`，
   这些在 E-Ink 上会表现为连续"闪屏"，且 Material 3 主题使用大量低对比度
   的 surface 色阶，在 E-Ink 上可读性差。项目 README 明确欢迎
   "其他种类设备支持"类的 PR。
2. **代理设置** — 漫画源、图片 CDN、GitHub Release 更新、WebDAV 备份都
   走 HTTP(S)。在很多网络环境（校园网、公司网、国内访问被墙源站）下，
   用户必须通过代理才能访问。当前应用没有任何代理设置入口；Dio 的默认
   `IOHttpClientAdapter` 会跟随系统代理，但 rhttp 的 `ClientSettings`
   在 `rhttp_adapter.dart` 中是 `static const`，固定配置，用户无法在应用内
   指定代理。插件内 fetch、图片加载、WebDAV 各自持有独立的 Dio/rhttp
   实例，缺少统一出口。
3. **稳健性加固 + Rust 性能评估** — 代码中存在若干可预见的健壮性问题
   （详见 `specs/` 与 `design.md`），同时项目已依赖 `flutter_rust_bridge` +
   `rhttp`，评估把热点路径（图片缓存键、缩略图、磁盘修剪）迁移到 Rust
   的收益与成本。

### What

- 新增 **E-Ink 模式**（设置 → 外观），包括：禁用翻页/缩放动画、
  高对比度主题（纯黑/纯白、无 surface 色阶）、阅读器减少残影的刷新策略
  （翻页时全屏刷新提示、禁用位移动画）。
- 新增 **网络代理设置**（设置 → 网络），支持 HTTP/HTTPS 代理 URL 配置，
  覆盖：插件 JS fetch（`PluginJsEngine`）、图片加载（`PluginImageLoader`）、
  插件索引/安装/更新（`PluginRuntimeController`、`SourcesPage`）、
  GitHub Release 更新（`SettingsPage`）、WebDAV（`rhttp` 适配器、
  `BackupService`）。同时支持"系统代理 / 自定义代理 / 无代理"三态。
- **稳健性加固**：统一网络出口（单一 Dio 工厂 + 配置刷新）、
  配置读写加锁与原子写、图片解码失败降级、下载重试与校验和、
  异常上报结构化日志等（以 spec 为准）。
- **Rust 性能评估**：对候选热点做基准测量，产出"迁移 or 不迁移"的
  证据化结论（NFR-PERF-01）。

### Impact

- **用户**：E-Ink 用户获得可读的阅读体验；受代理限制环境的用户能正常
  访问图源与更新；所有用户获得更稳的启动与下载行为。
- **界面**：设置页新增两个入口（外观区、网络区）；阅读器 UI 无结构性
  改动，仅在 E-Ink 模式下切换动画与主题。
- **兼容性**：设置存储为追加式（新增键，不破坏旧备份文件）；
  插件 JS API 零改动；现有 `app_settings.json` 可无损升级。
- **迁移**：无数据迁移；默认行为（非 E-Ink 模式、系统代理）与现状一致，
  低风险。
- **运维**：日志增加结构化网络事件；代理账号密码**绝不落盘**（仅存于
  内存，或仅存用户名做显示）。

## Delta Requirements

见 `specs/requirements.md`（REQ-001 ~ REQ-0xx，每个带可测 AC）。
本 change 不修改既有 `docs/EZVenera_execution_plan.md` 中的既有规格。

## Design

见 `design.md`（含 ADR：代理凭据处理、网络出口统一、Rust 迁移边界）。

## Tasks

见 `tasks.md`（依赖有序，每项含 REQ 映射与验证方法）。

## Verification

- [ ] Requirements ↔ implementation checked
- [ ] Design/ADR ↔ implementation checked
- [ ] Tasks ↔ code checked
- [ ] Tests ↔ acceptance criteria checked
- [ ] Two-pass adversarial review completed

## Acceptance

| Requirement | Acceptance | Evidence | Result |
|---|---|---|---|
| REQ-001 | AC-001 | 手动在 E-Ink 设备验证 / 截图 |  |
| REQ-002 | AC-002 | 手动验证 / 自动化 widget test |  |
| … | … | … |  |

## Limitations / Residual Risk

- E-Ink 真机效果无法在本机（无 E-Ink 设备）完全量化，AC 以设备实测为准。
- 代理对个别图源自签证书/非标准端口场景可能需要额外 `bypass` 规则，
  首版只做全局代理 + 默认系统代理。
- Rust 迁移只有在基准显示可测收益且 CI 具备 Rust 交叉编译能力后才执行。
