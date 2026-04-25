# EZVenera 插件兼容性清单

更新时间：2026-04-25

## 说明

- 结论基于三部分：
  - EZVenera 当前实现
  - 原项目 `venera` 的对应实现
  - 真实源样本 `D:\venera\EZVenera-config`
- 状态定义：
  - `已验证`：宿主已实现，且有真实源使用
  - `已实现/未系统验证`：宿主已实现，但缺少真实样本或缺少系统回归
  - `部分实现`：有主链路，但与原项目相比有明显缺口
  - `未接入`：当前简化版未纳入产品范围

## 保留能力清单

| 能力 | 状态 | 真实源样本 | 备注 |
| --- | --- | --- | --- |
| `account.login` | 已验证 | `ccc`、`ehentai`、`jm`、`picacg`、`wnacg` | 登录成功后会持久化账号数据 |
| `account.logout` | 已实现/未系统验证 | 无明确样本 | 宿主接口存在，但本地源仓库中未找到稳定覆盖样本 |
| `search.loadPage` | 已验证 | 大多数源 | 搜索主链路稳定 |
| `search.loadNext` | 已验证 | `hitomi`、`jcomic`、`manhuagui`、`manhuaren` | 仅在未定义 `search.load` 时启用 |
| `category` | 已验证 | 大多数源 | 固定/随机/动态分组已接入 |
| `categoryComics.load` | 已验证 | `jm`、`lanraragi` 等 | 基础列表加载可用 |
| `comic.loadInfo` | 已验证 | `ehentai`、`lanraragi`、`nhentai` 等 | 详情页主链路可用 |
| `comic.loadEpisode` | 已验证 | 全部阅读型源 | 阅读器、下载器都依赖该能力 |
| `comic.onImageLoad` | 已验证 | `ehentai`、`manwaba` | 图片 headers、重试、解扰已接入 |
| `comic.onThumbnailLoad` | 已实现/未系统验证 | 暂无真实样本 | 本轮已把详情/本地封面也接回该链路 |
| `settings` | 部分实现 | `baozi`、`ehentai`、`jm`、`manga_dex` 等 | 静态设置项可用；动态 getter 型设置未按原项目方式处理 |
| `idMatcher` | 已验证 | `hcomic`、`manhuaren`、`nhentai` | 低覆盖，但主链路存在 |
| `link` | 已验证 | `hcomic` | 低覆盖，功能本身已接入 |
| `translation` | 已验证 | `ehentai`、`jm`、`lanraragi`、`nhentai` 等 | 宿主已读取并提供翻译映射 |

## 已知差异

### 1. 分类页动态选项未补齐

- 状态：`部分实现`
- 原项目支持：
  - `categoryComics.optionLoader`
  - `categoryComics.ranking.loadWithNext`
- EZVenera 当前情况：
  - 仅支持静态 `optionList`
  - `ranking` 只支持按页码 `load(page)`
- 真实源影响：
  - `jm`
  - `mh1234`
  - `mxs`

### 2. 版本兼容约束未完全对齐

- 状态：`部分实现`
- 当前情况：
  - 宿主现在已经向 JS 暴露真实 `appVersion`
  - 但仍未像原项目一样严格阻止 `minAppVersion` 不满足的源加载
- 真实源影响：
  - 本地源仓库里有大量源声明 `1.4.0` 到 `1.6.0` 的最低版本

## 当前未接入但在真实源中常见的能力

| 能力 | 当前状态 | 真实源覆盖情况 | 说明 |
| --- | --- | --- | --- |
| `explore` | 未接入 | 33 个源 | 属于产品范围裁剪，不是 parser 漏实现 |
| `favorites` | 未接入 | 15 个源 | 真实源使用很多，用户容易误判为插件失效 |
| `onClickTag` | 未接入 | 23 个源 | 详情页标签当前只展示，不可跳转 |
| `enableTagsTranslate` | 未接入 | 14 个源 | 标签翻译能力未进入 EZVenera 产品面 |
| `comic.loadThumbnails` | 未接入 | `ehentai`、`lanraragi`、`wnacg` | 多页缩略图浏览未做 |
| `comic.starRating` | 未接入 | `ehentai`、`kavita`、`lanraragi`、`manga_dex` | 评分动作未接入 |
| `favorites.*` | 未接入 | `baozi`、`ccc`、`copy_manga`、`jm` 等 | 原项目收藏夹能力没有迁入 |
| `archive` 下载 | 未接入 | 模板中保留 | 简化版未纳入目标范围 |

## 建议使用说明

### 可以优先视为“当前兼容目标”的能力

- `search`
- `category`
- `comic.loadInfo`
- `comic.loadEp`
- `comic.onImageLoad`
- `settings`
- `translation`
- `idMatcher`
- `link`

### 安装插件时应额外留意的信号

- 源声明了较高 `minAppVersion`
- 源 heavily 依赖 `explore` / `favorites` / `onClickTag`
- 分类页依赖 `optionLoader`
- 详情页或封面依赖复杂缩略图逻辑

## 建议后续补充的验证样本

1. 做一个最小测试源，专门覆盖 `onThumbnailLoad`。
2. 做一个最小测试源，覆盖 `categoryComics.optionLoader`。
3. 做一个最小测试源，覆盖 `minAppVersion` 拒绝安装提示。
