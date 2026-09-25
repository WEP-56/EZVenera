# ADR-RT-1: 热点路径是否迁移 Rust

- Status: **ACCEPTED（基于测量数据）**
- Date: 2026-09-24
- Change: eink-proxy-hardening

## Context

REQ-013 要求评估"是否可以用 Rust 提高性能"。项目已有 Rust 组件
（rhttp / lodepng / quickjs），剩余候选热点为：H1 缓存键 md5、
H2 缓存修剪扫描、H3 modifyImage 像素拷贝。
基准测量见 `benchmark-report.md`（同机 Dart AOT vs Rust，
比率 1.9×–6×，但绝对值均在微秒–数毫秒级、低频路径）。

## Decision

**不迁移**任何热点到 Rust。理由：

1. 收益不可观测：最重的 H2 全量扫描也只在缓存超限时后台触发，
   20ms（桌面）/数十 ms（设备）用户无感。
2. 性能关键路径已在 Rust：HTTP 与 PNG 编码是真正的每帧高频操作，
   已由 rhttp/lodepng 承担。
3. 成本不对称：FRB 集成 + CI 双平台交叉编译 + 版本配对约束
   （pubspec 已警告 rhttp 0.15.1 ↔ FRB 2.11.1 锁定）显著大于收益。

改进走纯 Dart 算法路线（见 benchmark-report.md"后续可选优化"）。

## Consequences

- Phase 4 产出为评估结论 + 可复现基准工程，不产生运行时变更。
- 未来若新增每帧级 Dart 像素处理（如全局灰度化/去残影滤镜），
  按 benchmark-report 的"整管线下沉"路线重新评估，而不是逐像素桥接。
