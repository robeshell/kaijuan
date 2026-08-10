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
| LLM 三元组抽取研究与学习路径 | [research/kg-llm-extraction.md](./research/kg-llm-extraction.md)（服务 ai-graph） |
| 本书 AI 从普通对话到 Tool Agent 的实现演进 | [research/ai-chat-agent-evolution.md](./research/ai-chat-agent-evolution.md)（当前全流程 + 后续文章主线） |
| 图书 AI 助手演进系列文章 | [articles/book-ai-assistant-evolution/](./articles/book-ai-assistant-evolution/)（第一篇：从模型调用到可靠对话） |
| AI 运行时 Genkit 完整收口计划 | [research/ai-runtime-genkit-completion-plan.md](./research/ai-runtime-genkit-completion-plan.md)（词典/翻译/大纲/图谱迁移与旧 Provider 删除边界） |
| 某屏交互 | [specs/](./specs/) |
| 图书听书（TTS） | [specs/book-tts.md](./specs/book-tts.md)（T1 MVP 已有；不接云端 AI 音色） |
| 本书 AI 智能体 | [specs/ai.md](./specs/ai.md)（BYOK / 词典译 / 对话…） |
| AI 翻译偏好与选区译 | [specs/ai-translation.md](./specs/ai-translation.md)（设计定稿） |
| 本书知识图谱 | [specs/ai-graph.md](./specs/ai-graph.md)（M5 已实现；实体/关系/出处，章级增量） · 展示方案驱动 + 家族树见 [specs/ai-graph-narration.md](./specs/ai-graph-narration.md)（N1–N4 已实现） |
| 图书思维导图 | [specs/ai-mind-map.md](./specs/ai-mind-map.md)（独立确定性 Workflow、结构化节点与原生布局） |
| 代码约定 | [../AGENTS.md](../AGENTS.md) |

## 目录树

```text
docs/
  README.md
  PRODUCT.md                 ← 产品权威
  DESIGN_FOUNDATION.md       ← 视觉权威
  ENGINEERING.md             ← 工程骨架
  articles/
    book-ai-assistant-evolution/
      01-reliable-conversation.md   ← 系列第一篇：把一句回答接稳
  research/
    ai-chat-agent-evolution.md       ← 从模型对话到受控 Agent 的实现演进
    ai-runtime-genkit-completion-plan.md ← 全 AI 工作流统一模型边界的执行计划
    foliate-architecture.md
    kg-llm-extraction.md             ← LLM 三元组抽取研究与学习路径（对照 ai-graph）
  specs/
    _TEMPLATE.md
    library.md / shelf.md / search.md / lists.md / collections.md
    subpages.md
    import.md / remote-sources.md / wifi-transfer.md / webdav-backup.md
    reader-chrome.md / comic-reader.md / book-reader.md
    reading-stats.md
    book-tts.md
    ai.md                            ← 本书 AI 智能体
    ai-translation.md                ← AI 翻译偏好与选区译（设计定稿）
    ai-graph.md                      ← 本书知识图谱（M5 已实现）
    ai-graph-narration.md            ← 图谱展示方案驱动 + 家族树（N1–N4 已实现）
    ai-mind-map.md                   ← 图书思维导图（独立 Workflow）
```

## 权威层级

1. **PRODUCT.md** — App 做什么  
2. **DESIGN_FOUNDATION.md** — 长什么样  
3. **ENGINEERING.md** — 仓库怎么组织、怎么构建  
4. **specs/** — 单屏交互  
5. **AGENTS.md** — 实现约束  

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
| ai | 本书 AI 智能体（BYOK / 词典译 / 对话 / 大纲 / 思维导图；M0–M3b 已有） |
| ai-translation | AI 翻译偏好与选区译（设计定稿；T0–T3 已有，T4 整本译待办） |
| ai-graph | 本书知识图谱（M5 已有；实体/关系/出处，章级增量） |
| ai-graph-narration | 图谱展示方案驱动 + 家族树（N1–N4 已实现；方案契约/方向约定/连线架构图/地点链） |
| ai-mind-map | 图书思维导图（独立确定性 Workflow；结构化节点/证据/原生布局） |
| settings / mobile / overlay | **待写** |

整理三概念权威表见 [PRODUCT.md §4.3](./PRODUCT.md)。
