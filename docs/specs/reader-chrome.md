# 阅读器 Chrome 设计规范

| | |
|--|--|
| **PRODUCT** | [§4.6](../PRODUCT.md) |
| **视觉** | [DESIGN_FOUNDATION.md](../DESIGN_FOUNDATION.md) |

## 目标

- **漫画引擎**：页图 chrome（模式 / 方向 / 页进度）。
- **图书引擎**：reflow chrome（目录 / 字号等，另见 book-reader spec）。
- **可共享**：玻璃顶底栏、显隐节奏、错误态语言；皮肤跟 **品牌 + 阅读主题**。

## 原则

内容即界面；chrome 默认可隐藏；引擎分叉、壳组件尽量复用。

## 阅读主题默认

| 产品 | 默认内容背景 |
|------|----------------|
| comic | 深灰 `#1C1C1E` |
| book | 纸白等（book spec） |

## 布局与材质

- 顶栏 h56；图书底栏为**进度条 + 五键工具条**（目录 / 听书 / 亮度 / 字体排版 / 阅读模式），点键在上方展开面板；控件用设计 token（`AppSpacing` / `AppRadii` / 强调色），不用 Material 默认 `Slider` / `SegmentedButton`。
- **图书**：点按区做在正文手势层内（非 Stack 盖层），避免抢脚注/内链：翻页模式左右约 25% 翻页、中间显隐 chrome；滚动模式点空白显隐 chrome。进度条 seek 用全书 `progressFraction`（Foliate loc），松手定位。
- **图书跨端输入**：移动端以触摸 / 手写笔直接操纵正文；桌面端同时支持触控板、滚轮和鼠标按住拖动。输入设备集合由图书阅读器统一策略提供，滚动 / 翻页视图不得各自分叉。正文链接与脚注点击优先于空白点按，拖动不触发 chrome 显隐。
- **漫画**：中央单击显隐（页图引擎可保留）。
- glassFill + 克制模糊；跟随阅读主题深浅。  
- 交互节奏同前（200ms、拖动松手 seek、桌面键位）。  
- **桌面**：阅读器全窗覆盖壳层标题栏时，顶 chrome 须 `platformTitleBarHeight` 下沉；macOS 额外左侧让开红绿灯（~78）。
- 工具条大改计划与分刀见 [book-reader-tool-strip-plan.md](./book-reader-tool-strip-plan.md)。

## 书签 v1

- 两种阅读器都可在 chrome 中添加或移除**当前位置**书签。
- 书签列表按阅读位置排序，显示“第 N 页”或“章节 + 百分比”，点击跳转。
- 同一格式 locator 指向同一位置时只保留一条；删除条目时由数据库级联删除书签。
- v1 不编辑标签、不承载划线或笔记；数据库继续把 locator JSON 当作不透明载荷。
