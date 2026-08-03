---
version: "0.1.1"
name: kaijuan
description: "Kaijuan (开卷) — one quiet-study app with book and comic reading engines. No solid background bars, covers are the protagonists; reading content rendering is independent, chrome recedes into glass. Brand-layer rules live in kai-brand-design; this file is the product overlay."
colors:
  accent: "#EA580C"
  accentPresets: ["#EA580C", "#0177B5", "#047857", "#BE123C", "#475569"]
  # 单值模型：hover/pressed 由通用 stateLayer 前景叠加表达，不设独立 accent hover 色
  # 中性色/玻璃/文字三档全部继承品牌层皮肤 token
typography:
  # 壳层继承品牌层（w800 封顶、负字距三档、0.5 字号网格）
  # 阅读内容排版（书页字体栈、字号）属内容层，本文件与品牌层均不约束
rounded:
  cover: 12
  # 继承品牌层 control 10 / menu 12 / card 14 / sheet 18 / dialog 20
components:
  prefix: "App*"
  readerChrome: { barHeight: 56, trafficLightInset: 78, sliderTrack: 3, sliderThumbRadius: 6 }
  compatibilityEntrypoints: ["main_book.dart", "main_comic.dart"]
---

# Kaijuan (开卷) Design

## Overview

安静书房：无纯色背景条、封面是主角、内容（书页/漫画）至上。阅读内容渲染完全独立；chrome 克制地退到玻璃浮面里。

**Key Characteristics:**

- **事实源**：[`kai-brand-design`](https://github.com/robeshell/kai-brand-design) 品牌层 + `products/kaijuan/`。改设计先改规范仓库，再回本仓库落地；实现侧细节另见 `docs/DESIGN_FOUNDATION.md`。
- **组件前缀 `App*`**：`brand_tokens.g.dart` 由品牌 JSON 生成；主题层 `lib/core/theme/` 提供兼容语义 API，组件 kit 位于 `lib/presentation/widgets/app_components.dart`。
- **单 App 双引擎**：`main.dart` 是唯一产品入口；`main_book.dart` / `main_comic.dart` 仅为兼容重定向。漫画与图书共享主题路径，任何主题/组件改动必须覆盖两类内容。

## Typography migration status

Kaijuan 壳层字号已按 Kaiting 的迁移规则收敛到两层 token：通用层使用生成的 `KaiBrandMobileType` / `KaiBrandDesktopType`，产品特例使用 `KaiProductTokens`。业务 UI 不直接承载数字型 `fontSize`；新增字号先判断已有 `context.app*Size`，只有开卷特有的 chrome 角色才进入产品 token。

图书正文是独立的内容层：字号、行高、字距、段间距和字体栈由 `BookReadingPreferences` 与阅读器渲染链路提供，默认值与可调范围是功能参数，不迁入品牌或产品 chrome token。漫画内容为图像，不定义正文 `fontSize`。主题、组件和阅读器 chrome 的改动必须同时覆盖图书与漫画两类引擎。


### Accent（产品轴：ember 暖橙）

- **accent** `#EA580C`；预设：晴空 `#0177B5` / 松绿 `#047857` / 绯红 `#BE123C` / 岩灰 `#475569`。
- **单值模型**：hover/pressed 由通用 stateLayer 叠加（hover foreground@0.055–0.065、pressed @0.10、focused accent@0.16），不设独立 accent hover 色。
- 只用于选中/进度/主操作；阅读内容内的高亮色板属内容层，不受此约束。

### Text & States

- 文字三档 context getter（`appPrimaryText / appSecondaryText / appMutedText`）；禁用 `appDisabledForegroundOpacity`（secondary@0.55）；chrome 用 `appChromeSurface`；onAccent 用 accent preset 登记值；hairline 直接用于分隔。
- 状态色：错误 `colorScheme.error`；警告用品牌层 `derivedAlphas.status.warning`。

### Content Layer（阅读主题）

- paper / sepia / dark / pureBlack 色板 + 阅读字体栈是 L0 扩展点，**不是设计规范的约束对象**；chrome 取色来源按页登记（书籍 chrome 取自阅读色板且不透明——已登记分叉；漫画走皮肤 glass）。

## Typography

- 壳层继承品牌层：w800 封顶（禁 w900）、负字距三档（−0.8/−0.55/−0.25）、正文/行文字不加字距、0.5 字号网格。
- 阅读内容排版（书页字号、行距、字体栈）不受本文件约束；`book_theme_test.dart` 与 `book_typography_baseline_test.dart` 是内容层回归底线，必须原样通过。

## Layout

- 桌面壳：medium 216 / wide 236 侧栏 + 内容；移动壳：底栏 + 内容延伸玻璃下。窗口分级与壳切换继承品牌层，产品不自造断点。
- 桌面主窗默认 1280×800、最小 1024×700（逻辑/content 像素），与品牌 0.2.8 和其它产品一致。
- 阅读器 chrome：栏高 56；macOS 红绿灯避让 78。

## Elevation & Depth

- 浮面 `AppGlassSurface`：strongSurface + hairline + token 阴影 ×shadowScale +（可选）模糊；blur=0 皮肤自动跳过 BackdropFilter。
- 重复行/卡片不模糊；封面阴影仅 ≥96px 启用；多选操作条 strong 玻璃 + 顶 r18。

## Shapes

- 通用 UI 继承品牌圆角阶梯：control 10 / menu 12 / card 14 / sheet 18 / dialog 20 / pill 999；窄幅书籍 / 漫画封面使用产品 token r12；对话框 maxWidth 520，弹层 760（选项列表 560）。

## Components

- **阅读器工具条**：分段选项用 `AppChoiceStrip` 视觉语言；步进钮 token 色胶囊；进度滑杆轨 3、thumb r6。
- **目录抽屉 / 搜索面板**：strong 玻璃面；**长按选择菜单**：样式 chip 走 ChoiceOption 视觉，高亮圆点保留内容层色板。
- **摘抄卡片 / 书签弹层 / 漫画缩略图**：`showAppBottomSheet` + `AppListRow`。
- 通用组件（AppListRow / AppCheckRow / AppChoiceStrip / AppMenuButton / AppEmptyState / AppNavigationBar / showAppSnackBar / AppSettings*）锚点继承品牌层。
- **禁项**：裸 `PopupMenuButton`（用 `AppMenuButton`）、`Switch.adaptive`、Material elevation。

## Do's and Don'ts

### Do

- chrome 组件优先用 kit；新增通用组件回提品牌层。阅读器与书架模式见规范仓库 `products/kaijuan/patterns/`。
- 主题改动后漫画与图书两类内容各跑一遍；皮肤 × 全部强调色巡检。

### Don't

- 不为 chrome 样式改动触碰 `lib/readers/**`、翻页机制、图像渲染、阅读色板和内容排版边界。
- 不在 chrome 里硬编码颜色/圆角/alpha；不给展示文字染 accent。
- 不让窗口临时变矮把桌面壳退化成手机导航（品牌层规则）。

## Responsive Behavior

- 继承品牌窗口分级与 sheet↔popover 自适应（<680 落底部弹层）。
- 阅读器 chrome 在 compact/wide 间保持栏高与避让不变，只调整工具条分段密度。

## Iteration Guide

1. 样式改动先判归属：通用 → kai-brand-design 品牌层；开卷特有 → `products/kaijuan/`；然后再改代码。
2. 阅读器与书架模式以规范仓库 `products/kaijuan/patterns/reader.md`、`bookshelf.md` 为准；实现出现新模式时先更新产品规范。
3. 已知分叉统一登记在规范仓库 `products/kaijuan/divergences.md`，不得只留在代码注释或本文件。

## Known Gaps

- 书架网格 hover 的动效参数仍待定档。
- 主题持久化迁移（旧 themeMode → 皮肤 id）规则在代码内，未进规范。

## Agent Prompt Guide

- 改 UI 前读本文件 + kai-brand-design `DESIGN.md`；数值以 kai-brand-design `tokens/*.json` 为准。
- 快速定位：生成 token `lib/core/theme/brand_tokens.g.dart`（禁止手改）；主题 `lib/core/theme/`；组件 kit `lib/presentation/widgets/app_components.dart`；阅读器 chrome `lib/presentation/widgets/reader/`。
- 验收：`flutter analyze` 零告警；`flutter test` 全绿（尤其 `book_theme_test.dart`、`book_typography_baseline_test.dart`）；漫画与图书入口均可启动。
