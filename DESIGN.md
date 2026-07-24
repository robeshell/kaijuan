# DESIGN.md — 开卷（kaijuan）

> AI 代理入口：本文件给出开卷的视觉要点。**事实源**：[`kai-brand-design`](https://github.com/robeshell/kai-brand-design) 品牌层（通用 token/组件/模式）+ `products/kaijuan/`（本产品规范）。改设计先改规范仓库，再回本仓库落地。实现侧细节另见 `docs/DESIGN_FOUNDATION.md`。

## 视觉主题

安静书房：无纯色背景条、封面是主角、内容（书页/漫画）至上。阅读内容渲染完全独立，chrome 克制地退到玻璃浮面里。

## L0（产品轴）

- **强调色**：ember 暖橙 `#EA580C`，5 预设（晴空 `#0284C7` / 松绿 `#047857` / 绯红 `#BE123C` / 岩灰 `#475569`）；单值模型——hover/pressed 由通用 stateLayer 前景叠加表达，不设独立 accent hover 色。
- **组件前缀**：`App*`；主题层 `lib/core/theme/`（tokens/glass/skins/app_theme/context），组件 kit `lib/presentation/widgets/app_components.dart`，设置 kit `widgets/settings_components.dart`。
- **内容层扩展点**：阅读主题（paper/sepia/dark/pureBlack 色板 + 阅读字体栈）——阅读内容排版不是设计规范的约束对象；chrome（工具条/抽屉/菜单）的取色来源按页登记。
- **皮肤**：跟随系统（伪皮肤，按平台亮度解析）/ 默认 / 纯净 / 深夜，与品牌层一致。

## 关键落地（与品牌层锚点一致）

- 圆角 control 10 / menu 12 / card 14（封面同）/ sheet 18 / dialog 20 / pill 999；对话框 520；弹层 760（选项列表 560）。
- 文字三档 context getter（`appPrimaryText / appSecondaryText / appMutedText`）；禁用 secondary@0.38；hairline 直接用于分隔。
- 排版 w800 封顶（禁 w900）；大标题负字距（−0.8/−0.55/−0.25 三档）；正文/行文字不加字距。
- 浮面 `AppGlassSurface`（strong + hairline + token 阴影 ×shadowScale，blur=0 皮肤自动免模糊）；重复行/卡片不模糊。
- 菜单 `AppMenuButton`（窄屏底部弹层 / 宽屏 252px 锚定）；选择 `AppChoiceStrip`；空态 `AppEmptyState`；提示 `showAppSnackBar`；设置分组卡 r14 + hairline + 缩进 14 分隔。

## 阅读器 chrome（模式规范待提炼至 `products/kaijuan/patterns/reader.md`）

- 栏高 56；macOS 红绿灯避让 78；书籍 chrome 取色自阅读色板且不透明（内容层分叉，已登记），漫画走皮肤 glass。
- 进度滑杆：轨 3、thumb r6；分段选项用 ChoiceStrip 视觉语言。

## Do's and Don'ts

- ❌ 不动 `lib/readers/**`、翻页机制、阅读色板、内容排版边界；不在 chrome 里硬编码颜色/圆角/alpha。
- ❌ 双 flavor（`main_book.dart` / `main_comic.dart`）共享主题路径——改动必须两端可编译可运行。
- ✅ chrome 组件优先用 kit；新增的通用组件回提品牌层，阅读器特有模式登记 `products/kaijuan/patterns/`。
