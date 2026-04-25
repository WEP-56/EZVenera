# EZVenera 体检报告

更新时间：2026-04-25

## 范围

- 对照项目：`D:\venera\venera`
- 当前项目：`D:\venera\EZVenera`
- 真实源样本：`D:\venera\EZVenera-config`
- 重点模块：插件运行时、图片链路、阅读器、下载、本地页、设置/更新

## 本轮已落地修复

1. 插件运行时改为向 JS 暴露真实 `appVersion`，不再固定为 `0.1.0`。
   - 文件：`lib/src/plugin_runtime/plugin_runtime.dart`
2. 漫画页图片的 `onLoadFailed` 重试恢复为有上限的多次重试，接近原项目行为。
   - 文件：`lib/src/plugin_runtime/services/plugin_image_loader.dart`
3. 详情页、本地页中的远程封面改为优先走插件缩略图链路，避免 `Image.network` 绕过 headers/cookie/`onThumbnailLoad`。
   - 文件：`lib/src/pages/comic_details_page.dart`
   - 文件：`lib/src/pages/local_page.dart`

## 总览

| 模块 | 结论 | 说明 |
| --- | --- | --- |
| 插件运行时 | 中高风险 | 主链路可用，但仍有一批与原项目不一致的兼容点 |
| 图片链路 | 中风险 | 页面图片链路基本齐全，封面链路已补齐，仍有少量历史差异 |
| 阅读器 | 低风险 | 网络/下载/本地三类入口已打通，未见阻断性问题 |
| 下载 | 低风险 | 基础下载、失败清理、目录迁移可用 |
| 本地页 | 低风险 | 文件夹缺失处理完整，排序细节仍可优化 |
| 设置/更新 | 低风险 | 基础功能稳定，但依赖固定发布资产命名 |

## 模块体检

### 1. 插件运行时

#### 风险：`minAppVersion` 仍未真正生效

- 风险等级：高
- 原因：
  - EZVenera 解析插件时会读取 `minAppVersion`，但目前没有像原项目那样阻止不兼容源加载。
  - 原项目在 `lib/foundation/comic_source/parser.dart` 中会直接比较宿主版本并拒绝不满足条件的插件。
  - 本地真实源仓库中，大量源声明了高于当前 EZVenera `1.2.2` 的最低版本，例如 `ccc.js`、`comic_walker.js`、`copy_manga.js`、`happy.js`、`manga_dex.js`、`manhuaren.js` 等都声明了 `1.6.0`。
- 影响：
  - 用户可以安装“理论上不兼容”的源。
  - 这些源一旦依赖 EZVenera 未实现的新版能力，问题会以运行期异常而不是安装期提示的形式暴露。
- 建议修复：
  - 安装、更新、重载时都校验 `minAppVersion`。
  - 至少先在 UI 上给出明确告警，再决定是否强制阻止加载。

#### 风险：分类链路已补齐，但仍缺少系统回归

- 风险等级：中
- 当前状态：
  - 已支持 `categoryComics.optionLoader`
  - 已支持 `categoryComics.ranking.loadNext`
  - 已兼容原模板常见的 `categoryComics.ranking.loadWithNext`
- 真实源覆盖：
  - `optionLoader`：`jm.js`、`mh1234.js`、`mxs.js`
  - `ranking`：`ehentai.js`、`happy.js`、`hcomic.js`、`jm.js`、`komiic.js`、`picacg.js`、`wnacg.js`
- 剩余风险：
  - 还缺基于真实源的系统化手测和回归样本。
  - 动态选项返回空配置、混合分页模式切换等边界仍需继续验证。

#### 风险：保留能力之外的大量插件能力仍会“静默降级”

- 风险等级：中
- 原因：
  - EZVenera 当前没有接入原项目的 `explore`、`favorites`、`loadThumbnails`、`starRating`、`onClickTag`、`enableTagsTranslate` 等能力。
  - 真实源使用很广：
    - `explore`：33 个源
    - `favorites`：15 个源
    - `onClickTag`：23 个源
    - `enableTagsTranslate`：14 个源
- 影响：
  - 插件能安装，但行为与原项目不一致。
  - 用户会把“产品简化”误判成“插件坏了”。
- 建议修复：
  - 在源管理页补一个“能力支持矩阵/降级说明”。
  - 对明显依赖未接入能力的源增加提示。

### 2. 图片链路

#### 风险：封面链路曾绕过插件缩略图能力

- 风险等级：高
- 原因：
  - 详情页、本地页此前直接使用 `Image.network`。
  - 这会绕过 `onThumbnailLoad`、headers、cookie 与插件侧 URL 修正逻辑。
- 影响：
  - 需要鉴权、Referer 或缩略图重写的源会出现封面加载失败。
- 当前状态：
  - 本轮已修复，详情页和本地页改为优先走 `PluginImageLoader.loadThumbnail(...)`。

#### 风险：图片失败重试曾弱于原项目

- 风险等级：中
- 原因：
  - EZVenera 之前只允许页面图片单次 `onLoadFailed` 回退。
  - 原项目对漫画页图片保留了最多 5 次的重试窗口。
  - 真实源 `comick.js`、`ehentai.js` 确实使用了 `onLoadFailed`。
- 影响：
  - 某些带时效签名/一次性 URL 的图片源容错明显变差。
- 当前状态：
  - 本轮已修复为最多 5 次重试。

#### 风险：缩略图链路仍未系统验证 `onThumbnailLoad`

- 风险等级：低
- 原因：
  - 宿主已经实现 `comic.onThumbnailLoad`。
  - 但当前本地源仓库里没有真实源使用这一能力，缺少回归样本。
- 建议修复：
  - 后续增加一个最小测试源，覆盖 `onThumbnailLoad + headers + cookie` 组合。

### 3. 阅读器

#### 风险：本地/下载阅读排序问题已修复，但需要样本回归

- 风险等级：低
- 当前状态：
  - `lib/src/pages/reader_page.dart`
  - `lib/src/pages/local_reader_page.dart`
  - `lib/src/local_library/local_library_controller.dart`
  - 以上链路已切换到自然排序，`1 / 2 / 10` 不再按纯字符串顺序排列。
- 剩余风险：
  - 仍建议用几组真实目录样本验证：
    - `1.jpg 2.jpg 10.jpg`
    - `001.jpg 002.jpg 010.jpg`
    - `page-1.jpg page-2.jpg page-10.jpg`

### 4. 下载

#### 风险：失败时整本目录回滚，缺少“部分完成保留”策略

- 风险等级：低
- 原因：
  - 当前下载任务一旦失败或取消，会直接删除整个漫画目录。
  - 这与“保持库干净”一致，但不利于大体量下载排障。
- 影响：
  - 用户无法保留已成功章节做问题定位。
- 建议修复：
  - 保持默认清理策略不变，但可考虑增加“保留失败现场”开关。

### 5. 本地页

#### 风险：扫描范围是单层漫画目录假设

- 风险等级：低
- 原因：
  - 当前扫描规则假定“漫画目录下直接是章节目录，或目录本身直接放图片”。
  - 对更深层嵌套目录没有继续递归。
- 影响：
  - 某些用户自定义整理结构会被判定为空目录。
- 建议修复：
  - 保持当前规则作为默认行为。
  - 后续如有需要，可增加“递归深度”或“把当前目录视为单漫画”开关。

### 6. 设置 / 更新

#### 风险：更新流程依赖固定资产命名

- 风险等级：低
- 原因：
  - 当前更新逻辑按固定文件名匹配：
    - Windows：`windows-setup.exe`
    - Android：`android-release.apk`
- 影响：
  - 只要 GitHub Release 资产重命名，检查更新仍能成功，但下载资产会失败。
- 建议修复：
  - 优先匹配平台和扩展名，固定名只作为第一选择。
  - 最好在发布脚本里同步固化命名约定。

## 验证记录

- `flutter analyze`
  - 结果：通过
  - 时间：2026-04-25

## 建议的下一步顺序

1. 给插件安装/更新补 `minAppVersion` 校验与用户提示。
2. 为分类动态选项和排行 next-token 分页补真实源回归样本。
3. 用真实本地目录样本回归自然排序。
4. 把未接入插件能力整理到源管理页的“兼容性说明”。
