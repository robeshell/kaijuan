# 图书思维导图

| | |
|--|--|
| **状态** | Workflow 与对话内入口已实现 |
| **日期** | 2026-08-10 |
| **PRODUCT** | [§6](../PRODUCT.md) |
| **相关** | [ai.md](./ai.md)、[ai-graph.md](./ai-graph.md)、[webdav-backup.md](./webdav-backup.md) |
| **引擎** | 图书 reflow only；漫画页图另案 |

## 1. 定位

图书思维导图表达章节主题、论点和层级摘要。它与知识图谱分属两个业务模块：知识图谱以实体、关系、证据和身份消歧为中心；思维导图以一份冻结正文范围内的主题层级为中心。两者不得共用业务模型、缓存或视图状态。

普通聊天继续支持 Mermaid 和其他富内容图表。聊天图表是一次回答的展示内容，不得作为图书思维导图的事实来源、缓存格式或恢复输入。

## 2. 产品入口与范围

- 独立 Workflow 不等于独立页签。「本书 AI」不设置思维导图 Tab；用户在对话中说“当前章/本章”时冻结当前章，说“这本书/全书”时冻结当前作品或整书，随后直接路由到 `BookMindMapWorkflow`。生成进度、停止、失败、重试和完成后的原生交互图都属于该对话轮次，不向聊天 Agent 发送长期任务提示词。
- 发起轮次时由 App 冻结 `contentHash`、可选 `workKey`、作品标题和章节范围；当前翻页不改变运行中的范围。“当前章”必须直接冻结 Foliate 当前文档正文、章标题和物理定位；不得先抽取整书逻辑章节，再假设阅读器 section 序号与逻辑语料的 `sourceSectionIndex` 一定同源。自然语言中的明确范围就是用户确认，不再弹出独立范围选择器。
- “生成本章思维导图”快捷入口冻结当前章；用户明确说“这本书/整本书/全书”时冻结当前作品或整书。当前章纯文本必须保留可见标题、段落、列表之间的换行，不能因 DOM `textContent` 拼接而丢失结构。本章只有一个冻结内容单元时，在单批预算内必须保留全文并一次结构化生成节点树，不得沿用整书的逐章短采样或 batch/reduce；只有单章自身超过单批安全预算才允许头、中、尾保序采样。整书字符预算必须跨章节均衡，不能让后部章节消失。
- 首次生成、重新生成和恢复 checkpoint 都使用相同的范围指纹。范围变化后旧 checkpoint 不得混入新任务。

## 3. 数据契约

落盘事实为 `AiBookMindMap`，不保存 Mermaid 源码：

```text
AiBookMindMap
  version / contentHash / workKey / createdAt / model
  scopeSectionIndices / scopeFingerprint / contentKind / layout
  nodes[]

AiBookMindMapNode
  nodeId / parentId / order / level
  title / summary / evidence[]

AiBookMindMapEvidence
  sectionIndex / quote / progressInSection / spanResolved
```

- 节点使用扁平数组。`nodeId` 在 App 校验后按确定性前序重新分配，`parentId` 只引用同一产物内节点。
- 完成产物以结构化附件随对话消息持久化，同一会话可同时保留多个章节与全书思维导图；不得用仅按 `contentHash + workKey` 的单槽缓存覆盖旧对话结果。
- 只有一个根节点；无环、无孤儿、`level = parent.level + 1`、同父 `order` 唯一且连续。
- 标题短于摘要；根节点不得塞入全书长句。模型输出仍需经过长度、层级、分支均衡、证据范围和引文定位校验。
- 引文是可选的跳回原文增强信息：能在所选正文中定位时标为 `spanResolved=true` 并提供跳转；缺少或无法定位的引文不阻断摘要节点或整棵树，也不得被伪造为精确跳转。

## 4. 确定性 Workflow

```text
App 冻结书籍/作品/章节范围
  → 单内容单元：一次 AiWorkflowModelSession.completeJson 生成树
  → 多内容单元：章节均衡采样与稳定 batch
  → 逐 batch 调用 AiWorkflowModelSession.completeJson
  → 原子写入 checkpoint（已完成 batch + 中间摘要）
  → 最终结构化归并
  → Schemantic schema + App 业务校验
  → App 规范化 nodeId/层级/证据
  → App 按内容类型与拓扑选择布局
  → 原子保存 AiBookMindMap，删除 checkpoint
```

- `BookMindMapWorkflow` 自己不持有 Provider、Genkit 类型、UI 或 WebDAV 客户端。模型 I/O 只经 `AiWorkflowModelSession.completeJson`。
- 开卷拥有 `AiRunOrchestrator`、预算、取消、超时、范围、重试、checkpoint、存储和 UI 状态。暂不使用 Genkit `defineFlow` / Agent；Genkit 只负责 Provider 归一化、structured output、Schema 和 trace。
- DeepSeek 只接受原生 `json_object`，隔离 adapter 把锁版 Genkit 插件生成的 `json_schema` 请求转换为该模式，并把同一 schema 注入消息；Genkit JSON parser 与本 Workflow 的结构/证据校验仍必须全部通过。该兼容分支不得变成 fenced JSON 或跨协议 transport 回退。
- batch 失败不写完成标记。取消、网络失败和进程退出保留最后一个原子 checkpoint；同范围再次生成时恢复未完成 batch。
- 结构校验失败后的重试必须携带 App 给出的具体、无正文内容的修复原因（例如层级不足或父引用无效），不得用相同提示盲目重复。层级口径统一为根节点 `level=0`，至少包含 `level=2` 的孙节点，最多到 `level=4`。根节点多余 evidence 由 App 丢弃。模型提供的引文必须落在冻结正文范围内，成功定位后启用“跳回原文”；模型漏传、改写或无法定位引文时只丢弃该引文，不得让摘要节点或整棵树失败，也不得从正文自由猜测补证。
- 批次主题数与最终树的最低结构密度由 App 从冻结正文字符数确定，并同时写入提示词与业务校验。短范围仍允许紧凑结果；达到长章节规模时最终至少需要 10 个节点和 3 个根分支，不能让模型用全局固定的最低线吞掉论证链。
- 失败、取消和成功是互斥终态。服务端拒绝结构化格式、模型输出无效或网络失败时必须显示可重试错误；只有用户明确停止才显示取消，不得无声回到未生成空态。
- 模型输出的临时 ID、布局建议和 HTML/SVG 都不可信；App 只消费结构化主题数据。

## 5. 布局与交互

支持 `radial`、`rightFacing`、`bidirectional`。用户可手动选择，自动模式由 App 的纯函数结合 `contentKind`、最大层级、根分支宽度和节点总数决定；同一输入必须得到同一布局。

- Flutter 原生布局 + `CustomPainter` 连线 + `InteractiveViewer`，不创建 WebView，不执行 Mermaid。
- 支持缩放、自由拖动、重新居中、折叠/展开分支、节点详情和从证据跳回原文。画布拖动不得在导图外 240px 等近距离设置透明边界，应允许用户把任意分支自由移到视口中心；手动缩放范围覆盖全图总览和单节点细读。桌面鼠标滚轮与触控板滚动缩放必须以当前指针位置为锚点，缩放前后指针下的场景坐标保持不变；指针位于嵌入画布内时，该事件只操作导图，不得同时滚动外层对话。对话卡片提供“全屏查看”，以独立 `Scaffold` 路由铺满 App 工作区；它共享同一结构化数据和布局选择回调，不新增 Tab 或第二份缓存。
- 画布不是唯一可访问入口。节点详情和可聚焦的层级列表提供等价操作；触控目标手机不少于 44px。
- 大图只布局可见树。折叠分支不参与坐标计算；超过性能边界时默认折叠深层并提示读者展开，不在 UI isolate 做模型或文件 I/O。

## 6. 持久化与 WebDAV

- 对话消息中的结构化 `AiBookMindMap` 附件是用户可见的历史事实，随 `ai_chat/` 会话保存；`ai_mind_map/$contentHash[.$workKey].json` 只保留该范围最近一次完成产物，供运行恢复和旧版本兼容。checkpoint 存同目录的 `.checkpoint.json`，完成后删除。
- 消息附件以各自 `scopeFingerprint` 区分，同一会话可并存多个本章与全书结果。删书不删除对话附件；同文件再导入自动续上；清空对应对话才删除其历史附件。
- 用户主动 WebDAV 快照通过对话记录包含全部已完成思维导图，并兼容备份最近产物；不包含运行中 checkpoint、API Key、模型协议连续性元数据或布局临时坐标。
- 恢复采用本地优先：本地已有合法产物不覆盖；本地没有时恢复远端。旧快照缺少 `aiMindMaps` 合法。

## 7. 实施阶段

1. 文档与业务模型：冻结边界、Schema、验证器、布局策略。
2. Workflow 与存储：预算、取消、checkpoint、错误和恢复。
3. Controller：独立状态机、对话范围路由、原子保存、WebDAV。
4. UI：对话内快捷路由和结构化结果卡片、原生画布、折叠/详情/跳转；不设置独立思维导图页签。
5. 验证：模型/存储/恢复/取消/错误、布局算法、Widget 与大图边界测试；保留聊天 Mermaid 回归测试。

## 8. 验收

- 相同结构输入的节点 ID、父子关系和自动布局确定性一致。
- 非法父引用、环、跨范围证据、过长标题和失衡根节点不会被静默保存。
- 取消后保留 checkpoint；同范围恢复不重做已完成 batch；换范围不复用旧 checkpoint。
- DeepSeek 请求使用 `json_object` 而非 `json_schema`，非法 JSON 或不符合业务约束的结果仍失败；普通失败不会被取消收尾吞掉。
- UI 可切换三种布局、折叠、宽范围缩放、无近距离边界拖动、打开详情并跳回证据；桌面缩放以指针为锚且不联动外层对话滚动；对话卡片可进入并关闭全屏画布，且全屏中的布局切换会保存回同一对话附件。
- WebDAV 能导出/恢复已完成思维导图，旧快照仍可解析，Key 与 checkpoint 不进入快照。
- 普通聊天 Mermaid mindmap 和其他图表继续渲染，且不读取 `AiBookMindMap`。
