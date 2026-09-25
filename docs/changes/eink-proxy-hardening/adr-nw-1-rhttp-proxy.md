# ADR-NW-1: rhttp (WebDAV) 代理能力

- Status: **ACCEPTED**
- Date: 2026-09-24
- Change: eink-proxy-hardening

## Resolution Update (2026-09-24, TASK-000 已执行)

`flutter pub get` 拉取 `rhttp 0.15.1` 后直接读包源码（`lib/src/model/settings.dart`）：

- **FACT（已验证）**：`ClientSettings` 含 `proxySettings` 字段（`ProxySettings?`）。
- **FACT（已验证）**：`ProxySettings.noProxy()` / `ProxySettings.proxy(url)`
  （= `StaticProxy.all`）/ `ProxySettings.static(url:, condition:)` /
  `ProxySettings.list([...])` 均存在于 0.15.1。
- **FACT（已验证）**：`proxySettings` 为 null 时默认"follow the system proxy"。

结论：走决策分支的 IF 路线 —— `RHttpAdapter` 改为按请求动态构造
`ClientSettings`，自定义代理用 `ProxySettings.proxy(url)`，关闭代理用
`ProxySettings.noProxy()`，系统代理保持 null。已实现于
`lib/src/utils/rhttp_adapter.dart`。

## Context

EZVenera 用 `lib/src/utils/rhttp_adapter.dart` 里的 rhttp 作为 WebDAV 客户端
（Dio adapter 形态）。WebDAV 备份/同步是网络出口之一，代理需求必须覆盖它。

事实（evidence）：

- `pubspec.yaml` 锁定 `rhttp: ^0.15.1`，注释："rhttp 0.15.1 was generated
  with flutter_rust_bridge 2.11.1 and rejects newer runtimes at startup"
  — 不可随意升版，代理改造必须基于 0.15.1 的 API。
- 上游 `Tienisto/rhttp` README（2026-09 通过代理抓取）确认：
  - `ProxySettings.noProxy()`、`ProxySettings.proxy('http://host:port')`、
    `ProxySettings.static(url:, condition:)`、`ProxySettings.list([...])` 存在
  - "By default, the system proxy is enabled"
  - 证据类型：**FACT（上游文档）**，但注意上游 README 描述的是较新版本，
    0.15.1 的具体 API 形状本机无可验证（无 Flutter SDK，无 pub 缓存）→
    **UNKNOWN** 待 TASK-000 落地确认。

## Decision

- IF TASK-000 确认 0.15.1 提供 `proxySettings` 字段：
  `RHttpAdapter` 不再用 `static const ClientSettings`，改为
  `NetworkClientFactory` 提供（响应代理热更新），构造
  `proxySettings: ProxySettings.proxy(url)` 或
  `ProxySettings.noProxy()`（代理关闭时）。
- ELSE：WebDAV 侧保持跟随系统代理（rhttp 默认），自定义代理对 WebDAV
  的覆盖标记为 P2 限制并写入 README 已知问题。

## Consequences

- 统一后 WebDAV 与其它出口行为一致：代理设置变更即时生效。
- 若 0.15.1 不支持代理字段，改动量最小化（仅保留系统代理），
  不触碰 rhttp 版本锁定。

## Alternatives

- 直接把 rhttp 升到支持代理的版本 → 违反 pubspec 配对约束，拒绝。
- WebDAV 改用纯 Dart Dio + proxy adapter → 放弃 Rust 性能优势与上游兼容
  （上游 Venera 也用 rhttp 做 WebDAV），拒绝。
