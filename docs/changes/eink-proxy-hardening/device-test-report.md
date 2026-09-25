# 真机测试回执 — eink-proxy-hardening（自动化预填版）

> 测试执行：2026-09-25 08:04–08:50，通过 adb 自动化在本机完成可自动化项；
> 截图存档于本机 `/tmp/ezv_*.png`、`/tmp/t4_*.png`。标注【待人工】的项
> 需要真机肉眼确认（E-Ink 观感）或外部信息（代理端日志、WebDAV 账号）。

## 环境信息

- 设备型号：Likebook T80D（博阅，Rockchip）
- 屏幕类型：E-Ink 7.8"（无背光黑白）
- Android 版本：8.1.0（API 27, arm64-v8a）
- 测试构建：devtest 共存包 `com.ezvenera.ezvenera.devtest`（1.8.7+17，
  含 eink-proxy-hardening 全部改动 + JsonFileStore 并发修复）
- 代理环境：192.168.2.153:16492（局域网 HTTP 代理）

## 测试结果

| # | 结果 | 现象描述 | 证据 |
|---|---|---|---|
| T0 | PASS | 应用启动正常；设置页「网络」入口存在，副标题随代理状态实时联动（跟随系统→URL→已关闭） | 截图 `ezv_settings2.png` |
| T1 | PASS | 自定义代理下：copy_manga 图源安装成功、搜索"黑暗"返回结果、全部封面加载成功、漫画可正常阅读（多页翻页） | 截图 `ezv_where.png`、阅读页截图 |
| T2 | 【待人工】 | 代理端连接日志需在 192.168.2.153 上查看（代理软件为 clash/v2ray 时看连接面板） | — |
| T3 | PASS(弱对照) | 直连档下 `GET https://api.copy-manga.com/...` 失败（应用日志 WARNING）；系统浏览器（无代理）访问 github.com 报 `net::ERR_CONNECTION_CLOSED`。注：`api.github.com` 在该网络直连**间歇可达**，对照力度受限 | 应用日志 08:44 行；浏览器报错截图 |
| T4 | PASS | 代理改为错误端口 `http://192.168.2.153:1` 后（**不重启**），检查更新请求失败并被日志记录；恢复正确地址后恢复。SnackBar 明示「代理已保存，立即生效。」——配置热更新闭环 | 应用日志 08:47:58 行 `[network] GET https://api.github.com/repo...`（failed）；SnackBar 截图 `t4_step2.png` |
| T5 | SKIP | 设备未配置 WebDAV 账号 | — |
| T6 | PASS | 自定义代理下「检查更新」→ 弹窗「当前已经是最新版本。」= `GET https://api.github.com/repos/WEP-56/EZvenera/releases/latest` 经代理成功 | 截图 `ezv_update_check.png` |
| T7 | SKIP | 未使用认证代理（UI 提示与凭据剥离逻辑已有单测覆盖） | — |
| E0 | PASS | 设置 → 外观出现「E-Ink 模式」区块（总开关 + 高对比度 + 切章刷新） | 截图 `ezv_settings_bottom.png` |
| E1 | PASS | E-Ink 模式开启后：全部界面呈纯黑白高对比（搜索/设置/关于/日志页截图均为纯白底黑字，无米色/灰阶/色彩） | 截图 `t4_nav2.png` 等 |
| E2 | 部分【待人工】| 阅读器功能正常（真实漫画多页阅读）；翻页"完全无动画过渡"的观感需真机肉眼确认 | 阅读页截图 |
| E3 | 部分【待人工】| 切章闪烁遮罩已实现（220ms 纯色全屏），观感与是否触发固件全刷需肉眼确认 | — |
| E4 | 未测 | 关闭 E-Ink 恢复原主题（单测已覆盖主题切换逻辑） | — |

## 应用日志摘录（应用内日志页实拍）

```text
2026-09-25T08:28:46.558348 [ERROR] Platform error
PathNotFoundException: Cannot rename file to '/data/user/0/com.ezvenera.ezvene...
#2  JsonFileStore.write (package:ezvenera/src/utils/json_file_store.dart)
#3  AppStateController._persist
  → 旧版并发写 bug（详见 commit 368d279 修复），修复后未再出现

2026-09-25T08:41:54.337937 [WARNING] [network] GET https://www.copy20.com/sear...
2026-09-25T08:44:00.513970 [WARNING] [network] GET https://api.copy-manga.com/...
2026-09-25T08:47:58.158987 [WARNING] [network] GET https://api.github.com/repo...
  → 三条均为直连/错误代理档下的失败请求记录（结构化网络日志 REQ-012 生效）
```

## 追加：本地索引安装（REQ-014，真机验证）

| 项 | 结果 | 证据 |
|---|---|---|
| 按钮 | PASS | 图源管理页出现「本地索引安装」按钮（安装 / 图源列表 / 本地安装 / 本地索引安装 / 重新加载） |
| 选择器 | PASS | 点击后系统文件选择器正常拉起（截图 `ezv_local_index_picker.png`） |
| 解析/路径判定 | PASS（单测 9 例）| 上游 index.json 格式、filename 别名、坏行跳过、同目录 .js 存在性判定 |
| 完整离线安装 | 【待人工】| 使用方式：把 `index.json` 和图源 `.js` 放到设备同一文件夹 → 本地索引安装 → 选 index.json → 多选安装 |

## 测试中发现的缺陷及处置

| 缺陷 | 严重度 | 处置 |
|---|---|---|
| `JsonFileStore.write` 并发写共享 `.tmp` 导致 `PathNotFoundException`（tab 切换高频持久化时触发） | 高（丢写 + 报错，不崩溃） | **已修复**（commit 368d279：唯一临时文件名 + 写队列串行化），新增 20 并发回归测试，修复版已重装真机复测无复发 |

## 残留事项

1. T2（代理端观察）与 E2/E3（E-Ink 观感）待人工补充。
2. 设备网络出口对 `api.github.com` 间歇可达、对 `github.com` 直连不可达——
   网络环境相关，不影响功能结论，但代理设置对该设备是刚需。
