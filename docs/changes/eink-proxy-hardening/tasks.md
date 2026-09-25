# Tasks — E-Ink 适配、网络代理与稳健性加固

依赖有序；每项注明 REQ 映射与验证方法。
规模估计：P1 项约 3–4 个 PR，P2 项 2–3 个 PR，Rust 评估独立 PR。

## Phase 0 — 前置确认（无代码变更）

- [x] TASK-000 — 确认 rhttp 0.15.1 的 `ProxySettings` API 形状。
  **结论（2026-09-24，已验证）**：0.15.1 支持 `ClientSettings.proxySettings`
  与 `ProxySettings.noProxy()/proxy()/static()/list()`（读包源码
  `lib/src/model/settings.dart` 确认）。ADR-NW-1 已转 ACCEPTED。
- [x] TASK-000b — 确认 Dio 系统代理行为并定工厂写法。
  **结论**：`IOHttpClientAdapter.createHttpClient` 中显式设置 `findProxy`：
  system → `HttpClient.findProxyFromEnvironment`；custom → `PROXY host:port`；
  off → `DIRECT`。Android 无标准系统代理 API，system 档实际语义为
  环境变量代理（桌面有效，Android 通常直连），已在 UI 提示中说明。

## Phase 1 — 网络出口统一 + 代理（P1，REQ-005~008）

- [x] TASK-101 — `lib/src/network/network_client_factory.dart`
  （单例、`httpClient()` 工厂、`resolveProxyConfig()` 实时解析、
  网络日志拦截器）。REQ-008/012。
  验证：`flutter analyze` 零新增告警 + `test/network_proxy_test.dart` 4 例。
- [x] TASK-102 — `SettingsController` 增加 `ProxyMode` 三态
  （`proxyMode`：system/custom/off；`proxyUrl`），含解析、
  `isValidProxyUrl` 校验、持久化与 `toBackupJson`；凭据剥离
  （ADR-NW-2，`_sanitizeStoredProxyUrl`）。REQ-005。
  验证：持久化/备份/还原/重置 round-trip 单测。
- [x] TASK-103 — 设置页"网络"分区（入口卡片 + 三态单选 + URL 输入 +
  保存即生效提示 + 认证代理用法提示）。REQ-005/007。验证：analyze + 手动。
- [x] TASK-104 — 迁移 5 处裸 `Dio(` 到 `NetworkClientFactory`
  （plugin_runtime_controller / plugin_js_engine / plugin_image_loader /
  sources_page / settings_page×2）。REQ-006/008。
  验证：`grep -rn "Dio(" lib/` 仅剩工厂；全套测试通过。
- [x] TASK-105 — `RHttpAdapter` 动态构造 `ClientSettings`，按
  ADR-NW-1 接入三态代理（custom → `ProxySettings.proxy(url)`、
  off → `noProxy()`、system → 默认跟随系统）。REQ-006。
  验证：`test/webdav_auth_test.dart` 回归通过；代理链路待真机/局域网实测。

## Phase 2 — E-Ink 模式（P1，REQ-001~004）

- [x] TASK-201 — `SettingsController` 增加 eink 三键
  （`einkMode` 默认关 / `einkHighContrast` 默认开 / `einkFullRefreshHint`
  默认开）与解析/持久化/备份/重置。REQ-001。
  验证：`test/eink_settings_test.dart` round-trip + 默认值 3 例。
- [x] TASK-202 — `app.dart` 增加 `buildEinkThemeData(Brightness)`：
  纯黑/白配色、surface 全部收敛到背景色、`surfaceTint` 透明；
  `einkMode && einkHighContrast` 时覆盖 theme/darkTheme。REQ-003。
  验证：主题单测 3 例（亮/暗/无灰阶泄漏）。
- [x] TASK-203 — `reader_page.dart` 增加 `_isEink`/`_uiAnimDuration`：
  翻页（paged/horizontal-continuous/vertical-indexed 三种模式）、缩放、
  顶栏/底栏/进度条/抽屉引导的全部 Animated* 与 `AnimationController`
  在 E-Ink 下 0ms。REQ-002。验证：analyze；真机观察项见测试指南 E2。
- [x] TASK-204 — 全屏刷新提示：切章成功后 220ms 纯色遮罩
  （`_flashEinkRefresh`），由 `einkFullRefreshHint` 控制、阅读器抽屉
  可快捷开关。REQ-004。验证：真机观察项见测试指南 E3。
- [x] TASK-205 — 设置 → 外观 顶部新增「E-Ink 模式」区块
  （总开关 + 高对比度 + 切章刷新，后两项仅在总开关开启时显示）；
  阅读器抽屉新增切章刷新开关。REQ-001。验证：analyze + 真机 E0/E1。

## Phase 3 — 稳健性（P2/P1，REQ-009~011）

- [x] TASK-301 — 配置原子写 + 损坏文件兜底：新增
  `lib/src/utils/json_file_store.dart`（临时文件+rename 原子写；
  读取损坏/缺失/形状错误一律回退空 map 并告警），接入
  `SettingsController` 与 `AppStateController`（损坏自愈：兜底后即重写
  健康文件）；`SettingsController._persist` 复用 `toBackupJson()` 消除
  双份键值表。REQ-011。
  验证：`test/robustness_test.dart` 6 例（含"写中断不毁旧状态"）。
- [x] TASK-302 — 图片解码失败回退：两处 `Image` 增加 `errorBuilder`
  （解码错误不经过字节加载 Future，原先只会白屏/进全局错误钩子），
  失败记日志 + 重试前先 `ReaderImageCache.evict` 清除坏缓存后网络重载。
  REQ-009。验证：analyze；真机项见测试指南（注入坏缓存场景）。
- [x] TASK-303 — 下载单页重试：新增 `image_download_retry.dart`
  （最多 2 次重试、1s/2s 指数退避、非空校验），`DownloadController`
  接入；`DownloadJob.failedUnits` 计数，单页失败不再终止整个任务，
  完成消息汇总失败页数。REQ-010。
  验证：`test/robustness_test.dart` 5 例（成功/瞬时失败恢复/耗尽/空体/自定义次数）。
- [x] TASK-304 — 结构化网络日志：随 TASK-101 完成（工厂默认挂
  `_NetworkLogInterceptor`：失败必记、成功可选 `logSuccessResponses`），
  日志页（设置 → 日志）现有查看/导出能力直接展示 `[network]` 行。
  REQ-012。验证：代码路径 + 真机日志取证（测试指南 T1-T6）。

## Phase 4 — Rust 性能评估（P2，REQ-013）

- [x] TASK-401 — 基准工程（同机同数据对比，Dart AOT vs Rust release）：
  Dart：`scripts/benchmark_hotspots.dart`（dart compile exe 运行）；
  Rust：`benchmark/rust_benchmark/`（cargo run --release）。
  覆盖 H1 缓存键 md5 / H2 缓存修剪扫描 / H3 像素拷贝（rotate+range）。
- [x] TASK-402 — 结论与 ADR：`benchmark-report.md` + ADR-RT-1。
  **结论：三个候选热点均不迁移**——比率虽达 1.9×–6×，但绝对值
  （1.3µs–20ms）均在低频/后台/不可感知路径，且真正的高频性能路径
  （HTTP、PNG 编码、JS 引擎）已经由 rhttp/lodepng/quickjs 承担；
  迁移的 FRB 集成与 CI 交叉编译成本大于收益。H2 改进走纯 Dart
  算法路线（增量索引）。REQ-013 验证：基准数据可复现（源码在库）。

## 验证顺序

Phase 0 → 1 → 2 可并行两轨；Phase 3 依赖 Phase 1 的网络工厂；
Phase 4 完全独立可随时启动。每 Phase 结束跑
`flutter analyze` + `flutter test`（NFR-005）。
