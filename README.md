<p align="center">
  <img src="assets/ico.png" alt="Logo" width="180" />
</p>


# EZVenera

EZVenera 是一个面向 Windows / Android 的 Venera 简化分支，目标是把结构收紧、功能简化、实现做实，以持续维护。
### 为什么制作EZVenera
- 在Apr 5 2026，我发现venera在使用时，有一些漫画源无法使用，于是前往venera主仓库查看issues，沉痛的发现venera被设置为了 archived。但venera已经是我必不可少的漫画软件了。于是我决定接手制作。为了避免无法持续维护，我决定重构它，并缩紧功能。这个项目我将持续维护直到不再有任何漫画阅读需求。感谢原项目各位开发者长久以来的开源贡献！

## 当前状态

目前已经完成的主要内容：

- 全新的 EZVenera 应用壳层
- readme提到的的所有功能，都已稳定可用
- 对原版项目插件的全量兼容（但不包含收紧的功能）
- 应用程序内的GitHub Release 更新检测与下载
- GitHub Pages 文档站基础版，具备详细的EZVenera版本插件编写指南

核心运行时代码：

- `lib/src/plugin_runtime`

## 文档

当前仓库内已经有这些中文文档，但大多是给LLM看的，建议您查看下方的page页面：

- `docs/EZVenera_execution_plan.md`
- `docs/EZVenera_next_phase_handoff.md`
- `docs/EZVenera_plugin_runtime_design.md`
- `docs/EZVenera_plugin_doc.md`
- `docs/health_check_report.md`
- `docs/plugin_compatibility_checklist.md`

GitHub Pages 静态页面入口：

- 导航页：`docs/site/index.html`
- 插件编写页：`docs/site/plugin-guide.html`
- 项目结构页（用于接手开发，当前未编写）：`docs/site/project-structure.html`

## 插件仓库

EZVenera 的插件源建议使用：

- [EZvenera-config](https://github.com/WEP-56/EZvenera-config)

不要直接把原版 Venera 默认源仓库当作 EZVenera 的官方默认源来使用。

## 本地开发

安装依赖并运行：

```bash
flutter pub get
flutter run
```

常用检查：

```bash
flutter analyze
flutter test
```

## 仓库与发布

项目主页：

- [WEP-56/EZVenera](https://github.com/WEP-56/EZVenera)

发布页：

- [Releases](https://github.com/WEP-56/EZVenera/releases)

## 感谢社区

- [linux.do](https://linux.do/)

## Star History

<a href="https://www.star-history.com/?repos=WEP-56%2FEZVenera&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=WEP-56/EZVenera&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=WEP-56/EZVenera&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=WEP-56/EZVenera&type=date&legend=top-left" />
 </picture>
</a>

## 交流Q群
[![QQ群](https://img.shields.io/badge/QQ群-1085492350-12B7F5?logo=tencentqq&logoColor=white)](https://qm.qq.com/q/1085492350)