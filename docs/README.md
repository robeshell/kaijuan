# kaijuan 文档索引

仓库实现 **一个本地阅读 App**（开卷），内建漫画页图引擎 + 图书 reflow 引擎。  
权威与扩展方法以本页为准。

## 读哪份

| 你要… | 打开 |
|--------|------|
| 产品功能、阶段、非目标 | [PRODUCT.md](./PRODUCT.md) |
| 共享视觉 | [DESIGN_FOUNDATION.md](./DESIGN_FOUNDATION.md) |
| 工程结构 / 单入口 / 数据沿用 | [ENGINEERING.md](./ENGINEERING.md) |
| Foliate 全链路研究与取舍 | [research/foliate-architecture.md](./research/foliate-architecture.md) |
| 某屏交互 | [specs/](./specs/) |
| 图书工具条大改计划 | [specs/book-reader-tool-strip-plan.md](./specs/book-reader-tool-strip-plan.md)（底栏已落地，可归档） |
| 图书阅读下一程 | [specs/book-reader-next-plan.md](./specs/book-reader-next-plan.md) |
| 图书听书（TTS）方案 | [specs/book-tts.md](./specs/book-tts.md)（方案；不接云端 AI） |
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
    subpages.md                     ← 管理型二级/子级页面统一骨架
    reader-chrome.md / comic-reader.md / book-reader.md / wifi-transfer.md
    webdav-backup.md              ← WebDAV 快照备份与恢复
    reading-stats.md                 ← 阅读统计（洞察 + 时长 + 热力 + 备份）
    book-reader-tool-strip-plan.md   ← 图书底栏工具条大改（计划）
    book-tts.md                      ← 听书方案（系统 TTS，不接 AI）
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
- 导入 **CBZ / ZIP / EPUB / FB2 / MOBI / AZW3 / PDF / TXT / MD**；EPUB 自动探测正文 vs 页图。导入链路按「方式 / 格式」两层组织，见 [specs/import.md](./specs/import.md)。

## 如何扩展

### 加功能

1. 改 PRODUCT §4 表（标明 engine：image / book / 共享）。  
2. 开或改 specs。  
3. 实现挂对应 engine 或共享层（见 ENGINEERING）。  

### 加格式 / 导入策略

1. PRODUCT §8 格式矩阵说明。
2. `docs/specs/import.md` 先明确方式层与格式层的边界。
3. `ReaderFormat` / `EpubImportRouter` 加格式路由；方式适配器只产生 `ImportCandidate`。
4. 对应 import service 加支持，并复用统一 staging / hash / 提交协议。

### 加工程包

1. 改 ENGINEERING 目标树。  
2. 再改代码骨架。  

## specs 一览

| Spec | 说明 |
|------|------|
| library / shelf / search | 书库 / 书架 / 搜索 |
| import | 导入方式与导入格式两层链路 |
| lists | **书单**（长清单） |
| collections | **合集**（拼贴盒） |
| subpages | 管理型二级/子级页面的统一布局、操作与状态 |
| reader-chrome | 共享 chrome 语言 |
| book-reader | book reflow（主链已落地） |
| webdav-backup | 用户自有 WebDAV 备份与恢复 |
| book-tts | 听书方案（未实现；Foliate 切句 + 系统 TTS） |
| settings / mobile / overlay | **待写** |

整理三概念权威表见 [PRODUCT.md §4.4a](./PRODUCT.md)。
