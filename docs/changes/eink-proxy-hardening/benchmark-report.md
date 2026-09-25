# Rust 性能评估基准报告（REQ-013 / TASK-401 / TASK-402）

- 日期：2026-09-24
- 结论速览：**三个候选热点均不建议迁移 Rust**（详见结论）。
- 环境：Ubuntu 26.04 x86_64，8 核，NVMe SSD；Dart AOT
  （`dart compile exe`，Dart 3.13.4，最接近生产 release 模式）；
  Rust 1.93.1 release profile（LTO, codegen-units=1）。
- 方法：同机同数据对比，每个基准先预热一次再计时；
  H2 基准数据 = 2000 文件 / 64 子目录的临时目录；
  H3 数据 = 1200×1800 RGBA（Uint32List/Vec<u32>）模拟典型漫画页。
- 复现：`scripts/benchmark_hotspots.dart`（dart compile exe 后运行）与
  `benchmark/rust_benchmark`（cargo run --release）。两份源码均在本仓库。

## 测量数据

| 热点 | 场景 | Dart AOT | Rust | 比率 (Dart/Rust) |
|---|---|---|---|---|
| H1 缓存键 md5 | 每图一次 | 1.32 µs/op | 0.37 µs/op | ~3.6× |
| H2 缓存修剪扫描（stat+排序，2000 文件） | 缓存超限时触发 | 20.6 ms/op | 3.4 ms/op | ~6.0× |
| H3 copyAndRotate90（整页） | 插件 modifyImage 时 | 8.5 ms/op | 4.5 ms/op | ~1.9× |
| H3 copyRange（600×900 区域） | 插件 modifyImage 时 | 2.0 ms/op | 0.35 ms/op | ~5.8× |

（本机单次采样；原始输出见附录）

## 结论（ADR-RT-1 依据）

| 热点 | 决定 | 理由 |
|---|---|---|
| H1 md5 缓存键 | **不迁移** | 绝对值微秒级且每图仅一次，收益不可观测 |
| H2 缓存修剪扫描 | **不迁移**（改算法不改语言） | 收益真实（6×）但触发频率低、非交互路径；更优解是把全量扫描改为增量 LRU 索引/延迟修剪（纯 Dart 算法优化），无需 FFI |
| H3 像素拷贝 | **不迁移** | 仅在插件提供 `modifyImage` 脚本时触发；且该管线的大头是解码（ui codec，native）与 PNG 编码（lodepng，已是 Rust），逐像素部分只剩 2–9 ms/图；再叠加 FRB 边界的 buffer 拷贝开销，实际收益更小 |

## 支撑论据

- 项目已在正确的位置使用了 Rust：HTTP（rhttp）、PNG 编码（lodepng）、
  JS 引擎（flutter_qjs/quickjs）。剩余 Dart 热点经测量均不在用户可感知
  路径上。
- 迁移成本侧：引入热点迁移需要 FRB 代码生成、CI 交叉编译
  （android-arm64/windows-x64）、pubspec 的 rhttp/FRB 版本配对约束
  联动升级——维护成本显著大于上表收益。
- 与 design.md D-4 预判对照：H1 预判"不迁移"（证实）；H2/H3 预判"候选"，
  量化后降级为"不迁移"。

## 局限性（诚实披露）

- UNKNOWN：设备端（ARM + eMMC flash）绝对耗时会更差数倍，但同机对比的
  方向性结论（Dart:Rust 比率）预计一致；未做设备端复现。
- Rust 原型是独立二进制，未计入 flutter_rust_bridge 集成的 FFI 边界
  开销（迁移收益上限因此高估而非低估）。
- 单机采样，样本量 5–20000 次/项（视 op 成本），未做多机复现；
  绝对值会随机器浮动，比率结论在同类桌面 x86 上稳定。

## 后续可选优化（非迁移路线）

1. H2：修剪触发后记录"上次扫描水位"，优先删除最旧分桶，避免每次全量
   stat（纯 Dart，预计把常见路径降到 <2ms）。
2. H3：若某图源 modifyImage 大量使用，可考虑整管线（decode→process→
   encode）下沉 Rust，一次 FFI 往返替代逐像素桥接——待真实图源
   profiling 证明必要后再立项。

## 附录：原始输出

```text
== Dart AOT ==
H1 md5 cache key: total 26 ms / 20000 ops = 1.32 µs/op
H2 cache trim scan (stat+sort, 2000 files): total 102 ms / 5 ops = 20598.80 µs/op
H3 copyAndRotate90 (1200x1800): total 170 ms / 20 ops = 8523.20 µs/op
H3 copyRange (600x900 region): total 80 ms / 40 ops = 2018.75 µs/op

== Rust release ==
H1 md5 cache key: total 7.342104ms / 20000 ops = 0.37 µs/op
H2 cache trim scan (stat+sort, 2000 files): total 17.19796ms / 5 ops = 3439.40 µs/op
H3 copyAndRotate90 (1200x1800): total 90.682523ms / 20 ops = 4534.10 µs/op
H3 copyRange (600x900 region): total 13.973757ms / 40 ops = 349.32 µs/op
```
