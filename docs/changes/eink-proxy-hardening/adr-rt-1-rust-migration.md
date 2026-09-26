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

## Addendum (2026-09-26): 插件 AES 为第一优先级迁移项（P-1）

本 ADR 原始决策只覆盖 H1/H2/H3 三个热点，**未覆盖插件解密路径**
（审查报告 v1/v2 U-2、v4 P-1 指出的盲区）。现补齐测量并修正优先级。

### 测量基线（`scripts/benchmark_aes.dart`，可复现）

| 场景 | 点位数 | pointycastle（AOT, x64 主机） |
|---|---|---|
| AES-ECB/CBC | 全部模式 | **13.3–15.4 MB/s**（加解密同量级） |
| 1 MB 图像解密 | — | ≈ 70 ms，且发生在 **UI isolate**（阻塞帧） |

原生实现（AES-NI / OS crypto）通常在 1 GB/s 量级，差距 **50–100×**，
显著大于 H1/H2/H3 的 1.9–6×。设备端（无 AES-NI）只会更差。

### 关键设计约束（迁移前必须知晓）

`convert` 桥接在 Dart 侧是**同步**返回（`_onMessage` →
`_handleConvert`），而 init.js 暴露给插件的 `Convert.*` 约定同步取值
（仅 `setTimeout`/delay 走 Promise）。因此**不能**用
`Isolate.run` 把解密挪到后台 isolate——那会把返回值变成 Future，
破坏所有未 await 的插件调用。可行的收敛路径：

1. **首选**：Rust（FRB）新增 `aes` 导出，保持同步 FFI 调用语义
   （FRB 同步调用零拷贝 `[Uint8List]`），模式覆盖 ECB/CBC/CFB/OFB
   （CFB/OFB 为部分漫画源所必需，注意 pointycastle 的
   `blockSize` 参数语义）；
2. 次选：平台通道（Android javax.crypto / Windows CNG），需维护
   双端实现，一致性靠测试向量保证。

### Decision 修正

- H1/H2/H3 维持不迁移；
- **插件 AES（convert 桥接的 aes-ecb/cbc/cfb/ofb）列为 Rust 迁移
  的第一优先级项**，触发条件：Rust 构建链（FRB 版本配对、双平台
  交叉编译）因其他需求落地时顺带实施，或出现插件解密卡顿的用户
  反馈时提前启动。
