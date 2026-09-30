# 方案：漫画简介页章节显示模式切换（行列表 / 网格矩阵）

- 状态：PROPOSAL（待评审后实施）
- 范围：`lib/src/pages/comic_details_page.dart`（`_ChaptersView` /
  `_ChapterTile`）+ `lib/src/reader/chapter_order.dart`（存储扩展）+
  `lib/src/localization/app_localizations.dart`
- 作者：ZCode / 2026-09-28
- 参考：Suwayomi 生态（Suwayomi-WebUI 及其 fork，如 Hanayomi）的
  布局切换惯例——**Compact grid / Comfortable grid / List** 三态、
  切换入口置于区块标题行、偏好按页面持久化。
  （调研备注：撰写时本机对 api.github.com 的访问间歇不可达，
  Suwayomi-WebUI 源码级对照未完成；本文参考其交互惯例而非逐行移植，
  实施前可再补一次源码核对。）

---

## 1. 背景与动机

当前简介页的章节区（`_ChaptersView`）只有**行列表**一种显示形态：
每个章节一张圆角卡（`ListTile`：章节名 + id + chevron），分组源用
`ExpansionTile` 折叠。问题：

1. **长章节浏览效率低**：数百章的条漫（如 800+ 话）在列表里翻找很深；
   网格矩阵一屏可见 3 列 × 10+ 行，扫视效率高一个数量级。
2. **与生态习惯不一致**：Tachiyomi/Mihon/Suwayomi 系读者普遍期待
   章节区可切换 list/grid。
3. 顺带补强：当前 `_ChapterTile` **没有任何已读态/进度态视觉**，
   列表与网格都应当标识"已读 / 读到此处"。

## 2. 需求（REQ / AC）

| ID | 需求 | 验收标准 | 优先级 |
|---|---|---|---|
| REQ-1 | 章节区支持 **List / Grid** 两种显示模式，切换入口位于章节卡标题行 trailing（与现有 Reverse 按钮并排），图标随状态切换（`view_list` / `grid_view`） | 点击后无需重建页面立即切换；图标与模式一致 | P1 |
| REQ-2 | 显示模式按 **漫画维度** 持久化（沿用章节排序的既有 per-comic 存储模式：`AppStateController` + `reader.chapterDisplay.<source>.<comic>`），未设置时回退全局默认 `list` | 退出简介页重进保持所选模式；另一部漫画不受影响 | P1 |
| REQ-3 | 网格模式自适应列数：`GridView.builder` + `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120)`（手机 3–4 列，平板/桌面 6–10 列），`childAspectRatio ≈ 1.5` | 手机与 Windows 宽窗口均无溢出、列数合理 | P1 |
| REQ-4 | 分组源（`isGrouped`）在网格模式下保持 `ExpansionTile` 分组结构，**组内**以网格铺开 | 分组/非分组两类源均可用 | P1 |
| REQ-5 | 网格单元显示章节短名（最多 2 行省略）+ 已读态视觉；同时把已读态增强同步到列表模式（已读灰化），**当前读到章**在两种模式下高亮描边 | 打开过的章节灰化；`HistoryController` 命中章高亮 | P2 |
| REQ-6 | 长章节（500+）不卡顿：网格用 `GridView.builder(shrinkWrap: true, physics: NeverScrollableScrollPhysics())` 嵌入现有滚动体；列表模式迁移为 `ListView.builder(shrinkWrap, NeverScrollable)`（惰性构建） | 800 章滚动 60fps（主观）；无 jank 告警 | P2 |

Out of scope（列入后续）：章节多选批量下载入口（另立 change）、
网格模式下显示 id 副标题（网格空间有限，仅短名 + 已读态）。

## 3. 设计

### 3.1 数据与状态

```dart
// chapter_order.dart 内追加（与既有 reversed 偏好对称）：
enum ChapterDisplayMode { list, grid }

String _chapterDisplayKey(String sourceKey, String comicId) =>
    'reader.chapterDisplay.${Uri.encodeComponent(sourceKey)}.'
    '${Uri.encodeComponent(comicId)}.mode';

ChapterDisplayMode chapterDisplayModeFor(String sourceKey, String comicId) =>
    AppStateController.instance.getString(_chapterDisplayKey(...)) == 'grid'
        ? ChapterDisplayMode.grid
        : ChapterDisplayMode.list;          // 缺省回退 list（老行为）

Future<void> setChapterDisplayModeFor(String s, String c, ChapterDisplayMode m)
```

- 存 `String`（`'grid'`）而非 int：与 `SettingsController` 的枚举持久化
  惯例一致，`AppStateController.getString` 已有。
- **不改 `app_settings.json`**：显示模式是"这部漫画怎么看"的偏好，
  与"排序反不反"同属 per-comic 维度；且不进 WebDAV 备份语义
  （AppStateController 已在备份内，行为自动正确）。

### 3.2 UI 结构

```
_ChapterListCard
  └─ _SectionCard(title: 'Chapters',
       trailing: Row(min) [ _ModeToggle, _ReverseButton ])   // REQ-1
       └─ _ChaptersView(mode: …)                             // 新增 mode 参数
            ├─ list: ListView.builder(shrinkWrap, NeverScrollable)
            │    └─ _ChapterTile（+ 已读灰化，REQ-5）
            └─ grid: …同上，但每组/整体为
                 GridView.builder(maxCrossAxisExtent: 120,
                                  childAspectRatio: 1.5,
                                  shrinkWrap, NeverScrollable)
                      └─ _ChapterGridTile（REQ-3/5）
```

- `_ModeToggle`：`IconButton(icon: mode == list ? Icons.grid_view : Icons.view_list)`，
  tooltip「切换显示模式」，点击回调上层 `setState` + 持久化（REQ-2）。
- `_ChaptersView` 由 `StatelessWidget` 保持不变，mode 从构造参数传入，
  状态提升到 `_ComicDetailsBody`（现有 `chaptersReversed` 状态就在那里，
  模式与其同生命周期管理，避免另建 controller）。

### 3.3 网格单元规格（`_ChapterGridTile`）

- 容器：圆角 10、`surfaceContainerHighest @0.38`（与列表卡同色系）；
  **已读**：文字 `onSurfaceVariant @0.5`（灰化）；**未读**：正常前景；
  **当前读到章**：1.5px `primary` 描边。
- 文本：章节名去前缀压缩显示（`第 123 话 xx` → 单元内 `123`，
  简单正则 `第\s*([0-9.]+)\s*[话話卷卷回]|Ch\.?\s*(\d+)` 提取，提取失败
  回退完整 title 2 行省略）——首版可先不提取、直接 title 2 行省略，
  提取列为 P2 增强。
- 最小命中区 ≥ 44dp；无 subtitle（网格空间限制，id 悬浮 tooltip）。

### 3.4 已读态判定（REQ-5 数据源）

`HistoryController.instance.find(sourceKey, comicId)` 已有漫画维度历史
（`page`/`chapterId`）。新增轻量判定：`chapterId == entry.chapterId` →
当前读到；章节序号 < 已读章节序号 → 已读（用 `_chapterItems` 序号对比，
分组/倒序都基于同一 `orderedChapter*` 排序结果，天然正确）。

### 3.5 性能与兼容

- `shrinkWrap + NeverScrollable` 在 500+ 章时仍会**全量构建**子项
  （builder 惰性只在外层视口生效）——网格 chip 足够轻，实测预期可接受；
  若实测卡顿，升级路径是把整页迁到 `CustomScrollView + SliverGrid/
  SliverList`（列为后续，不进首版）。
- E-Ink 兼容：网格为纯静态卡片，无动画；高对比主题下颜色语义由
  `buildEinkThemeData` 的纯黑白 ColorScheme 自动收敛。
- Windows 桌面宽屏：`maxCrossAxisExtent 120` 自动多列，无需断点代码。

### 3.6 本地化

| 键 | 中文 | 英文 |
|---|---|---|
| `chapters.displayMode` | 显示模式 | Display mode |
| `chapters.mode.list` | 列表 | List |
| `chapters.mode.grid` | 网格 | Grid |

## 4. 任务分解

- [ ] T1 `chapter_order.dart`：`ChapterDisplayMode` + 存取函数（含单测：
  缺省回退 / set-get round-trip / 特殊 sourceKey 转义）
- [ ] T2 `_ChaptersView` 接入 `mode` 参数；list 迁移 `ListView.builder`
  （REQ-6）；切换按钮入 trailing（REQ-1）
- [ ] T3 `_ChapterGridTile` + 网格布局（REQ-3/4，分组内网格）
- [ ] T4 已读态/读到章高亮（REQ-5，列表+网格一致）
- [ ] T5 l10n 三键 + analyze + 全量 test + 真机冒烟
  （含分组源、800 章长源、E-Ink 主题三场景）

## 5. 风险

| 风险 | 缓解 |
|---|---|
| 500+ 章 shrinkWrap 全量构建卡顿 | chip 轻 + P2 验收实测；升级路径 Sliver 迁移已明确 |
| 章节名提取正则对个别图源失效 | 提取失败回退完整 title，不做硬依赖 |
| E-Ink 上已读灰化对比度不足 | 用 `onSurfaceVariant@0.5` + 真机验证，必要时改纯黑描边 |

## 6. Open Questions

1. per-comic 记忆是否需要"跟随全局默认"的第三态？（首版：一旦手动切换
   即固化 per-comic；提供长按模式按钮重置回全局默认，实现成本极低）
2. 网格单元是否需要显示下载状态徽标（与未来批量下载联动）？——
   建议与批量下载 change 一并设计。
