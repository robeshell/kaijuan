# 图书思维导图

| | |
|--|--|
| **状态** | **目标：轻会话产物（默认）**；实现仍部分走 Product Action 重路径，以本文为目标收敛 |
| **日期** | 2026-08-12 |
| **PRODUCT** | [§6](../PRODUCT.md) |
| **相关** | [ai.md](./ai.md)、[ai-product-actions.md](./ai-product-actions.md)、[ai-graph.md](./ai-graph.md)、[webdav-backup.md](./webdav-backup.md) |
| **引擎** | 图书 reflow only；漫画页图另案 |
| **栈** | **不引入 LangChain**；模型 I/O 用现有 Genkit adapter + App 编排即可 |

---

## 1. 定位（结论）

图书思维导图是**本书对话里的会话型可视化回答**，不是知识图谱式长期任务，也**不是**默认的重型产品工单。

对标体验（Anx Reader 一类）：快捷或自然语言 → 直接出图 → **接着聊即可改细**；无「继续修改」门槛、无自由输入「确认生成」卡。

| 是 | 不是 |
|----|------|
| 对话消息内的原生主题树 + 画布 | 独立 Tab / 全局 AI 产物库 |
| 一次（或按自然作品边界多次）结构化生成 | 字符 batch / reduce / 长 Agent 环 |
| 与聊天同一回合心智 | 默认 Proposal → 确认 → Journal 工单流 |
| 可选证据、导出、全屏 | 普通 Mermaid 的替代品 |

- 思维导图表达主题、论点与层级摘要；知识图谱表达实体、关系、证据与身份消歧。**不得**共用业务模型、缓存或视图状态。  
- 普通聊天 Mermaid 仍是通用富内容，**不得**解析、导入或迁移为原生 `AiBookMindMap`。  
- **不引入 LangChain**。生成与改图用现有对话 Agent（Function Calling）+ `AiBookMindMapService` / `completeJson`（或未来本地 outline→树）；Genkit 只做模型 I/O。

### 1.1 与 Product Action 的边界

| 路径 | 适用 |
|------|------|
| **轻路径（导图默认）** | 快捷生成、自由输入创建/修订、「再详细点」等会话改图；**默认不展示确认卡**；**不要求**用户先点「继续修改」 |
| **Product Action 控制面** | 留给图谱外写、整本译、导出、破坏性操作等；**不是**导图日常主路径的必经体验 |
| **实现债** | 代码若仍经 Journal/确认，属待拆除的重路径，**不得**再写进产品验收为「正确体验」 |

控制面协议本身可保留为平台能力，见 [ai-product-actions.md](./ai-product-actions.md)；**导图规格以本节轻路径为准**。

---

## 2. 对话入口与修订

### 2.1 入口

- **无关键词路由 / 第二意图模型。** 同一本书对话模型：直接回答、只读工具，或发起原生导图生成/修订。  
- **快捷**：「请为当前章生成思维导图」（及后续等价文案）→ App 已知范围 → **直接开始生成**（进度可见）。  
- **自由输入**：明确要画/生成/修订原生导图时，模型可走终止型能力（工具或 App 等价入口）；**评价、解释、教程、Mermaid、否定**应普通回答，不启动生成。  
- **伪交付**：模型未真正交付原生图却用正文声称「已生成思维导图」时，App 可撤回并做有界协议修复；修复成功后仍走轻路径生成，**不**为此强制确认卡。  
- 发送前冻结章节/作品/manifest/`workKey`；模型运行中翻页不改变已冻结范围。标题等为不可信引用材料。

### 2.2 范围

- 「当前章/本章/这一章/这章」→ 当前 Foliate 章。  
- 「当前作品/这部作品」→ 结构识别中的当前作品。  
- 「这本书/本书/整本书/全书」→ 当前出版物。  
- 无范围词时默认**当前章**。  
- 合集/分卷：仍可用对话内纵向范围卡（选作品/卷）；**选范围 ≠ 工单确认**，点选后直接生成。

### 2.3 修订（会话化，核心体验）

```text
用户：「再详细一点」/「把人物分支展开」
  → 若本会话有原生导图：默认目标 = 最近一张（或本轮上下文已点名的那张）
  → 直接修订生成 → 对话中追加新卡片（或更新展示策略见实现）
  → 评价 / 解释 / 「不用改了」→ 普通回答，不生成
```

- **不设**「继续修改」按钮或钉住前提；会话内直接改最近/preferred 图。  
- 否定、讨论、教程、明确 Mermaid：**零次**原生生成。  
- 多张图时：默认最近一张；用户点名标题/「上一张」时优先其指向；歧义时用一句追问，不弹复杂工单。

### 2.4 用户原始要求

快捷与自由输入均保留**用户完整原话**进入生成输入（可影响取舍），不得只留范围摘要。

---

## 3. 结构预检与用户告知

复用 `AiBookStructureSession`；生成前应有进度/范围反馈，禁止无反馈空窗。

- `singleWork`：当前章或全书一次生成；进度如「正在为你生成《书名》…」。  
- `segmentedSingleWork`：按部/卷依次生成，每范围一张卡片。  
- `multiWorkOmnibus` / 带候选的 `uncertain`：对话内纵向选范围后生成；不弹 Dialog/Bottom Sheet 作为主路径。  
- 结构预检规则（副标题、合集边界等）与既有结构规格一致，不另造导图专用 AI 书型判断。

---

## 4. 输入与生成

```text
快捷 / 自由输入 / 会话修订
  → App 冻结范围（必要时范围卡）
  → 读取有效正文 + 用户原话
  → 一次 completeJson（或等价结构化）
  → 树校验、稳定 ID、可选 evidence
  → 写入对话消息附件并展示原生画布
```

- 一范围一次模型请求；**禁止** batch/reduce、字符采样充完整、静默截断装成功。  
- 上下文过长：明确失败，提示换模型或缩小范围。  
- 正文不可信；书型编辑原则（论说/叙事/知识、`organizingPrinciple`、平行标题、反目录复刻）仍适用。  
- 模型返回 `contentKind`、`organizingPrinciple`、扁平 `nodes`（`tempId/parentTempId/order/title/summary/evidence?`）；不返回 Mermaid/坐标。  
- **不**要求 Genkit `defineFlow`；**不**引入 LangChain。

---

## 5. 数据与持久化

```text
AiBookMindMap
  version / contentHash / workKey? / createdAt / model
  scopeSectionIndices / scopeFingerprint / contentKind / organizingPrinciple / layout
  nodes[]
  （可选）artifactId / sourceArtifactId / revision   — 便于多图与修订，非工单必经

AiBookMindMapNode
  nodeId / parentId / order / level / title / summary / evidence[]
```

- 校验：父引用、无环无孤、非空标题摘要；多根 forest 可本地合成单根；稳定 `mm001…`。  
- evidence 可选；无法逐字定位则丢弃。  
- **唯一产品持久化事实**：`ai_chat/` 消息附件；随用户主动 WebDAV。无独立 `ai_mind_map/` 目录、无重复 WebDAV 顶层 `aiMindMaps`。  
- Key、临时布局坐标不进备份。  
- 轻路径**不**把 Journal/Receipt 当用户可见产物；若实现暂写 Journal，不得驱动「必须确认」体验。

---

## 6. 布局与交互

- 布局：`bidirectional`（默认）、`rightFacing`、`radial`。  
- 原生 Flutter 画布：缩放、拖动、折叠、详情、可选证据跳转、全屏；非 WebView 业务 Mermaid。  
- 导出 PNG：完整画布（非视口裁切），桌面保存面板 / 移动相册；超大图降倍率。  
- 进度与错误紧贴对话；可停止；晚到结果不得写入。

---

## 7. 验收（轻路径）

- 快捷「生成本章思维导图」→ **无确认卡** → 一次结构化调用 → 原生卡片。  
- 自由输入明确生成 → **无确认卡**（默认）→ 原生卡片；评价/教程/Mermaid/否定 → 零次生成。  
- 「再详细一点」（会话内已有图）→ **无「继续修改」前提、无确认卡** → 修订生成。  
- 合集范围卡选完即生成，不二次「确认生成」工单。  
- 无 batch/reduce/独立 mind-map store。  
- 取消与失败终态清晰；已完成卡片保留。  
- 导出与三种布局可用；普通 Mermaid 不受影响。  
- **栈**：无 LangChain 依赖；模型走现有 Genkit adapter。

### 7.1 实现收敛说明（文档债）

轻路径已落地：自由输入 create/revise 无确认卡；会话改图不设「继续修改」按钮（默认最近/preferred 图）。Journal 控制面仍可承载崩溃恢复与重任务，**不**作为导图日常交互门槛。

---

## 8. 非目标

- 用 LangChain / 超长 ReAct 替代有界对话工具循环。  
- 导图默认上完整 Product Action 确认与跨端 Journal 恢复。  
- 与知识图谱共用模型或缓存。  
- 漫画页图导图。
