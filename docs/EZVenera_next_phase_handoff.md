# EZVenera 下一阶段交接文档

更新时间：2026-04-20

本文用于在新对话中快速接手 EZVenera 当前工程状态，继续推进：
- 前端调优
- 设置页面补全

项目路径：
- 本体：`D:\venera\EZVenera`
- 原版参考：`D:\venera\venera`
- 漫画源仓库：`https://github.com/WEP-56/EZvenera-config`

## 1. 当前总体状态

EZVenera 已经完成了“可用的简化版 venera”这一阶段的核心功能：
- 平台范围：Windows、Android
- 导航结构：`Search / Category / Local / Sources / Settings`
- 插件运行时：已兼容 EZvenera-config / venera-config 中保留能力
- 搜索、分类、详情、阅读、下载、本地历史/收藏/下载、漫画源管理、基础设置已可用
- 登录：密码登录、Cookie 登录、WebView 登录均已接入
- 持久化：历史、收藏、下载库、页面状态、登录状态已具备基础持久化

目前重点已经从“功能补全”转向“界面体验”和“接近原版质感”。

## 2. 已完成的关键能力

### 2.1 插件运行时

保留并实现的插件能力：
- `account`
- `search`
- `category`
- `categoryComics`
- `comic.loadInfo`
- `comic.loadEp`
- `comic.onImageLoad`
- `comic.onThumbnailLoad`
- `settings`
- `link`
- `idMatch`

关键文件：
- [plugin_runtime.dart](D:\venera\EZVenera\lib\src\plugin_runtime\plugin_runtime.dart)
- [plugin_runtime_controller.dart](D:\venera\EZVenera\lib\src\plugin_runtime\plugin_runtime_controller.dart)
- [plugin_source_parser.dart](D:\venera\EZVenera\lib\src\plugin_runtime\parser\plugin_source_parser.dart)
- [plugin_js_engine.dart](D:\venera\EZVenera\lib\src\plugin_runtime\engine\plugin_js_engine.dart)
- [models.dart](D:\venera\EZVenera\lib\src\plugin_runtime\models.dart)

### 2.2 登录与登录持久化

已实现：
- 密码登录
- Cookie 登录
- WebView 登录
- 登录状态独立持久化
- 旧 `_localStorage` 登录状态兼容

关键文件：
- [sources_page.dart](D:\venera\EZVenera\lib\src\pages\sources_page.dart)
- [plugin_webview_login_page.dart](D:\venera\EZVenera\lib\src\pages\plugin_webview_login_page.dart)
- [models.dart](D:\venera\EZVenera\lib\src\plugin_runtime\models.dart)

最近修复：
- 不再只靠 `account != null` 判断登录状态
- 新增 `_ez_logged` 持久化标记
- 修复多源场景下 parser 闭包错误绑定 `sourceKey` 的问题，避免串源

### 2.3 搜索 / 分类 / 本地

已实现：
- 搜索源选择、搜索选项、分页、详情跳转
- 分类页、分类漫画页已接入真实业务
- Local 下已有 `History / Favorites / Downloads`
- 页面切换状态保留和基础持久化已接入

关键文件：
- [search_page.dart](D:\venera\EZVenera\lib\src\pages\search_page.dart)
- [categories_page.dart](D:\venera\EZVenera\lib\src\pages\categories_page.dart)
- [category_comics_page.dart](D:\venera\EZVenera\lib\src\pages\category_comics_page.dart)
- [local_page.dart](D:\venera\EZVenera\lib\src\pages\local_page.dart)
- [app_state_controller.dart](D:\venera\EZVenera\lib\src\state\app_state_controller.dart)

### 2.4 阅读器

已实现：
- 基础章节阅读
- 键盘、滚轮、左右区域翻页
- 历史恢复
- 章节切换
- 章节前后页跳转
- 控制层基础显隐
- 图片缓存、磁盘缓存、预加载、`precacheImage`

关键文件：
- [reader_page.dart](D:\venera\EZVenera\lib\src\pages\reader_page.dart)
- [reader_image_cache.dart](D:\venera\EZVenera\lib\src\reader\reader_image_cache.dart)

注意：
- 阅读器现在已经明显优于最初简化版，但离原版 `reader.dart + scaffold.dart + images.dart` 体系还有距离
- 下一阶段仍应继续向原版结构靠拢

### 2.5 Windows 构建

已修复：
- `flutter_inappwebview_windows` 构建依赖 `nuget` 的问题
- 项目内会自动 bootstrap 本地 `nuget.exe`

关键文件：
- [windows/CMakeLists.txt](D:\venera\EZVenera\windows\CMakeLists.txt)

## 3. 当前已经确认的体验问题

### 3.1 还未完成的 UI/体验类目标

用户已明确要求下一阶段重点做：
1. Windows 自定义顶部边框
2. 更像原版的左侧侧边栏
3. 搜索 / 分类结果改为带封面的瀑布流卡片
4. 引入更多原版风格的动效
5. 设置页面逐步复用原版结构

### 3.2 已处理但建议复测

- 源管理页展开时报的 Windows accessibility 警告
  - 已将 `ExpansionTile` 改为自定义折叠卡片
  - 需复测是否还会出现：
    - `[ERROR:flutter/shell/platform/windows/accessibility_plugin.cc(73)] Announce message 'viewId' property must be a FlutterViewId.`

- 登录状态持久化
  - 已修
  - 需复测密码登录、Cookie 登录、WebView 登录三类源

## 4. 下一阶段工作目标

## 4.1 前端调优

### A. Windows 自定义顶部栏

目标：
- 仅 Windows 使用自定义顶部栏
- 显示：
  - 标题：`EZVenera`
  - 最小化
  - 最大化 / 还原
  - 关闭
- 删掉当前左侧栏内部那块大标题和说明文案：
  - `EZVenera`
  - `Windows and Android only. Plugin-first architecture.`

当前相关文件：
- [main_shell.dart](D:\venera\EZVenera\lib\src\shell\main_shell.dart)
- [app.dart](D:\venera\EZVenera\lib\src\app.dart)

原版参考建议：
- 原版有自己的窗口框架能力，可参考：
  - [reader.dart](D:\venera\venera\lib\pages\reader\reader.dart)
  - 以及原版工程内窗口相关实现

建议做法：
- Windows 下在 `Scaffold` 外层或顶部加入自定义 title bar 容器
- Android 保持现状
- 注意拖动区域、双击最大化、按钮 hover/pressed 状态

### B. 侧边栏重构

目标：
- 更接近图 1
- 两个分区：
  - 上部：`Search / Category / Local / Sources`
  - 下部：`Settings`
- 宽度适中，不要太宽
- 去掉当前侧栏上方说明区

当前相关文件：
- [main_shell.dart](D:\venera\EZVenera\lib\src\shell\main_shell.dart)
- [app_destination.dart](D:\venera\EZVenera\lib\src\navigation\app_destination.dart)

建议做法：
- 不再直接依赖 `NavigationRail` 的默认布局
- 改为自绘侧边栏组件
- 保留 `IndexedStack` 的页面保活逻辑

### C. 窗口最小尺寸与布局切换

目标：
- Windows 窗口有最小尺寸限制
- 缩小到某阈值时自动切换到移动端布局
- 行为类似原版

当前相关文件：
- [main_shell.dart](D:\venera\EZVenera\lib\src\shell\main_shell.dart)
- Windows runner 相关：
  - [main.cpp](D:\venera\EZVenera\windows\runner\main.cpp)
  - runner 目录其他窗口文件

建议做法：
- 布局切换不要只依赖平台，要加宽度阈值判断
- 例如：
  - Windows 宽度较大：桌面侧栏布局
  - Windows 宽度较小：顶部栏 + 底部导航移动布局
- 最小宽高限制在 runner 层做

### D. 搜索 / 分类结果卡片化

目标：
- 搜索结果、分类结果改为瀑布流 / 卡片流
- 必须有封面
- 卡片上至少显示：
  - 封面
  - 标题
  - 副标题
  - 标签或语言/来源信息

当前相关文件：
- [search_page.dart](D:\venera\EZVenera\lib\src\pages\search_page.dart)
- [category_comics_page.dart](D:\venera\EZVenera\lib\src\pages\category_comics_page.dart)

建议做法：
- 为 Windows 和 Android 做自适应列数
- 不要继续用单纯 `ListTile`
- 可以增加：
  - 懒加载封面
  - 占位图
  - Hover 态 / 点击缩放 / Hero 动画

原版参考：
- 分类和搜索结果页表现
- 用户给的图 4 作为目标风格

### E. 动效补强

目标：
- 不做“通用 Flutter demo 动效”
- 要更接近原版那种轻巧、克制、有效的动效

优先补的动效：
- 页面切换淡入 / 滑入
- 卡片 staggered reveal
- 搜索结果加载完成时的渐入
- 侧边栏选中态过渡
- 阅读器控制层滑入滑出
- Sources 卡片展开收起动画细化

建议先查原版：
- [scaffold.dart](D:\venera\venera\lib\pages\reader\scaffold.dart)
- 其他页面中的 AnimatedPositioned / AnimatedContainer / blur / overlay 用法

## 4.2 设置页面补全

目标：
- 慢慢复用原版，不要求一口气做完
- 优先补“结构”和“分组”，再补具体项

当前文件：
- [settings_page.dart](D:\venera\EZVenera\lib\src\pages\settings_page.dart)
- [settings_controller.dart](D:\venera\EZVenera\lib\src\settings\settings_controller.dart)

当前已有：
- 主题模式
- 漫画源索引 URL

建议下一批优先补：
1. 阅读器设置
2. 网络设置
3. 下载设置
4. 外观设置
5. 关于 / 调试信息

原版参考：
- 原版 settings 页面及其分组结构

## 5. 推荐的下一阶段实施顺序

建议严格按这个顺序做，避免 UI 改来改去：

1. `MainShell` 重构
   - 自定义 title bar
   - 自定义侧边栏
   - 小窗口切移动布局

2. 结果页视觉重构
   - Search 瀑布流卡片
   - CategoryComics 瀑布流卡片

3. 动效补强
   - 主导航
   - 卡片
   - 页面切换

4. Settings 页面结构升级
   - 分组先做
   - 项目逐步迁移

5. 阅读器第二轮 UI 靠拢
   - 更完整的控制面板
   - 更像原版的顶部/底部结构
   - 阅读设置入口

## 6. 关键技术约束

- 不要脱离原版项目太远
- UI 可以简化，但结构和交互风格要尽量继承原版
- 插件能力范围不要再扩大，维持当前精简集合
- 默认漫画源索引必须继续使用 EZvenera-config，不回退到原版源仓库

## 7. 近期重要修复记录

以下是本轮会话中已经做过、接手时不应重复返工的内容：

- 搜索链路已打通
- 分类 / 分类漫画页已接业务
- 阅读器已支持基础翻页、章节切换、历史恢复
- 阅读器新增图片缓存 / 磁盘缓存 / 预取
- 本地历史 / 收藏 / 下载已可用
- 页面状态持久化已做基础版本
- 登录状态持久化已修
- WebView 登录已接入
- `flutter_inappwebview_windows` 的 NuGet 构建问题已修
- Sources 页展开控件已替换为自定义折叠卡片

## 8. 新对话接手时建议直接说明的内容

建议新对话开场直接说明：
- 继续做前端调优和设置页补全
- 以 [EZVenera_next_phase_handoff.md](D:\venera\EZVenera\docs\EZVenera_next_phase_handoff.md) 为上下文
- 第一阶段先重构 `MainShell`
- 保持接近原版 venera，不做大幅脱离原项目风格的 UI

## 9. 交接时的代码状态

截至本文写入时：
- 工程可正常 `analyze`
- 工程可正常 `test`
- 当前工作区无待说明的异常状态

