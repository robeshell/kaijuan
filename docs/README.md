# kaijuan 文档索引

仓库实现 **一个本地阅读 App**（开卷），内建漫画页图引擎 + 图书 reflow 引擎。  
权威与扩展方法以本页为准。

## 读哪份

| 你要… | 打开 |
|--------|------|
| 产品功能、状态、下一程、非目标 | [PRODUCT.md](./PRODUCT.md) |
| 共享视觉 | [DESIGN_FOUNDATION.md](./DESIGN_FOUNDATION.md) |
| 工程结构 / 单入口 / 数据沿用 | [ENGINEERING.md](./ENGINEERING.md) |
| Foliate 全链路研究与取舍 | [research/foliate-architecture.md](./research/foliate-architecture.md) |
| 某屏交互 | [specs/](./specs/) |
| 图书阅读下一程（历史计划） | [specs/book-reader-next-plan.md](./specs/book-reader-next-plan.md) |
| 图书听书（TTS） | [specs/book-tts.md](./specs/book-tts.md)（T1 MVP 已有；不接云端 AI 音色） |
| 本书 AI 智能体 | [specs/ai.md](./specs/ai.md)（BYOK / 词典译 / 对话…） |
| AI 翻译偏好与选区译 | [specs/ai-translation.md](./specs/ai-translation.md)（设计定稿） |
| 本书知识图谱 | [specs/ai-graph.md](./specs/ai-graph.md)（M5 规格；实体/关系/出处，章级增量） |
| 给 Open Design | [opendesign/HANDOFF.md](./opendesign/HANDOFF.md) |
| 代码约定 | [../AGENTS.md](../AGENTS.md) |
| 会话交接（易过期） | [dev-handoff.md](./dev-handoff.md) |

## 目录树

```text
docs/
  README.md
  PRODUCT.md                 ← 产品权威
  DESIGN_FOUNDATION.md       ← 视觉权威
  ENGINEERING.md             ← 工程骨架
  dev-handoff.md
  research/
    foliate-architecture.md
  specs/
    _TEMPLATE.md
    library.md / shelf.md / search.md / lists.md / collections.md
    subpages.md
    import.md / remote-sources.md / wifi-transfer.md / webdav-backup.md
    reader-chrome.md / comic-reader.md / book-reader.md
    reading-stats.md
    book-reader-tool-strip-plan.md   ← 图书底栏（已落地，可归档）
    book-reader-next-plan.md
    book-tts.md
    ai.md                            ← 本书 AI 智能体
    ai-translation.md                ← AI 翻译偏好与选区译（设计定稿）
    ai-graph.md                      ← 本书知识图谱（M5 规格）
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
- 书库内「全部 / 漫画 / 图书」类型筛选。  
- 导入 **CBZ / ZIP / EPUB / FB2 / MOBI / AZW3 / PDF / TXT / MD**；方式/格式两层，见 [import.md](./specs/import.md)。  
- **AI** 为可选本书智能体（BYOK），见 [PRODUCT.md §6](./PRODUCT.md)。

## 如何扩展

### 加功能

1. 改 [PRODUCT.md](./PRODUCT.md) 对应功能表（标明引擎：页图 / reflow / 共享）。  
2. 开或改 specs。  
3. 实现挂对应 engine 或共享层（见 ENGINEERING）。  

### 加格式 / 导入策略

1. PRODUCT §7 格式矩阵。  
2. `docs/specs/import.md` 明确方式层与格式层边界。  
3. `ReaderFormat` / 路由加格式；方式适配器只产生 `ImportCandidate`。  
4. 复用统一 staging / hash / 提交协议。  

### 加 AI 能力

1. 改 PRODUCT §6 能力表与落地顺序。  
2. 开或改 `docs/specs/ai.md`；翻译专项见 `docs/specs/ai-translation.md`。  
3. ENGINEERING 增加 `lib/ai`（或等价）边界与 Provider 约定。  

### 加工程包

1. 改 ENGINEERING 目标树。  
2. 再改代码骨架。  

## specs 一览

| Spec | 说明 |
|------|------|
| library / shelf / search | 书库 / 书架 / 搜索 |
| import | 导入方式与格式两层链路 |
| remote-sources | WebDAV 导入 + OPDS |
| wifi-transfer | WiFi 传书 MVP |
| lists | **书单**（长清单） |
| collections | **合集**（拼贴盒） |
| subpages | 管理型二级/子级页面骨架 |
| reader-chrome | 共享 chrome 语言 |
| comic-reader / book-reader | 双引擎阅读 |
| webdav-backup | 用户自有 WebDAV 备份与恢复 |
| reading-stats | 阅读统计 |
| book-tts | 听书（系统 TTS；T1 MVP 已有） |
| ai | 本书 AI 智能体（M0–M2 MVP；M3+ 规划） |
| ai-translation | AI 翻译偏好与选区译（设计定稿；T0–T4） |
| settings / mobile / overlay | **待写** |

整理三概念权威表见 [PRODUCT.md §4.3](./PRODUCT.md)。
