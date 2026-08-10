# 图书思维导图

| | |
|--|--|
| **状态** | 已实现（独立 `BookMindMapWorkflow`） |
| **日期** | 2026-08-10 |
| **PRODUCT** | [§6](../PRODUCT.md) |
| **相关** | [ai.md](./ai.md)、[ai-graph.md](./ai-graph.md)、[webdav-backup.md](./webdav-backup.md) |
| **引擎** | 图书 reflow only；漫画页图另案 |

## 1. 定位

图书思维导图表达章节主题、论点和层级摘要。它与知识图谱分属两个业务模块：知识图谱以实体、关系、证据和身份消歧为中心；思维导图以一份冻结正文范围内的主题层级为中心。两者不得共用业务模型、缓存或视图状态。

普通聊天继续支持 Mermaid 和其他富内容图表。聊天图表是一次回答的展示内容，不得作为图书思维导图的事实来源、缓存格式或恢复输入。

## 2. 产品入口与范围

- 「本书 AI」增加独立「思维导图」页签；空对话中的「生成思维导图」快捷入口只切换到该页签，不向聊天 Agent 发送长期任务提示词。
- 生成前由 App 冻结 `contentHash`、可选 `workKey`、作品标题和用户确认的章节范围。文件内多作品先选作品，再选该作品的内容单元；当前翻页不改变运行中的范围。
- 范围确认列出全部可读内容单元。正文/辅文规则只给默认建议，用户最终勾选是权威输入；字符预算只能均衡抽样，不能让后部章节从选择器消失。
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
- 只有一个根节点；无环、无孤儿、`level = parent.level + 1`、同父 `order` 唯一且连续。
- 标题短于摘要；根节点不得塞入全书长句。模型输出仍需经过长度、层级、分支均衡、证据范围和引文定位校验。
- 每个非根节点至少有一条能在所选正文中定位的证据，每个输入 batch 至少被最终证据覆盖一次。附加证据无法定位时可保留为 `spanResolved=false`，但节点详情明确标注，不把它冒充精确跳转。

## 4. 确定性 Workflow

```text
App 冻结书籍/作品/章节范围
  → 章节均衡采样与稳定 batch
  → 逐 batch 调用 AiWorkflowModelSession.completeJson
  → Schemantic schema + App 业务校验
  → 原子写入 checkpoint（已完成 batch + 中间摘要）
  → 最终结构化归并
  → App 规范化 nodeId/层级/证据
  → App 按内容类型与拓扑选择布局
  → 原子保存 AiBookMindMap，删除 checkpoint
```

- `BookMindMapWorkflow` 自己不持有 Provider、Genkit 类型、UI 或 WebDAV 客户端。模型 I/O 只经 `AiWorkflowModelSession.completeJson`。
- 开卷拥有 `AiRunOrchestrator`、预算、取消、超时、范围、重试、checkpoint、存储和 UI 状态。暂不使用 Genkit `defineFlow` / Agent；Genkit 只负责 Provider 归一化、structured output、Schema 和 trace。
- batch 失败不写完成标记。取消、网络失败和进程退出保留最后一个原子 checkpoint；同范围再次生成时恢复未完成 batch。
- 模型输出的临时 ID、布局建议和 HTML/SVG 都不可信；App 只消费结构化主题数据。

## 5. 布局与交互

支持 `radial`、`rightFacing`、`bidirectional`。用户可手动选择，自动模式由 App 的纯函数结合 `contentKind`、最大层级、根分支宽度和节点总数决定；同一输入必须得到同一布局。

- Flutter 原生布局 + `CustomPainter` 连线 + `InteractiveViewer`，不创建 WebView，不执行 Mermaid。
- 支持缩放、拖动、重新居中、折叠/展开分支、节点详情和从证据跳回原文。
- 画布不是唯一可访问入口。节点详情和可聚焦的层级列表提供等价操作；触控目标手机不少于 44px。
- 大图只布局可见树。折叠分支不参与坐标计算；超过性能边界时默认折叠深层并提示读者展开，不在 UI isolate 做模型或文件 I/O。

## 6. 持久化与 WebDAV

- 结果存于 `ai_mind_map/$contentHash[.$workKey].json`；checkpoint 存同目录的 `.checkpoint.json`，完成后删除。
- 主键为 `contentHash + workKey`。删书不删除思维导图；同文件再导入自动续上；显式「删除思维导图」才删除结果与 checkpoint。
- 用户主动 WebDAV 快照包含已完成思维导图，不包含运行中 checkpoint、API Key、模型协议连续性元数据或布局临时坐标。
- 恢复采用本地优先：本地已有合法产物不覆盖；本地没有时恢复远端。旧快照缺少 `aiMindMaps` 合法。

## 7. 实施阶段

1. 文档与业务模型：冻结边界、Schema、验证器、布局策略。
2. Workflow 与存储：预算、取消、checkpoint、错误和恢复。
3. Controller：独立状态机、范围解析、原子保存、WebDAV。
4. UI：独立页签、快捷路由、原生画布、折叠/详情/跳转。
5. 验证：模型/存储/恢复/取消/错误、布局算法、Widget 与大图边界测试；保留聊天 Mermaid 回归测试。

## 8. 验收

- 相同结构输入的节点 ID、父子关系和自动布局确定性一致。
- 非法父引用、环、跨范围证据、过长标题和失衡根节点不会被静默保存。
- 取消后保留 checkpoint；同范围恢复不重做已完成 batch；换范围不复用旧 checkpoint。
- UI 可切换三种布局、折叠、缩放、拖动、打开详情并跳回证据。
- WebDAV 能导出/恢复已完成思维导图，旧快照仍可解析，Key 与 checkpoint 不进入快照。
- 普通聊天 Mermaid mindmap 和其他图表继续渲染，且不读取 `AiBookMindMap`。
