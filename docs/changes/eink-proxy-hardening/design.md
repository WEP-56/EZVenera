# Design — E-Ink 适配、网络代理与稳健性加固

## Status

DRAFT (awaiting review)

## Context

EZVenera 的现状（G0 探索事实，均取自本仓库代码）：

- 网络出口分散，共 5 处裸 `Dio(`：
  - `lib/src/plugin_runtime/plugin_runtime_controller.dart:16` — 插件索引/安装/更新
  - `lib/src/plugin_runtime/engine/plugin_js_engine.dart:56` — 插件 JS fetch
  - `lib/src/plugin_runtime/services/plugin_image_loader.dart:50` — 图片加载
  - `lib/src/pages/sources_page.dart:24` — 图源管理
  - `lib/src/pages/settings_page.dart:1536,1744` — GitHub Release 检查与更新下载
- 另有两处独立网络设施：
  - `lib/src/utils/rhttp_adapter.dart` — WebDAV 专用 rhttp 适配器，
    `ClientSettings` 为 `static const`，**固定配置、无代理字段**
  - `lib/src/backup/backup_service.dart` — 通过上述 rhttp 适配器访问 WebDAV
- 阅读器动画集中：`lib/src/pages/reader_page.dart` 使用
  `AnimatedContainer`（180ms）、`AnimatedPositioned`（180ms）、
  `AnimatedOpacity`（160/180ms）、`PageView` 翻页动画（180ms）、
  缩放动画（180ms）。这些在 E-Ink 上都会闪屏。
- 主题：`lib/src/app.dart` 使用 `ColorScheme.fromSeed`，浅色背景
  `0xFFF7F4EC`，深色模式为 Material3 默认；无高对比度 E-Ink 变体。
- 设置持久化：`SettingsController._persist()` 直接 `writeAsString` 覆写
  `app_settings.json`，无原子写；`initialize()` 中 `jsonDecode` 失败会
  throw 导致启动失败（`AppBootstrap._initialize` 未捕获而展示错误页）。
- 图片解码：`_ReaderImageState.build` 中 `FutureBuilder` 失败会渲染
  错误卡片（已有），但 `ReaderImageCache._loadInternal` 磁盘缓存读到损坏
  文件时直接 throw；`PluginImageLoader._loadBytes` 失败有重试（5 次）
  但依赖 `onLoadFailed` 回调存在。
- 下载：`DownloadController._runJob` 单页失败即整个 job 失败
  （写入 `File.writeAsBytes` 无重试、无校验）。
- Rust 现状：pubspec 已依赖 `flutter_rust_bridge: 2.11.1` + `rhttp ^0.15.1`
  （两者配对，注释警告不可随意升版）；本机有 Rust 1.93 工具链。

## Decision

### D-1 网络出口统一为 `NetworkClientFactory`

- 新增 `lib/src/network/network_client_factory.dart`：
  `NetworkClientFactory.instance.httpClient({responseType, throwOnError, interceptors, logSuccessResponses})`。
- **实现说明（与初稿的偏差，2026-09-24）**：
  - 热更新不靠显式 `reloadFromSettings()` 调用，而是工厂**每次创建客户端时
    实时**从 `SettingsController` 解析 `ProxyConfig`（`resolveProxyConfig()`），
    且客户端按请求批次新建——代理变更天然即时生效（REQ-007），调用方零接入成本。
  - 不统一下发 connect/receive 超时：现有调用方（如应用内更新下载大 APK）
    依赖无限时等待，Phase 1 保持行为不变；超时统一收口移到 Phase 3 稳健性任务。
  - 无效的自定义代理 URL 回退到"跟随系统"行为并写告警日志，不让所有请求静默失败。
- 所有 5 处 `Dio(` 与 rhttp 适配器统一改用该工厂（TASK-104 已完成）：
  - `PluginRuntimeController` / `PluginJsEngine` / `PluginImageLoader` /
    `SourcesPage` / `SettingsPage`；
  - `RHttpAdapter` 的 `ClientSettings` 改为按请求动态构造（见 ADR-NW-1，
    已 ACCEPTED：rhttp 0.15.1 确认支持 `ProxySettings`）。
- 结构化日志（REQ-012）：工厂默认附加 `_NetworkLogInterceptor`——失败请求
  必记日志，成功请求由调用方通过 `logSuccessResponses: true` 选择性开启
  （图片加载等高频路径默认关闭，防日志爆炸）。

#### ADR-NW-1：代理如何处理（rhttp）

- 状态：**PROPOSED**
- 上下文：rhttp 0.15.1 的 README（上游 `/Tienisto/rhttp`）确认
  `ClientSettings(proxySettings: ProxySettings.proxy(url))` 存在；
  EZVenera 锁定的 0.15.1 是否包含相同 API 需
  `flutter pub deps` + 读本地缓存确认（本机无 Flutter SDK，标 UNKNOWN）。
- 决策：if 0.15.1 支持 `proxySettings` → 在 `RHttpAdapter` 动态构造
  `ClientSettings`；else → WebDAV 请求在 Rust 层保持跟随系统代理，
  并记录缺陷。代理对 WebDAV 的覆盖优先级为 P1，若 0.15.1 不支持则
  降为 P2 并明示限制。

#### ADR-NW-2：代理凭据

- 状态：**ACCEPTED (draft)**
- 决策：首版仅支持无认证 HTTP(S) 代理；"系统代理"由 `ProxySettings`
  默认行为（rhttp）与 Dio `IOHttpClientAdapter` 的系统代理发现承担。
  不持久化密码；若后续需要认证代理，凭据仅存内存 + 加密至少，
  写入 `app_settings.json` 视为违反 NFR-002。

### D-2 E-Ink 模式

- 新增设置键：`einkMode`（bool，默认 false）、
  `einkFullRefreshHint`（bool，默认 true）、
  `einkHighContrast`（bool，默认 true），
  枚举 `EinkMode` 由 `SettingsController` 承载（复用现有 setter 模式）。
- `lib/src/app.dart`：
  - `theme`：当 `einkMode && einkHighContrast` 时，替换为
    `_einkHighContrastTheme`（纯背景 `0xFF000000`/`0xFFFFFFFF`，
    无 surface 色阶，介于 `ThemeMode.light/dark` 之外独立指定）。
  - 阅读器设置由 `_ReaderSettingsDrawer` 增加 E-Ink 分区开关，
    由 `SettingsController.instance` 驱动 `AnimatedBuilder` 即时生效。
- `lib/src/pages/reader_page.dart`：
  - 新增 `bool get _isEink`；当 `_isEink` 时：
    - `_moveToPage` / 连续滚动：`animateTo` → `jumpTo`（复用
      `readerEnablePageAnimation` 的 false 分支逻辑，无需改封装）；
    - `_ReaderImageState._animateTo`（缩放）→ 直接 `_resetZoom`；
    - `AnimatedContainer/AnimatedPositioned/AnimatedOpacity` →
      以 `duration: Duration.zero` 覆盖（封装为 `_einkDuration()` 帮助函数，
      避免到处 if）。
  - 全屏刷新提示：翻页/章节切换时若 `einkFullRefreshHint`，
    显示一次性全屏遮罩（500ms 白/黑闪）提示残影清除。
- 本地化：`app_localizations.dart` 增加三个键（中英）。

### D-3 稳健性加固

- **配置原子写**（REQ-011）：`SettingsController._persist` 改为
  `writeAsString(临时文件) → rename(目标)`；`initialize()` 用
  try/catch 包裹 `jsonDecode`，失败时记日志并以默认值启动（不再抛错页）。
  同样应用于 `AppStateController._persist`。
- **图片解码降级**（REQ-009）：`ReaderImageCache._loadInternal` 磁盘缓存
  读取后校验非空；`decodeImage` 失败时删除坏缓存文件并回退网络重载一次。
- **下载重试与校验**（REQ-010）：`DownloadController._runJob` 图片写入前
  校验 `bytes.isNotEmpty`，失败重试 2 次（指数退避 1s/2s），重试仍失败则
  标记该图片失败并继续（不整体失败），job 汇总失败数。
- **结构化日志**（REQ-012）：`AppLogger` 增加 `network()` 事件；
  `NetworkClientFactory` 在 Dio 拦截器中记录 method/url/status/耗时/代理。

### D-4 Rust 性能评估（REQ-013，产出结论，不承诺迁移）

- 候选热点（按 README 与代码盘点）：
  1. **图片缓存键 MD5** — `ReaderImageCache._cacheKey` 每图一次，
     Dart `crypto` 已够快，预计**不迁移**（收益 < 0.5ms/图，成本高）。
  2. **磁盘缓存修剪** — `_trimDiskCacheIfNeeded` 全量扫描 + stat，
     大缓存（数百 MB/数千文件）时可能卡顿，候选迁移或改为增量 LRU 索引。
  3. **缩略图/图片解码** — 已有 `lodepng_flutter`（Rust）与
     `rhttp`（Rust），解码已在 Rust 侧；Dart 侧 `_RuntimeImage`
     （`PluginImageModifier`）的逐像素拷贝是纯 Dart 热点，候选迁移。
  4. **插件 JS 执行** — `flutter_qjs` 已内置 JS 引擎，属"固有成本"，
     不迁移。
- 结果（2026-09-24，已执行）：Dart AOT vs Rust release 同机对比，
  数据与结论见 `benchmark-report.md` + ADR-RT-1——**三项均不迁移**，
  H2 改进走纯 Dart 算法路线。基准工程：
  `scripts/benchmark_hotspots.dart` + `benchmark/rust_benchmark/`。

## Alternatives

- A1 网络层：逐个 Dio 实例原地加 proxy（不建工厂）→ 会导致代理热更新
  无法统一、代码重复 5 处；否决。
- A2 E-Ink：全局硬编码检测厂商/屏幕类型自动开 E-Ink → 误伤非 E-Ink 平板；
  首版手动开关即可；列为 OQ-001 后续。
- A3 E-Ink 动画：直接删除动画功能 → 影响普通 LCD 用户；否决，用
  `einkMode` 条件覆盖。
- A4 Rust：整体重写网络栈 → 破坏插件兼容与 rhttp 配对约束；否决。

## Risks

- R-1（高）：rhttp 0.15.1 的 `ProxySettings` API 形状未验证 → 缓解：
  先本地拉取依赖确认；不行则 WebDAV 代理延后（ADP-NW-1 已述）。
- R-2（中）：E-Ink 效果需真机验证，本机无设备 → 缓解：AC 写为设备实测，
  提供截图/录屏模板；发布前由用户验证。
- R-3（中）：Dio 系统代理在 Android 上依赖平台网络栈，行为因设备而异
  → 缓解：三态开关显式化，兜底文档。

## ADR 索引

- ADR-NW-1（rhttp 代理能力）：PROPOSED
- ADR-NW-2（代理凭据不落盘）：ACCEPTED (draft)
- ADR-<future>（Rust 迁移范围）：待 benchmark 后追加
