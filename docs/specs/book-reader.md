# 图书阅读器设计规范

| | |
|--|--|
| **PRODUCT** | [§4.6](../PRODUCT.md) · [§8 格式矩阵](../PRODUCT.md) |
| **相关** | [reader-chrome.md](./reader-chrome.md)、[library.md](./library.md) |
| **状态** | 规格 + **reflow 已落地**（`flutter_html` 滚动 + 真分页；可替换引擎） |

## 目标

**正文 EPUB** 的 reflow（文字流式）阅读。与漫画页图引擎在同一 App 内，按 `item.kind` 路由。

## 范围

### 做（v1）

- 导入 EPUB（reflow）：content-hash 去重、封面/标题元数据、`kind=book`。  
- 打开：按 spine **分节** 阅读；**滚动 / 翻页** 两模式；进度写入不透明 locator。  
- 阅读默认：字号、行距、边距、阅读背景、阅读模式。  
- Chrome：返回、目录（NCX / nav）、书签、排版；可隐藏。  
- 书内超链接：跳转到目标 spine 节；`#fragment` 按 HTML 内 id 位置估算节内进度。  
- 与 comic 共享：整理三概念、书库壳、桌面 inset（不共享页图引擎）。

### 不做（本阶段）

- 划线笔记、TTS、在线书城。  
- 固定版式双栏 / 全页 `@page` / 复杂 flex-grid 还原（远）。

### EPUB CSS（v1 子集）

OPF manifest 中的 CSS 经 `BookEpubSession.stylesheets()` 懒加载一次；各 spine 节 `<link rel="stylesheet">` 按需读取。预处理管线把 CSS 文本挂到 `PreparedSection`，**不**把包级 CSS 复制进每一节的 `html` 字符串（大书内存）。

| 能力 | 滚动（flutter_html） | 翻页（HtmlBlockParser） |
|------|----------------------|-------------------------|
| OPF manifest CSS | `<style>` 注入节首；flutter_html 解析 | 简易规则表：class / 标签选择器 |
| 节内 `<link>` CSS | 同上（节级 `<style>`） | 同上 |
| `font-weight` / `font-style` / 下划线 / 删除线 | 是 | 是（含 `.class`） |
| `text-indent` / 段前后距（可解析数值） | 尽力 | 段首缩进 |
| 标题 `h1`–`h6` 相对字号 | 是 | 是（CSS 可覆盖默认倍率） |
| 用户字号 / 行距 / 主题色 | **覆盖**正文 `body` 基准 | **覆盖**测量基准 |
| `@font-face` / 嵌入字体 | v1 跟进（Phase 4） | 同左 |
| 媒体查询、`!important`、伪类、继承链 | 否 | 否 |

**原则**：优先阅读流畅度；Calibre / 余华类书靠 class 粗体、首行缩进、章节标题即可。翻页不建完整 CSS 引擎，未识别声明静默忽略。

### 书签（v1）

- 顶部 chrome 可添加/移除当前位置书签，并可打开书签列表。
- 列表显示章节名与节内百分比；点击后按 `BookLocator` 跳转。
- 排版模式或字号变化不改变书签语义；locator 仍以 spine 节 + 节内进度保存。

## 引擎决策

| 方案 | 说明 |
|------|------|
| **当前** | 结构：`epub_pro` **懒加载**（`openBook` / 按需读 HTML·图片）→ `BookEpubSession`；渲染：HTML 预处理 → `flutter_html`（滚动）/ `HtmlBlockParser`+`Paginator`（翻页，大书窗口分页） |
| 后续可替换 | 嵌入 WebView 等；locator 契约保持不透明 |

原则：**DB 不解析 locator**；节索引 + 节内进度分数属 format-owned JSON。包结构解析走库，不手写 OPF/NCX。

### 目录与链接

- 目录来自 `epub_pro` 的 chapters（EPUB3 `nav` / EPUB2 `toc.ncx`），映射到 spine 节；不再用各节 `<title>`（套装书常全书同名）。  
- 书内相对链接：按当前节 `baseHref` 解析 spine 节 + 可选 `#fragment`；跳转前须 `ensureSectionPrepared` 再算节内进度。  
- 外链（`http`/`https`/`mailto`/`www.`）：系统默认方式打开；失败时 Snackbar 提示「无法打开链接」。

### 脚注（v1）

- 识别：`epub:type=noteref` / `footnote`，以及中文站常见 `zy-footnote`、`.epub-footnote`、`.duokan-footnote-*`。  
- 点击脚注标记 → 弹出说明气泡（可滚动）；**不**跳转到 aside。  
- 正文不展示脚注 `aside` 块；图标角标在预处理时改写成可点上标（`※`），避免翻页模式把脚注图当成整页大图。

### 模式约定

- **滚动**：按**已测章节高度**映射 offset ↔ `BookLocator`；节 HTML **按需加载**；pending jump 失败须重试直至 layout 就绪。  
- **翻页**：渐进分页；大书（spine > 80）只排当前节窗口，页末可跨到下一节再排。未排到的节不可用 pageMap clamp 跳转，应保留 pending。  
- **大书页码 chrome**：pageMap 未完整时底栏**不显示全书页码**（分母会随窗口漂移）；改显示 `节序 / 节内页序`（如 `12 / 480 节 · 3 / 8 页`）。全书 map 就绪后恢复 `当前页 / 总页数`。
- 图片：按 OPF 相对路径解析，读取时补 `contentDirectoryPath`（如 `OEBPS/`）。  
- Chrome「页」导航仅在 `readingMode == page` 且已有 pageMap 时启用。

### Chrome 占位

- 顶栏内容高：`kBookReaderChromeBarHeight`（56）。  
- 底栏内容高：`kBookReaderChromeBottomHeight`（padding + IconButton）。  
- 正文 inset / 分页 `pageSize` 必须与上述常量一致，避免末行被挡。

## Locator 契约（book）

```json
{
  "sectionIndex": 0,
  "progressInSection": 0.0,
  "spineVersion": 1
}
```

- `sectionIndex`：spine 线性项下标（仅 `itemref` 顺序）。  
- `progressInSection`：0…1，节内进度。  
- `spineVersion`：spine 解析规则变更时递增以作废进度。  

整书 `progress_fraction` ≈ `(sectionIndex + progressInSection) / sectionCount`。

## 导入

- 扩展名：`epub`（`BrandConfig.app.importExtensions`）。  
- 路由：`EpubImportRouter` 自动探测 — 正文 EPUB → book import；页图 EPUB → comic import。  
- 存储：与 comic 相同 content-addressed 布局，同一 `library` / `covers` 目录。  
- `pageCount`：`sectionCount`。

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
2. 滚动与翻页均可阅读；目录 / 书签跳转正确。  
3. 退出再进恢复章节与大致位置。  
4. 页图 EPUB 自动进入漫画引擎。
