# KaikaNext 文档索引

仓库实现 **一个本地阅读 App**（Kaika），内建漫画页图引擎 + 图书 reflow 引擎。  
权威与扩展方法以本页为准。

## 读哪份

| 你要… | 打开 |
|--------|------|
| 产品功能、阶段、非目标 | [PRODUCT.md](./PRODUCT.md) |
| 共享视觉 | [DESIGN_FOUNDATION.md](./DESIGN_FOUNDATION.md) |
| 工程结构 / 单入口 / 数据沿用 | [ENGINEERING.md](./ENGINEERING.md) |
| Foliate 全链路研究与取舍 | [research/foliate-architecture.md](./research/foliate-architecture.md) |
| 某屏交互 | [specs/](./specs/) |
| 图书工具条大改计划 | [specs/book-reader-tool-strip-plan.md](./specs/book-reader-tool-strip-plan.md) |
| 给 Open Design | [opendesign/HANDOFF.md](./opendesign/HANDOFF.md) |
| 代码约定 | [../AGENTS.md](../AGENTS.md) |
| 会话交接（易过期） | [dev-handoff.md](./dev-handoff.md) |

> 当前交接状态（2026-07-22）：Foliate 大改造尚未提交，Android metadata probe 存在已定位的 `style.allowScript` 启动参数阻塞。接手前先读 [dev-handoff.md](./dev-handoff.md)。

## 目录树

```text
docs/
  README.md
  PRODUCT.md                 ← 产品权威（单 App 双引擎）
  DESIGN_FOUNDATION.md       ← 视觉权威
  ENGINEERING.md             ← 工程骨架
  dev-handoff.md
  research/
    foliate-architecture.md
  specs/
    _TEMPLATE.md
    library.md / shelf.md / search.md / lists.md / collections.md
    reader-chrome.md / book-reader.md
    book-reader-tool-strip-plan.md   ← 图书底栏工具条大改（计划）
  opendesign/
    HANDOFF.md / CONTEXT.md / DESIGN.md / BRIEFS.md
```

## 权威层级

1. **PRODUCT.md** — App 做什么  
2. **DESIGN_FOUNDATION.md** — 长什么样  
3. **ENGINEERING.md** — 仓库怎么组织、怎么构建  
4. **specs/** — 单屏交互  
5. **AGENTS.md** — 实现约束  
6. **opendesign/** — 出图；不发明 PRODUCT 没有的能力  
7. **dev-handoff.md** — 仅续聊  

## 已定原则（摘要）

- **一个 App、一套数据**（沿用已有 `app_library`）。  
- **一个仓库**，共享 core；两个引擎按 `item.kind` 路由。  
- 书库内提供「全部 / 漫画 / 图书」类型筛选，不再用品牌分段。  
- 导入 **CBZ / ZIP / EPUB**；EPUB 自动探测正文 vs 页图。

## 如何扩展

### 加功能

1. 改 PRODUCT §4 表（标明 engine：image / book / 共享）。  
2. 开或改 specs。  
3. 实现挂对应 engine 或共享层（见 ENGINEERING）。  

### 加格式 / 导入策略

1. PRODUCT §8 格式矩阵说明。  
2. `ReaderFormat` / `EpubImportRouter` 加路由。  
3. 对应 import service 加支持。

### 加工程包

1. 改 ENGINEERING 目标树。  
2. 再改代码骨架。  

## specs 一览

| Spec | 说明 |
|------|------|
| library / shelf / search | 书库 / 书架 / 搜索 |
| lists | **书单**（长清单） |
| collections | **合集**（拼贴盒） |
| reader-chrome | 共享 chrome 语言 |
| book-reader | book reflow（spike 已落地） |
| settings / mobile / overlay | **待写** |

整理三概念权威表见 [PRODUCT.md §4.4a](./PRODUCT.md)。
