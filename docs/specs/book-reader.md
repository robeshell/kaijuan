# 图书阅读器设计规范（book App）

| | |
|--|--|
| **PRODUCT** | [§4.6](../PRODUCT.md) · [§8 格式矩阵](../PRODUCT.md) |
| **相关** | [reader-chrome.md](./reader-chrome.md)、[library.md](./library.md) |
| **状态** | 规格 + **reflow spike 已落地**（纯文本；可替换引擎） |

## 目标

**book** 产品的正文阅读：EPUB **reflow**（文字流式），非页图。  
与 **comic** 的页图 EPUB（spine→图）**严格分流**。

## 范围

### 做（v1 / spike）

- 导入 EPUB（reflow）：content-hash 去重、封面/标题元数据、`kind=book`。  
- 打开：按 spine **分节** 阅读；滚动/翻节；进度写入不透明 locator。  
- 阅读默认：字号、行距、阅读背景（纸白/米色/深灰…）。  
- Chrome：返回、目录（spine）、字号 +/-、主题；可隐藏。  
- 与 comic 共享：整理三概念、书库壳、桌面 inset（不共享页图引擎）。

### 不做（本阶段）

- 漫画页图 EPUB 走 book。  
- 划线笔记、TTS、在线书城。  
- 复杂 CSS / 固定版式双栏还原（远）。

## 引擎决策（spike）

| 方案 | 说明 |
|------|------|
| **当前 spike** | 自研轻量：ZIP + OPF spine → 抽取 XHTML 纯文本 → Flutter `Text`/`SelectableText` 流式排版 |
| 后续可替换 | 若版式不够，再评估 `flutter_html` / 嵌入 WebView；locator 契约保持不透明 |

原则：**DB 不解析 locator**；节索引 + 节内偏移/进度分数属 format-owned JSON。

## Locator 契约（book）

```json
{
  "sectionIndex": 0,
  "progressInSection": 0.0,
  "spineVersion": 1
}
```

- `sectionIndex`：spine 线性项下标（仅 `itemref` 顺序）。  
- `progressInSection`：0…1，节内滚动比例（spike）。  
- `spineVersion`：spine 解析规则变更时递增以作废进度。  

整书 `progress_fraction` ≈ `(sectionIndex + progressInSection) / sectionCount`。

## 导入

- 扩展名：`epub`（`BrandConfig.book.importExtensions`）。  
- 拒绝路径：若 OPF spine **无可用文字节**且仅有图片页 → 提示「页图 EPUB 请用漫画 App」（可选文案）。  
- 存储：与 comic 相同 content-addressed 布局，目录在 `book` namespace。  
- `pageCount`：0（或 sectionCount 写入扩展字段前暂 0）。

## UI

- 全屏阅读；顶栏：返回 / 标题 / 目录 / 设置。  
- 底栏或侧栏：字号、主题。  
- 桌面：顶栏遵守 `DesktopTitleBarMediaQuery`；mac 左侧让红绿灯。  
- 空态 / 失败：安静中文文案。

## 打开路由

```text
book 书库点条目 → BookReaderScreen
comic 书库点条目 → ComicReaderScreen
```

书库壳可共享；**禁止** book 条目进入 comic 页图 session。

## 验收（spike）

1. book flavor 导入 reflow EPUB 出现在书库。  
2. 打开可滚动正文，切换章节。  
3. 退出再进恢复章节与大致滚动位置。  
4. 漫画页图 EPUB 仍只在 comic 可用。
