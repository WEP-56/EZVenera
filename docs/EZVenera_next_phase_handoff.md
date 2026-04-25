# EZVenera 下一阶段接手文档

更新时间：2026-04-25

本文用于在新对话中快速接手 `EZVenera` 当前状态，并继续推进下一阶段工作。

项目路径：
- 简化版项目：`D:\venera\EZVenera`
- 原项目参考：`D:\venera\venera`
- 打包输出目录：`D:\venera\pack`
- 插件源仓库：`https://github.com/WEP-56/EZvenera-config`

当前版本：
- `pubspec.yaml`：`1.2.2+3`

当前分支状态：
- 分支：`main`
- 远端：`origin/main`
- 最近提交：
  - `de6c356` 更新版本号
  - `fc2f848` 添加更新功能，修复 Windows 安装桌面快捷方式问题，修复漫画卡片文本溢出问题
  - `b3998e3` Add community appreciation section to README

---

## 1. 本阶段接手目标

下一阶段的核心目标有 3 个：

1. 做一轮全面“体检”  
   对比 `D:\venera\venera` 与 `D:\venera\EZVenera` 的各模块，尤其是插件模块和图片/阅读/下载链路，排查简化过程中遗漏的兼容性细节，提升稳定性、兼容性，避免再次出现类似最初 `jm.js` 图片错乱那种问题。

2. 编写详细易读的中文版文档  
   目标有两个文档：
   - 接手开发的程序员可以快速了解项目（项目结构）
   - 想要自制插件的用户可以更方便（插件制作）

3. 将上述两个文档做成一版 GitHub Pages HTML 文件  
   用于直接在线阅读。

---

## 2. 当前项目状态总览

EZVenera 目前已经不是“空壳”或“仅能跑起来”的阶段，而是一个可用的 Windows / Android 简化版。

已具备的主能力：
- 插件运行时
- 搜索
- 分类
- 漫画详情
- 阅读器
- 下载
- 本地页（历史 / 收藏 / 下载 / 自定义漫画文件夹）
- 漫画源管理
- 基础设置
- GitHub Release 更新检测与下载
- Windows / Android 双平台打包

当前重点已经从“补齐基础功能”转向：
- 稳定性、兼容性
- 与原项目关键行为保持一致
- 文档体系
- 发布维护能力

---

## 3. 最近这轮会话完成的关键工作

### 3.1 插件与图片处理

已修复 `jm.js` 源图片乱序问题。

根因：
- `jm.js` 本身没有问题
- 问题在 EZVenera 的图片解扰执行器
- EZVenera 复用同一个 JS 引擎执行 `modifyImage`
- JM 源每次都会声明 `let modifyImage = ...`
- 第二张图开始重复声明，异常被吞掉，导致返回原始错乱图

修复位置：
- `lib/src/plugin_runtime/services/plugin_image_modifier.dart`

修复方式：
- 改为每次在独立作用域中内联执行脚本
- 避免 `modifyImage` 重复定义污染全局上下文

这是下一阶段“稳定性体检”的典型案例，必须作为检查模板反向推广到其他源和其他插件能力。

### 3.2 本地页重构

本地页已重构为“文件夹”式结构。

当前能力：
- 左侧目录：
  - 历史
  - 收藏
  - 下载
  - 用户自定义漫画文件夹
- 支持添加漫画文件夹
- 支持扫描本地目录下的漫画
- 支持本地漫画阅读与历史恢复

关键文件：
- `lib/src/pages/local_page.dart`
- `lib/src/local_library/local_library_controller.dart`
- `lib/src/local_library/local_library_models.dart`
- `lib/src/pages/local_reader_page.dart`
- `lib/src/library/history_models.dart`

### 3.3 阅读器增强

本轮已把阅读器从“粗浅实现”推进到“可用的统一阅读器”。

当前已完成：
- 网络漫画 / 下载漫画 / 本地文件夹漫画统一入口
- 双击缩放
- 再次双击缩回
- 缩放状态下锁定页视图翻页，避免误翻页
- 去掉滚轮缩放，只保留滚轮翻页
- 顶部设置按钮
- 阅读器设置侧边栏
- 右下角快捷功能：
  - 下载
  - 全屏
  - 自动翻页
- 阅读器内设置持久化：
  - 点击翻页
  - 反转点击翻页
  - 双击缩放
  - 页面动画
  - 自动翻页间隔

关键文件：
- `lib/src/pages/reader_page.dart`
- `lib/src/settings/settings_controller.dart`
- `lib/src/localization/app_localizations.dart`

### 3.4 主壳层与搜索页

已完成：
- Windows 窗口尺寸记忆
- 主导航栏支持折叠 / 展开
- 搜索表单改为“keyword 主导”的展开 / 收起式交互

关键文件：
- `lib/main.dart`
- `lib/src/shell/windows_window_frame.dart`
- `lib/src/shell/main_shell.dart`
- `lib/src/pages/search_page.dart`

### 3.5 设置页更新流程

已完成设置页“关于”里的更新流程基础版：
- 检查 GitHub `releases/latest`
- 识别 tag 格式 `vx.x.x`
- 判断平台：
  - Windows 下载 `setup.exe`
  - Android 下载 `apk`
- 显示下载进度
- 下载完成后拉起安装
- Windows 下尽量保证旧版本退出后再启动安装程序

关键文件：
- `lib/src/pages/settings_page.dart`

### 3.6 卡片溢出与 Windows 安装器问题

已修复：
- 搜索结果 / 分类结果卡片文字超出卡片边界
- Windows 安装器不创建桌面快捷方式

关键文件：
- `lib/src/widgets/comic_card_grid.dart`
- `scripts/windows_installer.nsi`

### 3.7 图标、版本、打包

已完成：
- Windows 图标替换
- Android 启动图标替换
- 版本号更新
- Windows setup / Android APK 打包

关键文件：
- `assets/ico.ico`
- `assets/ico.png`
- `windows/runner/resources/app_icon.ico`
- `android/app/src/main/res/mipmap-*/ic_launcher.png`
- `pubspec.yaml`
- `scripts/build_release.ps1`

---

## 4. 当前代码结构速览

### 4.1 主模块目录

`lib/src` 下主要目录：
- `bootstrap`：启动初始化
- `downloads`：下载任务、下载库
- `library`：历史、收藏、JSON 存储
- `local_library`：自定义本地漫画文件夹扫描
- `localization`：本地化文案
- `navigation`：主导航定义
- `pages`：主要页面
- `plugin_runtime`：插件运行时核心
- `reader`：阅读器缓存等支撑服务
- `settings`：设置控制器
- `shell`：Windows 标题栏 / 主壳层
- `state`：页面状态持久化
- `widgets`：共用 UI 组件

### 4.2 插件运行时关键文件

必须优先熟悉：
- `lib/src/plugin_runtime/plugin_runtime.dart`
- `lib/src/plugin_runtime/plugin_runtime_controller.dart`
- `lib/src/plugin_runtime/models.dart`
- `lib/src/plugin_runtime/result.dart`
- `lib/src/plugin_runtime/parser/plugin_source_parser.dart`
- `lib/src/plugin_runtime/engine/plugin_js_engine.dart`
- `lib/src/plugin_runtime/services/plugin_image_loader.dart`
- `lib/src/plugin_runtime/services/plugin_image_modifier.dart`
- `lib/src/plugin_runtime/storage/cookie_store.dart`
- `lib/src/plugin_runtime/storage/plugin_data_store.dart`

### 4.3 阅读器关键文件

- `lib/src/pages/reader_page.dart`
- `lib/src/reader/reader_image_cache.dart`

### 4.4 本地页关键文件

- `lib/src/pages/local_page.dart`
- `lib/src/local_library/local_library_controller.dart`
- `lib/src/local_library/local_library_models.dart`
- `lib/src/library/history_controller.dart`
- `lib/src/library/favorite_controller.dart`
- `lib/src/downloads/download_controller.dart`

### 4.5 打包与安装器

- `scripts/build_release.ps1`
- `scripts/windows_installer.nsi`
- `scripts/windows_installer.iss`

---

## 5. 下一阶段任务一：全面“体检”

这是最高优先级任务。

### 5.1 总体原则

不是要把原项目所有功能抄回来，而是：
- 只对比 EZVenera 保留的功能
- 找出“简化后缺失的稳定性保护、兼容性细节、边界处理”
- 尤其关注插件执行链路、阅读链路、图片链路、下载链路

换句话说，目标不是“功能更多”，而是“保留下来的功能更稳、更兼容”。

### 5.2 建议体检范围

建议按模块逐项对照 `D:\venera\venera`：

1. 插件运行时
   - JS 引擎初始化
   - `ComicSource` API 暴露完整性
   - parser 对能力的解析是否一致
   - 登录态、cookie、持久化数据
   - `onImageLoad` / `onThumbnailLoad`
   - `modifyImage`
   - `onLoadFailed`
   - `onResponse`
   - 设置项读取
   - 本地化 / `translation`
   - 链接跳转 / `link`

2. 图片下载与图片改造
   - 图片请求 headers
   - 请求失败重试
   - JS 回调结果类型兼容
   - 图片解扰脚本是否能重复执行
   - 缓存命中后是否影响新逻辑

3. 阅读器
   - 章节切换
   - 历史恢复
   - 网络 / 下载 / 本地目录 3 类阅读路径
   - 缩放和翻页的边界行为
   - 自动翻页与章节末尾行为

4. 下载
   - 下载封面
   - 多章节下载
   - 下载中断 / 失败清理
   - 下载目录迁移

5. 本地页
   - 文件夹扫描规则
   - 目录不存在时的处理
   - 历史恢复到本地文件夹漫画

6. 设置 / 更新
   - 设置项持久化
   - 更新检查与安装链路
   - Android / Windows 差异处理

### 5.3 插件模块体检重点

插件模块必须作为第一优先级，因为最初的问题就发生在这里。

建议专项输出一份“插件兼容性体检表”，对每个保留能力逐项确认：
- EZVenera 是否实现
- 与原项目实现差异
- 是否有已知风险
- 是否有已验证的真实源

至少要覆盖这些能力：
- `account.login`
- `account.logout`
- `search.loadPage`
- `search.loadNext`
- `category`
- `categoryComics.load`
- `comic.loadInfo`
- `comic.loadEpisode`
- `comic.onImageLoad`
- `comic.onThumbnailLoad`
- `settings`
- `idMatcher`
- `link`

### 5.4 体检产出要求

建议最后至少产出两份东西：

1. 模块体检报告  
   以“模块 -> 风险 -> 原因 -> 建议修复”的形式输出。

2. 插件兼容性清单  
   明确哪些功能是“已验证稳定”、哪些是“理论支持但未系统验证”。

### 5.5 建议体检顺序

建议顺序：

1. 插件运行时
2. 图片下载 / 图片改造
3. 阅读器
4. 下载
5. 本地页
6. 设置 / 更新

---

## 6. 下一阶段任务二：中文版文档

这一项要产出两份“详细易读”的中文文档。

### 6.1 文档目标

要同时满足两类读者：

1. 接手开发的程序员
   - 能快速了解项目结构
   - 能快速定位关键模块
   - 能知道主要运行流程
   - 能知道哪些地方和原项目不同

2. 想自制插件的用户
   - 能理解 EZVenera 插件的能力边界
   - 能知道如何写一个插件
   - 能知道如何调试常见问题

### 6.2 建议文档一：项目结构文档

建议文件目标：
- 面向开发者

建议内容大纲：

1. 项目定位
   - EZVenera 是什么
   - 和原项目 `venera` 的关系
   - 平台范围：Windows / Android

2. 目录结构
   - `lib/src` 各目录职责
   - `docs`
   - `scripts`
   - `windows`
   - `android`

3. 运行流程
   - 启动流程
   - 主壳层与页面切换
   - 插件加载流程
   - 搜索 / 分类 / 详情 / 阅读 / 下载 流程

4. 核心模块说明
   - `plugin_runtime`
   - `reader`
   - `downloads`
   - `local_library`
   - `settings`
   - `shell`

5. 持久化
   - AppState
   - 设置
   - 历史 / 收藏
   - 插件数据 / cookie

6. 与原项目的主要差异
   - 保留了什么
   - 删掉了什么
   - 简化的代价与注意事项

7. 构建与打包
   - 分析命令
   - 打包命令
   - Windows setup / Android APK

### 6.3 建议文档二：插件编写文档

建议文件目标：
- 面向插件作者

建议内容大纲：

1. 插件是什么
   - 插件脚本文件位置
   - 插件能力边界

2. 插件最小结构
   - `name`
   - `key`
   - `version`
   - `minAppVersion`
   - `search`
   - `category`
   - `comic`

3. 可用 API 说明
   - `Convert`
   - `Network`
   - `HtmlDocument`
   - `UI`
   - `Comic`
   - `ComicDetails`
   - `ImageLoadingConfig`
   - `Image`

4. 能力逐项说明
   - 登录
   - 搜索
   - 分类
   - 详情
   - 章节页
   - 图片加载
   - 图片解扰
   - 设置项
   - 链接识别

5. 常见示例
   - 最小搜索源
   - 带分类源
   - 带图片解扰源
   - 带登录源

6. 常见坑
   - `onImageLoad` 返回值格式
   - `modifyImage` 作用域
   - cookie 与登录态保存
   - `loadInfo` 和 `loadEpisode` 的耦合
   - 需要 headers 的图片源

7. 调试建议
   - 如何打印日志
   - 如何隔离问题
   - 如何确认是插件问题还是宿主问题

### 6.4 文档写作要求

要求：
- 全中文
- 结构清楚
- 例子尽量完整
- 不要只写“概念”，必须带路径、带真实文件名、带最小代码示例
- 要尽量贴合 EZVenera 当前实现，而不是原项目旧实现

---

## 7. 下一阶段任务三：GitHub Pages HTML

要把“项目结构文档”和“插件编写文档”各做一版 HTML。

### 7.1 建议输出方式

建议不要一开始就引入复杂站点生成器，先做一版静态 HTML 即可。

建议目录：
- `docs/site/index.html`
- `docs/site/project-structure.html`
- `docs/site/plugin-guide.html`
- `docs/site/assets/*`

### 7.2 建议要求

1. 页面可直接在 GitHub Pages 托管
2. 中文排版清晰
3. 目录导航清晰
4. 代码块样式清楚
5. 移动端可阅读

### 7.3 建议内容结构

`index.html`
- 项目简介
- 两个文档入口

`project-structure.html`
- 项目结构文档 HTML 版

`plugin-guide.html`
- 插件编写文档 HTML 版

### 7.4 视觉要求

不要做成默认白底黑字文档页就交差。

建议：
- 和 EZVenera 当前产品视觉保持一致
- 有明确的标题层级
- 代码块、提示块、注意事项要可视化区分

---

## 8. 当前实现中需要特别知道的事实

### 8.1 平台范围

当前项目明确只做：
- Windows
- Android

不要再为 iOS / macOS / Linux / Web 扩功能。

### 8.2 更新功能现状

设置页关于区域已有更新流程基础版，但仍建议下一阶段复核：
- GitHub API 请求
- 下载进度展示
- Windows 安装器拉起
- Android APK 打开安装
- 错误提示与边界处理

### 8.3 阅读器现状

阅读器已经比最初版本强很多，但还不等同于原版完整阅读器体系。

当前更像：
- 一个显著增强后的简化版

如果后续体检中发现和原版差距导致兼容性问题，要优先补稳定性，不要先追视觉。

### 8.4 打包命令

当前统一打包命令：

```powershell
powershell -ExecutionPolicy Bypass -File D:\venera\EZVenera\scripts\build_release.ps1 -ProjectRoot D:\venera\EZVenera -OutputRoot D:\venera\pack
```

仅打 Windows：

```powershell
powershell -ExecutionPolicy Bypass -File D:\venera\EZVenera\scripts\build_release.ps1 -ProjectRoot D:\venera\EZVenera -OutputRoot D:\venera\pack -SkipAndroid
```

仅打 Android：

```powershell
powershell -ExecutionPolicy Bypass -File D:\venera\EZVenera\scripts\build_release.ps1 -ProjectRoot D:\venera\EZVenera -OutputRoot D:\venera\pack -SkipWindows
```

### 8.5 最近一次已知成功打包

最近成功打包版本：
- `1.2.2+3`

产物路径：
- `D:\venera\pack\EZVenera-1.2.2-windows-setup.exe`
- `D:\venera\pack\EZVenera-1.2.2-android-release.apk`

---

## 9. 推荐的下一阶段执行顺序

建议严格按下面顺序推进：

1. 做全面体检
   - 先出问题清单
   - 先看插件运行时，再看阅读器和图片链路

2. 先修稳定性 / 兼容性问题
   - 不要还没体检完就先写大文档

3. 写“项目结构文档”
   - 面向开发者

4. 写“插件编写文档”
   - 面向插件作者

5. 再做 GitHub Pages HTML
   - 优先把 Markdown 内容打磨清楚
   - HTML 只是展示层

---

## 10. 新会话建议开场方式

新会话建议直接这样说明：

1. 以 `D:\venera\EZVenera\docs\EZVenera_next_phase_handoff.md` 为上下文
2. 当前目标是：
   - 先做稳定性 / 兼容性体检
   - 再写两份中文版文档
   - 最后做 GitHub Pages HTML
3. 先从插件模块对比 `D:\venera\venera` 开始
4. 不对比已移除功能，只对比保留功能

---

## 11. 最后提醒

下一阶段最容易跑偏的地方有两个：

1. 只顾着补原项目功能，忘了“简化版”的边界  
   目标是稳定性和兼容性，不是把删掉的功能全补回来。

2. 文档写成“概念说明”，没有真实路径和真实代码  
   文档必须能真正帮助接手开发者和插件作者。

如果下一阶段只能抓一件事，优先抓：

**插件模块稳定性体检。**

这是当前项目最值得投入的方向，也是最能直接提升整体可靠性的方向。
