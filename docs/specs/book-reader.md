# 图书阅读器设计规范

| | |
|--|--|
| **PRODUCT** | [§4.6](../PRODUCT.md) · [§8 格式矩阵](../PRODUCT.md) |
| **相关** | [reader-chrome.md](./reader-chrome.md)、[library.md](./library.md) |
| **状态** | 规格 + **reflow 已落地**（Kaika controller + Anx Reader foliate-js/WebView） |

## 目标

**正文 EPUB** 的 reflow（文字流式）阅读。与漫画页图引擎在同一 App 内，按 `item.kind` 路由。

## 范围

### 做（v1）

- 导入 EPUB（reflow）：content-hash 去重、封面/标题元数据、`kind=book`。  
- 打开：按 spine **分节** 阅读；移动端提供**滚动 / 翻页**，桌面端仅提供**翻页**；进度写入不透明 locator。
- 阅读默认：字号、行距、边距、阅读背景、阅读模式、翻页效果（`pageTurnEffect`）。
- Chrome：返回、目录（NCX / nav）、书签、排版；打开阅读器时默认隐藏，中间点按显隐。
- 书内超链接：由 Foliate 处理 spine/fragment；外链经 Dart bridge 交系统打开。
- 与 comic 共享：整理三概念、书库壳、桌面 inset（不共享页图引擎）。

### 不做（本阶段）

- 划线笔记、TTS、在线书城。  
- 固定版式双栏 / 全页 `@page` / 复杂 flex-grid 还原（远）。

### EPUB CSS

EPUB 原始 HTML/CSS 由 Anx Reader 的 foliate-js 在系统 WebView 中排版，滚动和翻页共用同一浏览器 CSS 实现。OPF / 章节样式、class、选择器、媒体查询、图片与 `@font-face` 均按包内相对路径解析；用户字号、行距、页边距和阅读主题通过 style bridge 覆盖内容基准。不在 Dart 中维护第二套 CSS 解析器。

### 阅读主题 token（Readium 启发）

阅读主题与 App chrome 独立；token 级取值参考 Readium CSS，**不**整包注入 Readium 样式表。

| 主题 | 背景 | 正文 | 链接 | 标题（略柔于正文） |
|------|------|------|------|-------------------|
| paper | `#FFFFFF` | `#121212` | `#1A0DAB` | `#2A2A2A` |
| sepia | `#FAF4E8` | `#5F4B32` | `#6B5344` | `#4A3A28` |
| dark | `#121212` | `#B0B0B0` | `#63CAFF` | `#CCCCCC` |
| pureBlack | `#000000` | `#FEFEFE` | `#63CAFF` | `#E8E8E8` |

- **正文字体**：Georgia → Charter / Palatino → PingFang SC / Songti SC / Noto Serif SC → `serif`（Latin serif + CJK 系统衬线 fallback）。
- **链接**：使用主题 `linkColor`；脚注上标仍弱化、无下划线。
- **用户字号 / 行距 / 边距**仍覆盖 `body` 基准；主题色覆盖作者 CSS 的正文/链接/标题默认（EPUB class 粗体、缩进等仍生效）。

### 标题默认比例（相对用户字号）

滚动与翻页共用 rendition theme 的默认标题比例；EPUB 作者 CSS 可在非用户强制项上覆盖：

| 标签 | 字号倍率 | 段前 / 段后（× 用户字号） |
|------|----------|---------------------------|
| h1 | 1.75 | 1.4 / 0.9 |
| h2 | 1.45 | 1.2 / 0.75 |
| h3 | 1.25 | 1.0 / 0.6 |
| h4 | 1.15 | 0.8 / 0.5 |
| h5 | 1.10 | 0.7 / 0.45 |
| h6 | 1.05 | 0.6 / 0.4 |

- 字重 **bold**；h1/h2 可选轻微 `letter-spacing`。
- **不**强制居中章节标题——仅当 EPUB / 作者 CSS 已指定 `text-align: center` 时居中。

### 书签（v1）

- 顶部 chrome 可添加/移除当前位置书签，并可打开书签列表。
- 列表显示章节名与节内百分比；点击后按 `BookLocator` 跳转。
- 排版模式或字号变化不改变书签语义；locator 仍以 spine 节 + 节内进度保存。

## 引擎决策

| 方案 | 说明 |
|------|------|
| **当前** | 导入探测、封面/元数据与阅读渲染统一使用 MIT `Anxcye/anx-reader` 的 foliate-js；导入使用不可见 WebView probe，阅读通过 Kaika 的 `flutter_inappwebview` adapter 接回 controller / CFI / TOC。 |
| **演进边界** | 不建设通用“可换引擎”接口；围绕自研管线拆分包解析、内容准备、定位、排版、输入适配与缓存策略。locator 契约继续保持不透明。 |

原则：**DB 不解析 locator**；节索引 + 节内进度分数属 format-owned JSON。包结构解析走库，不手写 OPF/NCX。

### 目录与链接

- 阅读与导入均使用 foliate-js 解析 EPUB3 `nav` / EPUB2 `toc.ncx` 和 spine；不再保留 Dart 侧第二套 EPUB 包解析器。
- 书内相对链接、fragment 和阅读历史由 Foliate rendition 处理，不在 Dart 侧重复解析 HTML。
- 外链经 `onExternalLink` bridge 用系统浏览器 / 邮件客户端打开（仅 `http` / `https` / `mailto`）。

### 脚注

- 复用 Foliate 的 footnote 识别和弹层行为，经 typed bridge 接回 chrome/overlay。
- 弹层样式：`index.html` 提供中性圆角 surface + 半透明遮罩；`book.js` 的 `applyFootnoteTheme()` 按当前阅读主题色设置背景、边框与阴影。
- 不再保留 Dart HTML 预处理器或针对特定出版方 class 的第二套改写规则。

### 模式约定

- **打开时序**：点击后立即显示阅读底色 + 适应窗体的完整封面。Foliate ready 后先扩散消失封面（底下保持阅读底色），再从底色淡入正文。退出为短淡出。locator 与 loopback mount 并行；CFI 在首屏 init 传入。
- **页面上下留白**：Chrome 为覆盖式悬浮层，不永久占用完整操作栏高度；正文只保留系统安全区 + 8dp 阅读留白。Chrome 显隐不得改变分页尺寸或页码。
- **滚动（仅 iOS / iPadOS / Android）**：同一 foliate Paginator 切换为 `flow=scrolled`，位置仍由 CFI 表示；切模式和尺寸变化不销毁 WebView。跨 spine 节仍按 Anx 语义单 iframe 挂载：接近章节边界时预加载相邻节 HTML，新节 iframe 就绪后再替换旧节（避免空白卡顿）；节末上/下滑仍由 `book.js` 触发 `nextPage`/`prevPage` 进入下一节。
- **翻页**：正文交给 Anx foliate Paginator 的 CSS multi-column、方向锁定和 snap；移动端横滑跟手、释放后吸附到相邻页，点按/按钮翻页复用其 200–300ms 动画。Dart 不生成 page list，也不运行 `TextPainter` 章节分页。尺寸/生命周期切换开始时冻结最后一个稳定 CFI，并忽略离屏、零尺寸阶段产生的 relocation；普通尺寸变化保留同一 WebView 并由 ResizeObserver reflow 后回到冻结位置。若 Android 在内外屏切换时报告 renderer process gone，则立即移除失效 WebView，待 App resumed 后用该 CFI 重建一次。
- **翻页效果**（`BookPageTurnEffect`，仅翻页模式）：

  | 值 | 标签 | v1 |
  |----|------|-----|
  | `slide` | 滑动 | **默认值**；Anx Paginator snap 跟手，点按/按钮按距离使用 200–300ms 吸附动画。 |
  | `none` | 无效果 | 调用 rendition `next` / `prev` 直接换页。 |
  | `curl` | 仿真翻页 | **占位**：持久化与设置可选；引擎暂回退为 `slide`。真仿真卷曲另开刀。 |
- **点按**：翻页模式左右约 1/4 翻页、中间显隐 chrome；WebView 内链、表单控件与文字选择优先于空白点按。滚动模式点空白显隐 chrome。
- **平台能力策略**：正文是可直接操纵的阅读画布。macOS / Windows 暂不暴露滚动模式；打开时即使历史偏好为滚动也必须归一到翻页，阅读器与全局设置均不显示滚动选项。移动端两种模式仍共用输入设备策略。

  | 平台 / 输入 | 滚动模式 | 翻页模式 |
  |-------------|----------|----------|
  | iOS / iPadOS / Android：触摸、手写笔 | 纵向拖动，使用平台惯性与边界反馈 | 横向滑动达阈值后翻页；点按左右区翻页 |
  | macOS / Windows：触控板、滚轮 | 不提供 | 触控板横向手势翻页；不把纵向滚轮隐式映射成翻页 |
  | macOS / Windows：鼠标按住拖动 | 不提供 | 横向拖动达阈值后翻页 |
  | 键盘 | 移动端不作为主输入 | 左右键、PageUp / PageDown、Space 翻页 |

  翻页阅读画布须显式允许 `touch`、`mouse`、`stylus`、`trackpad`；鼠标拖动只作用于正文画布，不改变书库与设置列表的系统桌面行为。链接点击和文字选择仍优先，形成拖动后不得触发空白点按。
- **位置 chrome**：foliate-js 不构建全书 Dart pageMap；底栏显示章节序和 CFI/section fraction 换算的全书进度，不伪造受字号/窗口影响的固定总页数。
- **失败恢复**：包解析或 rendition display 失败必须结束 loading 并显示明确错误，不得悄悄保留旧页造成假成功。
- **异步隔离**：每次 WebView attachment 持有 generation lease；renderer 重建、快速退出或 session dispose 后，旧 generation 的 load、relocation、click、console 与 error 回调全部忽略。
- **打开诊断**：debug 日志分段记录 `server-ready → webview-created → renderer-load-end → publication-attached → first-relocation`；renderer 被系统杀死时另记 `renderer-gone → renderer-recovered`，用于区分文件服务、WebView 冷启动、EPUB rendition 与折叠切屏恢复耗时。
- **资源预算**：loopback server 使用 `File.openRead()` 提供 EPUB；foliate-js/zip.js 建立 ZIP 条目索引并只挂载当前章节，章节切换后 unload 旧 section。离开阅读器时关闭 HTTP server 并释放 WebView。
- **嵌入字体**：交由 WebView 按 EPUB 原始 `@font-face` 与相对路径加载，不注册到 Flutter 进程级字体表。
- **排版设置**：滑杆拖动只更新面板预览值，松手后一次性提交 controller、持久化并触发重排。
- 图片：按 OPF 相对路径解析，读取时补 `contentDirectoryPath`（如 `OEBPS/`）。  
- Chrome「页」导航仅在 `readingMode == page` 且 rendition 已绑定外部 next / prev 时启用。

### Chrome 几何

- 顶栏内容高：`kBookReaderChromeBarHeight`（56）。  
- 底栏内容高：`kBookReaderChromeBottomHeight`（padding + IconButton）。  
- 上述尺寸只用于悬浮 Chrome 自身，不参与正文 `pageSize`；正文使用“页面上下留白”中的稳定平台 inset。

## Locator 契约（book）

```json
{
  "sectionIndex": 0,
  "progressInSection": 0.0,
  "cfi": "epubcfi(/6/2!/4/2)",
  "spineVersion": 1
}
```

- `sectionIndex`：spine 线性项下标（仅 `itemref` 顺序）。  
- `progressInSection`：0…1，节内进度。  
- `cfi`：Foliate 原生语义位置；存在时恢复和书签跳转优先使用它。
- `spineVersion`：spine 解析规则变更时递增以作废进度。  

整书 `progress_fraction` ≈ `(sectionIndex + progressInSection) / sectionCount`。

## 导入

- 扩展名：`epub`（`BrandConfig.app.importExtensions`）。  
- 路由：`EpubImportRouter` 自动探测 — 正文 EPUB → book import；页图 EPUB → comic import。正文探测须在 spine 中均匀抽样，并以实际抽样节数计算文本密度；不能只采开头后除以全书节数，避免套装书被插图误判成漫画。
- 存储：与 comic 相同 content-addressed 布局，同一 `library` / `covers` 目录。  
- 提交：源文件先进入同一 support root 下的 `.import-staging`，在临时文件上完成解析和封面；成功后原子移动并写 DB，失败时不得在正式目录留下文件。
- 数据库现有 `pageCount` 字段对 book 暂存 `sectionCount`，UI 不把它显示为受排版影响的真实页数。

## UI

- 全屏阅读；顶栏：返回 / 标题 / 目录 / 书签 / 排版。  
- 底栏：上一页·节 / 进度 / 下一页·节。  
- 桌面：顶栏遵守 `DesktopTitleBarMediaQuery`；mac 左侧让红绿灯。  
- 空态 / 失败：安静中文文案。

## 打开路由

```text
条目 kind=book → BookReaderScreen
条目 kind=comic → ComicReaderScreen
```

书库壳共享；**禁止** book 条目进入 comic 页图 session。

## 验收

1. 导入 reflow EPUB → 书库出现，kind=book。  
2. 移动端滚动与翻页均可阅读；桌面端只能进入翻页；目录 / 书签跳转正确。
3. 移动端触摸 / 手写笔、桌面触控板 / 鼠标拖动均符合上表。
4. 退出再进恢复章节与大致位置。
5. 页图 EPUB 自动进入漫画引擎。
