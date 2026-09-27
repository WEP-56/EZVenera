# ADR-NW-2: 代理凭据处理

- Status: **ACCEPTED (draft)**
- Date: 2026-09-24
- Change: eink-proxy-hardening

## Context

代理可能需要认证（用户名/密码）。但 `SettingsController` 现有的持久化
（`app_settings.json` 明文、`toBackupJson`/`exportToPath` 会进备份）
与 NFR-002（安全）冲突。

## Decision

- 首版代理**仅支持无认证** HTTP(S) 代理。
- 凭据模型：
  - 代理 URL 可以含 userinfo（`http://user:pass@host`），但**只读取不持久化**：
    - 持久层只存 host/port/scheme；
    - URL 中的 userinfo 仅内存持有（本次会话），退出即丢。
  - 日志/备份/`.ezvenera` 导出**绝不包含** userinfo（导出前剥离）。
- 若用户需要认证代理，后续版本再引入加密存储（`flutter_secure_storage`
  类），且写入 `app_settings.json` 视为违反 NFR-002，禁止。

## Consequences

- 简单、无凭证泄露面；认证代理用户首版需要等后续版本。
- rhttp（WebDAV）路径支持 URL 内联认证：认证代理下的 WebDAV 同步可用。
- **Dio（dart:io HttpClient）路径不支持**：`PROXY host:port` 语法不携带
  凭据，也未接 `authenticateProxy` 回调，认证代理下插件请求/图片下载会
  收到 407 并按普通网络失败处理。处置：设置页提示已注明"认证代理目前
  仅对 WebDAV 同步生效"；网络日志拦截器对 407 输出专门警告。后续可经
  `HttpClient.authenticateProxy` 补齐 Dio 路径。
- **遗留问题（显式记录，本次未处置）**：WebDAV 密码目前明文持久化于
  `app_settings.json` 并随 `toBackupJson`/`exportToPath` 进入备份与远端，
  与 NFR-002 冲突；与代理凭据不同，它未在本次变更中剥离。计划按
  Decision 所述路线迁移 `flutter_secure_storage`。

## Alternatives

- 直接持久化密码 → 违反 NFR-002，拒绝。
