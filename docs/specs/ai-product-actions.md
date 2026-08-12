# AI 产品动作协议（Product Action Protocol v1）

| | |
|--|--|
| **状态** | v1 控制面迁移中；协议骨架已建立，生产 Workflow、恢复与 Artifact 提交尚未完成 |
| **日期** | 2026-08-12 |
| **PRODUCT** | [§6](../PRODUCT.md) |
| **工程** | [ENGINEERING.md](../ENGINEERING.md)「AI 边界」 |
| **相关** | [ai.md](./ai.md)、[ai-workflow-extension.md](./ai-workflow-extension.md)、[ai-mind-map.md](./ai-mind-map.md)、[ai-graph.md](./ai-graph.md)、[ai-translation.md](./ai-translation.md) |
| **适用范围** | 本书对话中由模型建议，或由 App 明确入口触发的产品动作 |

> 本规范是开卷 AI 产品动作的权威控制协议。它定义建议、策略、确认、授权、执行、恢复与回执，不定义各领域 Workflow 内部如何生成内容。若其他 AI 规格把模型工具调用、输入附件或自然语言命中直接等同于执行授权，以本规范为准。

---

## 1. 结论

开卷采用以下固定边界：

```text
模型可以建议动作，不能授权动作；
App 可以解析和校验动作，只有可信用户操作或产品策略可以授权动作；
Workflow 只执行 App 签发的不可变命令，不执行原始模型 Tool Call。
```

正式链路：

```text
用户输入 / 明确 UI 操作
  → 冻结本轮上下文与能力目录
  → AiActionProposal
  → AiActionPolicy
    ├─ allow                → AiAuthorizedCommand
    ├─ requireConfirmation  → 对话内确认 → AiAuthorizedCommand / rejected
    ├─ requireClarification → 对话内补充 → 新 Proposal 或普通回答
    └─ deny                 → rejected
  → AiActionJournal 先记录命令
  → 确定性 Workflow
  → AiActionReceipt + 领域 Artifact
```

产品工具调用只是 `AiActionProposal` 的一种来源。它不是命令、不是审批结果，也不能直接启动思维导图、翻译、图谱重建、导出或写入笔记。

---

## 2. 术语与规范用语

本规范中的“必须 / 不得”是强制要求，“应 / 不应”是默认要求，“可以”是受边界约束的可选行为。

| 术语 | 定义 |
|------|------|
| **Product Action** | 会启动领域任务、改变持久化产品状态、产生或修订 Artifact、写文件或访问外部系统的动作 |
| **Read Tool** | 只读取冻结书籍上下文、不会改变产品状态的工具，如目录、章节、搜索和取样 |
| **Proposal** | 对“准备做什么”的结构化建议；无执行权 |
| **Policy** | App 自有的纯决策层；判断权限、风险、范围、目标、歧义与是否需要确认 |
| **Decision** | Policy 对 Proposal 的结果：允许、要求确认、要求补充或拒绝 |
| **Authorization** | 可信用户操作或 App 明确策略对一个确定动作的授权证据 |
| **Command** | App 根据有效授权签发的不可变执行命令 |
| **Workflow** | 开卷拥有的确定性领域编排；只接受 Command |
| **Artifact** | 思维导图、图谱、译稿、导出文件等领域产物 |
| **Receipt** | 一次 Command 的可审计执行结果，不等同于 Artifact |
| **Journal** | 本地持久化的动作控制记录，用于幂等、恢复、取消和晚到结果隔离 |
| **Action Definition** | 一个动作的编译期注册定义，包含 schema、风险、能力、Gateway、Workflow Adapter、Artifact 与版本 |

Read Tool 不进入产品动作审批，但仍受冻结作用域、参数预算、调用次数、取消和提示词注入防护约束。

---

## 3. 设计原则

### 3.1 建议与授权分离

- 模型输出文字、Tool Call、结构化 JSON 或“我将为你生成”之类承诺，都不能构成授权。
- 模型不得直接构造数据库 ID、文件路径、WebDAV 路径、真实 `artifactId` 或权限凭据。
- App 只向模型暴露本轮签发的临时别名；真实身份由 Gateway 在冻结快照内解析。
- Controller 的范围和预算校验不是用户授权，二者必须分别成立。

### 3.2 单一控制平面

- 自由输入、快捷入口、范围卡片、失败重试、崩溃恢复和未来产品动作都汇入同一 `AiProductActionController`。创建/修订请求走 Proposal/Policy；失败重试和恢复只引用既有 Command/Journal，不重新解释原始自然语言。
- 动作发现与分发来自 `ProductActionRegistry` 的注册定义；完整扩展接口见 [ai-workflow-extension.md](./ai-workflow-extension.md)。
- 不为每个中文说法增加关键词路由、正则矩阵或专用隐式分支。
- 不增加第二个意图模型。普通对话的同一模型可以回答、调用 Read Tool 或提出 Product Action Proposal。
- 显式 UI 命令可以跳过模型判断，但不能绕过 Policy、Journal 和 Workflow 预检。

### 3.3 框架无关

- `AiActionProposal`、`AiActionDecision`、`AiAuthorizedCommand`、`AiActionReceipt` 与 Journal 都是 App 自有纯 Dart 契约。
- Genkit Agent 的 Tool、Interrupt、Session、Snapshot 和 Artifact 不得成为产品数据库、会话文件或 WebDAV schema。
- `LegacyAiAgentRuntime` 与未来 `GenkitAgentRuntime` 必须投影成同一 App 协议。
- Genkit 可以承载 Interrupt/Resume，但不能拥有作品范围、产品授权、幂等、领域 Artifact 或 Workflow 提交权。

### 3.4 最小权限与显式作用域

- 每轮只向模型声明当前可用工具和临时别名。
- Command 必须携带冻结的 `contentHash`、可选 `workKey`、范围指纹和目标版本。
- 作品、章节或 Artifact 不明确时不得猜测执行；进入补充信息状态。
- 人类可读标题只用于展示，不作为身份键或授权依据。

### 3.5 可恢复且至多一次提交

- Workflow 开始前必须先持久化 Command 和幂等键。
- 重试可以产生新的 attempt，但不得重复提交同一个目标效果。
- Artifact 提交与 Receipt 终态必须具有确定顺序；进程崩溃后可以判断是安全重试、返回既有结果还是放弃。
- 取消必须区分“已请求取消”和“底层工作已静止”，不得只改变 UI 文案后继续提交晚到结果。

---

## 4. 正式状态机

```text
proposed
  → policyChecked
    → awaitingClarification
      → proposed | rejected | expired
    → awaitingConfirmation
      → authorized | rejected | expired
    → authorized
    → rejected

authorized
  → preflight
    → queued
      → executing
        → succeeded
        → partiallySucceeded
        → failed
        → cancelRequested
          → cancelled
          → failed
    → failed
    → abandoned
```

### 4.1 状态约束

- `proposed` 之前不得调用领域 Workflow。
- `authorized` 只能由有效 Policy allow 或用户确认产生，不能由模型事件直接产生。
- `awaitingClarification` 与 `awaitingConfirmation` 是可持久化等待态，不是普通助手 Markdown。
- `queued` 前必须写入 Journal；写入失败不得执行。
- `succeeded`、`partiallySucceeded`、`failed`、`cancelled`、`rejected`、`expired`、`abandoned` 是终态。
- 一个 Command 只能有一个产品终态。终态后的模型、网络和 Workflow 事件必须忽略并记录为晚到事件。
- `cancelRequested` 不是终态。只有 Workflow 已停止产生可提交副作用，才可进入 `cancelled`。

### 4.2 Proposal 与 Agent Run

- Product Tool Call 必须终止当前普通 Read Tool 循环，并投影成 `AiActionProposal`。
- Proposal 产生后，不保存模型声称“已经生成”的伪完成正文。
- 等待确认期间不要求模型持续占用连接。若运行时支持可持久化 Interrupt/Resume，可以恢复同一 Agent Run；不支持时由 App 持久化 Proposal，确认后直接签发 Command。
- 无论是否使用 Resume，Workflow 输入都来自 Command，不从恢复后的模型自由文本重新解析。

---

## 5. 数据契约

以下字段描述协议语义；实现可以使用等价命名，但不得删掉身份、版本、授权和幂等边界。

### 5.1 `AiActionProposal`

```text
protocolVersion
proposalId
parentRunId / conversationId / turnId
actionKind
definitionVersion
proposalSchemaVersion
source                 # modelTool | explicitUi
sourceSubmissionId     # 原始发送/按钮事件的稳定去重身份
originalUserText
requestedArguments
scopeRef               # 模型只可提交临时 work_n / section_n
targetRef              # 模型只可提交临时 artifact_n
expectedRevision?
frozenContextRef
provider / model / promptVersion?
capabilitySnapshotRef
createdAt / expiresAt
```

约束：

- `source=modelTool` 永远不自带授权。
- `source=explicitUi` 只表示发生了可信 UI 手势，是否可自动授权由 Policy 矩阵决定。
- Proposal 不保存完整书籍正文；只引用冻结快照、结构版本和范围指纹。
- 原始用户文字必须保留，后续领域 Workflow 不得只收到模型改写后的摘要。

### 5.2 `AiActionDecision`

```text
proposalId
outcome                # allow | requireConfirmation | requireClarification | deny
reasonCode
riskClass              # read | reversible | external | destructive
resolvedActionKind
resolvedScope
resolvedTarget?
normalizedArguments
confirmationSummary?
allowedHumanDecisions  # approve | edit | reject | respond
decidedAt
```

Policy 必须是纯决策：不调用模型、不读取实时翻页位置、不执行 Workflow、不写 Artifact。

### 5.3 `AiAuthorizedCommand`

```text
protocolVersion
commandId
proposalId
actionKind
definitionVersion
commandSchemaVersion
workflowVersion
authorizationSource   # explicitUi | userApproval | trustedPolicy
authorizationSubmissionId # 最终授权手势/审批的稳定去重身份
authorizationEvidence # UI action id / approval id，不含隐私正文
authorizedAt
idempotencyKey
contentHash / workKey?
scopeFingerprint
scopeSectionIndices
targetArtifactId?
expectedRevision?
arguments
originalUserText
```

约束：

- Command 创建后不可变。编辑范围或参数必须重新经过 Policy，并签发新 Command。
- `idempotencyKey` 绑定一次可信 `authorizationSubmissionId` 的期望效果，在该 submission 的安全重试间保持稳定。用户后来再次明确发起相同参数的动作拥有新的授权 submission，不得因内容 hash 相同而永久去重。
- `attempt` 不属于 Command。每次执行/恢复尝试由 Journal 与 `workflowRunId + attempt` 记录，Receipt 回写实际 attempt；重试不得修改已签发 Command。
- 修订命令必须携带 `targetArtifactId + expectedRevision`，提交时使用 compare-and-set；目标已更新则失败并要求读者基于最新版重试。
- Command 只能引用 App 已解析的真实身份，Workflow 不再认识 `artifact_n` / `work_n`。

### 5.4 `AiActionReceipt`

```text
commandId / workflowRunId
attempt
definitionVersion / workflowVersion
status                 # succeeded | partiallySucceeded | failed | cancelled | abandoned
artifactRefs[]
usage?
publicErrorCode?
diagnosticRef?
startedAt / finishedAt
```

- Receipt 记录执行事实，不能用助手文字代替。
- 用户错误只保存稳定公开错误码；供应商响应、HTTP 细节、堆栈和 Trace 只通过脱敏诊断引用关联。
- 多作品或分卷任务允许 `partiallySucceeded`，但必须列出已提交与未完成范围；不得删除已经完成的 Artifact。

### 5.5 `AiActionJournalEntry`

Journal 至少保存 Proposal/Decision/Command/Receipt 引用、当前状态、状态版本、单调事件序号和最近更新时间。

- Journal 是本地运行控制事实，不随 WebDAV 同步等待中的审批、进行中的模型连接或取消令牌。
- 完成后的领域 Artifact 继续按各自规格进入 `ai_chat/`、`ai_graph/`、导出文件或现有数据库。
- Journal 不保存 API Key、搜索 Key、WebDAV 凭据、Provider thinking 签名或完整书籍正文。
- 恢复时必须重新验证书籍仍存在、`contentHash` 与结构指纹未改变、目标 revision 仍匹配；否则进入 `abandoned`，不自动改用当前阅读位置。

---

## 6. 授权策略矩阵

第一阶段采用保守策略，待真实评测证明误触发率足够低后才可扩大自动授权范围。

| 来源与动作 | 默认 Policy | 说明 |
|------------|-------------|------|
| Read Tool：目录、当前章、按节、搜索、取样 | 不进入 Product Action Policy | 只读；由只读工具策略自动执行，仍受冻结范围和预算限制 |
| 用户点击“生成本章思维导图”等明确快捷入口 | `allow` | UI 已明确动作和范围；仍做预检并写 Journal |
| 用户在对话内范围卡片点击“生成” | `allow` | 卡片必须显示动作、作品/章节范围；该点击同时提供授权 |
| 自由输入后模型提出创建思维导图 | `requireConfirmation` | 首阶段必须展示对话内确认卡 |
| 自由输入后模型提出修订思维导图 | `requireConfirmation` | 显示目标版本与修改要求 |
| 仅附加导图后发送评价、提问或含糊文字 | 普通对话或 `requireClarification` | 附件只绑定目标，不授权修订 |
| 用户点击失败任务“重试” | 不创建新 Proposal | Controller 校验既有 Command、Journal 终态、能力和是否已提交，复用原 Command 与幂等键创建新的 Workflow attempt |
| 自由输入要求整本翻译、写入笔记、导出或外部分享 | `requireConfirmation` | 展示范围、目标和可能的外部写入 |
| 对明确 UI 按钮执行 PNG 导出/保存 | `allow` | 用户点击已明确；系统保存面板仍由平台确认目标 |
| 删除、清空、覆盖或不可逆操作 | `requireConfirmation` | 使用原生破坏性确认；不得由模型静默批准 |
| 未知别名、跨书目标、范围冲突、过期 Proposal | `deny` | 不得降级到当前章或当前作品 |

`trustedPolicy` 不是模型置信度阈值。它只能覆盖经过产品评审、无歧义且可逆的明确 UI 路径；任何新增自动授权动作必须更新本矩阵和评测集。

---

## 7. 对话与附件语义

### 7.1 自由输入

- 用户输入只进入一次普通对话 Agent 回合，不先跑关键词或第二意图模型。
- Agent 可以正常回答、使用 Read Tool、提出一个 Product Action Proposal 或询问用户。
- Product Action Proposal 必须是该模型响应中唯一的终止产品动作；不得与 Read Tool 请求并列执行。
- 模型没有提出产品动作时，App 不因用户文字包含“导图”“生成”“修改”等词自行补执行。

### 7.2 产物附件

- “继续修改”只把稳定 `artifactId` 绑定为本轮可信目标上下文，并显示可移除附件。
- 附件不把 composer 切换成永久修订模式，不意味着后续每句话都进入 Workflow。
- “这张图不错”“解释一下第三个分支”“不用改了”应走普通回答，不得生成新版本。
- “再详细一点”“把第三章展开”“删除重复分支”可由同一 Agent 提出指向该附件的修订 Proposal，再经 Policy。
- 关闭附件只移除目标上下文，不删除 Artifact，也不改变历史消息。
- 多个可用 Artifact 或目标不明确时，显示对话内纵向选择或补充卡片；不得靠“最近一张”静默猜测。

### 7.3 歧义语言

下列情况必须通过语义评测与补充交互处理，而不是新增字符串边界：

| 输入 | 期望 |
|------|------|
| “不用再出导图” | 普通回答；不得 Proposal |
| “请再出一个详细导图” | 创建或修订 Proposal，取决于可信上下文 |
| “不用，再出个详细导图” | 语义/标点有歧义时补充确认，不直接执行 |
| 附件 + “这张图很好” | 普通回答 |
| 附件 + “再详细一点” | 指向附件的修订 Proposal |
| 附件 + “不用改了” | 普通回答或取消待确认 Proposal |

---

## 8. 对话内确认与补充交互

- 确认、范围选择和补充信息均出现在对话时间线中，纵向展示；默认不使用 Dialog 或 Bottom Sheet。
- 等待卡片不是助手 Markdown，必须由结构化状态渲染并支持恢复。
- 确认卡至少展示：动作名称、目标书/作品/章节、目标 Artifact 与 revision（如有）、用户原始要求摘要、是否会产生外部写入。
- 创建操作使用“生成 / 修改范围 / 取消”；修订操作使用“应用修改 / 查看目标 / 取消”。按钮文案可以按动作调整，但不能只显示笼统“确定”。
- 用户选择“修改范围”或编辑参数后必须重新经过 Policy；不能直接修改已经签发的 Command。
- `reject` 结束 Proposal；`respond` 仅补充缺失信息，补充后创建新 Proposal，不复用过期范围。
- 等待确认时允许用户继续普通对话，但同一个 Proposal 只能被解决一次；会话中不得同时存在两个竞争的 composer 提交入口。

---

## 9. 幂等、并发与版本控制

- 一个用户提交动作只创建一个 `turnId` 和一个初始 `proposalId`；键盘、发送按钮和平台重复 action 汇入同一互斥入口。
- `commandId` 标识一次授权后的不可变命令；`idempotencyKey` 标识同一可信 submission 的期望产品效果。它必须纳入稳定授权 submission、解析后的动作、冻结范围以及可选目标/revision，不能只对书籍内容和参数做 hash。
- 同一按钮/确认事件的重复回调复用幂等键；用户稍后主动再次生成使用新的 submission id，即使参数完全相同也可以创建第二份 Artifact。
- Workflow 必须先查询 Journal：已成功则返回既有 Receipt；仍在执行则复用观察通道；确认未提交且可恢复时才创建新 attempt。
- 重试/恢复不是新的产品意图，不重新调用模型、Policy 或签发 Command；若用户修改范围、参数或目标，则是新动作，必须创建 Proposal 并重新授权。
- 同一 Artifact 的修订使用 `expectedRevision` compare-and-set。两个并发修订只能有一个提交成功，另一个进入冲突失败，不得后写覆盖。
- 多作品/分卷顺序任务中的每个子范围拥有稳定子命令或子幂等键；重试只补未完成范围。
- 会话消息和 Artifact 提交必须可按稳定 ID 去重；WebDAV 合并不得使用整段 JSON 相等作为唯一身份规则。

---

## 10. 取消、超时与晚到结果

- 用户点击停止后，UI 立即显示“正在停止”或等价状态，同时 Journal 进入 `cancelRequested`。
- Controller 必须向搜索、模型、Read Tool 和 Workflow 传播同一取消信号；不得在子阶段创建脱离父任务的新 token。
- Provider 不支持真实 HTTP 中止时，不得声称已经完成底层取消。可以停止 UI 消费并禁止提交，但只有底层调用返回且 Workflow 静止后才进入 `cancelled`。
- `cancelRequested` 后到达的模型输出、结构化结果、Artifact 或 Receipt 必须隔离；不得恢复消息、覆盖新 revision 或把任务改回成功。
- 超时是失败或取消原因，不是授权失效的替代。自动重试仍须遵守原 Command 的幂等规则，并在 Journal 中创建新的 Workflow attempt。

---

## 11. 安全与隐私

- 书名、作者、目录、正文、网页摘要、旧 Artifact、模型输出和 Tool 参数全部是潜在不可信数据。
- 只有 App 编译期注册并按本轮动态开放的 Tool 才能形成 Proposal。
- Gateway 必须拒绝未知 Tool、未知字段、未知别名、跨会话 Artifact、跨书范围、非法 revision 和超预算参数。
- Proposal、确认卡与日志不得展示或持久化 API Key、Authorization Header、Provider thinking 签名、内部文件绝对路径或 WebDAV 凭据。
- Trace 与诊断日志使用 `proposalId / commandId / workflowRunId` 关联，正文和用户原始要求默认脱敏或摘要化。
- 普通 Markdown、Mermaid、代码块、书籍正文中的伪 Tool Call 永远不能进入执行链。

---

## 12. Genkit 与运行时边界

Genkit 官方的 Interrupt/Resume 和 Tool Approval 是可选运行时实现，不是开卷产品协议本身。

```text
Genkit Tool Call / Interrupt
  → GenkitAgentRuntime adapter
  → AiActionProposal / App 等待态
  → AiProductActionController / Policy / Journal
  → AiAuthorizedCommand
  → App Workflow
```

- Genkit `toolApproval` 可以暂停未批准 Tool，但 App 仍须运行自己的 Policy、真实身份解析和 Command 签发。
- Resume 必须恢复原始 Proposal/Interrupt；不得手工伪造 Provider Tool Part 或让模型重新猜目标。
- Genkit Session/Snapshot 可以帮助恢复普通 Agent Run，但产品等待态和已授权命令必须能在没有 Genkit Session 时独立恢复。
- 当前锁定 `genkit 0.15.1` 的取消缺口未解除前，`GenkitAgentRuntime` 继续受运行时门禁限制；本协议先在兼容运行时落地。
- 注册表、能力门禁、通用 Workflow Adapter、领域 Artifact 与多层版本以 [ai-workflow-extension.md](./ai-workflow-extension.md) 为准；Genkit `Artifact` 不能替代它们。

背景参考：

- [Genkit Dart：Interrupts](https://genkit.dev/docs/dart/interrupts/)
- [Genkit Dart：Tool Approval Middleware](https://genkit.dev/docs/dart/middleware/)
- [OpenAI Agents SDK：Guardrails and human review](https://developers.openai.com/api/docs/guides/agents/guardrails-approvals)
- [LangChain：Human-in-the-loop](https://docs.langchain.com/oss/javascript/langchain/human-in-the-loop)

这些资料说明通用的 pause/approve/reject/resume 模式；作品范围、附件、Artifact 版本、WebDAV 和 Workflow 语义仍以开卷规范为准。

---

## 13. 可观察性与评测

每个阶段至少记录脱敏结构化事件：

```text
proposal.created
policy.allowed | policy.confirmation_required | policy.clarification_required | policy.denied
authorization.granted | authorization.rejected | authorization.expired
command.journaled
workflow.started | workflow.cancel_requested | workflow.completed | workflow.failed
artifact.committed
receipt.committed
late_event.quarantined
```

事件必须携带稳定 ID、状态版本、单调序号、动作类型、授权来源、范围指纹、延迟和公开错误码；不得记录 Key 或完整正文。

首阶段上线门槛：

- 否定、评价、教程、概念讨论、Mermaid 请求和附件普通问答评测中，错误产品执行数必须为 0。
- 任何未授权 Workflow 启动数必须为 0。
- 重复提交、重复 Artifact、旧 revision 覆盖必须为 0。
- 取消后 Artifact 提交必须为 0。
- 所有待确认、崩溃恢复、过期、拒绝和冲突路径都有稳定 UI 状态与测试。

---

## 14. 测试矩阵

### 14.1 纯单元测试

- Proposal schema、未知动作和别名拒绝。
- Policy 授权矩阵全覆盖。
- 状态机所有合法迁移与非法迁移拒绝。
- Command 不可变、submission 级幂等键、Journal attempt 和 revision compare-and-set。
- Journal 原子写入、终态唯一、晚到事件隔离。

### 14.2 语义评测

建立 200–300 条中文为主的最小对照集，至少覆盖：

- 创建 / 修订 / 评价 / 讨论 / 教程 / 否定 / 反问 / 假设 / 纠正。
- 有附件与无附件；单张与多张 Artifact。
- 当前章、当前作品、整本出版物、合集作品和不确定范围。
- “不用再生成”与“请再生成”、“再详细一点”与“解释得详细一点”等最小差异。
- DeepSeek 思考开关、OpenAI Compatible、Anthropic、Ollama 与自定义端点模型矩阵。

语义评测只评价 Proposal/普通回答/补充信息选择，不直接执行真实 Workflow。

### 14.3 集成与恢复测试

- Proposal → 确认 → Command → Workflow → Receipt 正常链路。
- 确认前杀进程，恢复同一等待卡片。
- Journal 成功、Workflow 启动前崩溃，恢复后安全重试。
- Artifact 已提交、Receipt 写入前崩溃，恢复后返回既有 Artifact，不重复生成。
- 并发修订同一 revision，只允许一个提交。
- 取消与 Provider 晚到结果；取消后不得持久化 Artifact。
- WebDAV 合并按稳定消息/Artifact 身份去重，不同步本地等待态。

### 14.4 Widget 测试

- 对话内确认、补充、拒绝、过期和恢复卡片。
- 附件只绑定目标；评价不修订，明确修改才出现 Proposal。
- 键盘与按钮重复提交只产生一个 Proposal。
- 屏幕阅读器能读出动作、范围、风险、按钮与状态变化；触控区符合 AI 面板规范。

---

## 15. 分阶段迁移

不得大爆炸替换当前对话和 Workflow。

### P0 — 规范与测试骨架

- 本规范成为权威控制协议。
- 为现有错误语义先补失败测试：否定、附件评价、歧义、重复提交、取消晚到、revision 冲突。
- 旧行为尚未迁移时，测试应明确标记为预期失败或单独目标套件，不得把文档目标误报为已实现。

### P1 — App 契约与 Policy

- 新增纯 Dart Proposal/Decision/Command/Receipt/Journal 状态契约。
- `AiRunProductActionRequested` 仅转换成 Proposal，不再直接代表可执行命令。
- 建立动作注册表和 Policy 矩阵；先接思维导图创建/修订。

### P2 — 对话内确认与附件语义

- 新增结构化确认/补充卡片。
- 自由输入产生的思维导图 Proposal 默认需要确认。
- “继续修改”附件改为目标绑定，不再把所有后续文字直送修订 Workflow。
- 快捷入口、范围卡片和失败重试走同一 Controller，但可按矩阵自动授权。

### P3 — Journal、幂等、版本与取消

- Workflow 前持久化 Command；加入安全恢复和 Receipt。
- 修订使用 expected revision；WebDAV 和会话附件按稳定身份合并。
- 取消进入 `cancelRequested`，等待真实静止并隔离晚到结果。

### P4 — 扩展产品动作

- 将整本翻译、写入笔记、导出和未来图谱对话入口逐项接入注册表。
- 按 [Workflow Extension Contract](./ai-workflow-extension.md) 落地 Action Definition、能力门禁、多层版本、Workflow Adapter、领域 Artifact 与 App-owned Receipt 投影。
- 每新增动作只增加注册定义、schema、Policy、Gateway、Workflow adapter 和领域产物实现，不增加自然语言关键词路由或通用 Controller switch。

### P5 — Genkit Agent 灰度

- 在相同协议和测试下验证 Genkit Interrupt/Resume、Session/Snapshot、Trace 和真实取消。
- 运行时门禁全部通过后，才允许 Genkit 替换普通对话工具循环；Product Action Protocol 不随 SDK 切换。

---

## 16. 完成标准

- [x] 模型思维导图 Tool Call 只产生 Proposal。
- [x] 任何生产 Workflow 都只接受有效 `AiAuthorizedCommand`。
- [x] 自由输入的思维导图动作具有对话内确认路径。
- [x] 思维导图附件只绑定目标，不隐式授权修订。
- [x] 快捷 UI、自由输入、重试和恢复全部走同一 Policy/Journal/Executor。
- [x] 幂等、revision 冲突、取消和晚到结果通过生产链与崩溃恢复测试。
- [x] 待确认与执行状态可以在 App 重启后恢复或明确放弃，且不会从头重复副作用。
- [x] 产品 Artifact 的概念边界与 Genkit Session/Artifact、Journal 控制态分离。
- [x] 新增动作经注册定义接入，缺失能力时不可执行；增加第二个测试 Workflow 不修改通用分发代码。
- [x] Action、Command、Workflow、Artifact、Prompt 和 Renderer 独立版本化并由注册定义实际传播。
- [ ] 语义评测中错误产品执行为 0，未授权 Workflow 启动为 0。
- [x] PRODUCT、ENGINEERING、ai.md 与各领域规格不再包含“模型调用或附件直接授权执行”的描述。

本轮证据：

- 提交顺序：Adapter 只写 Artifact/checkpoint 事件；对话投影在 Receipt 之后
  （`BookAiWorkspaceController.runMindMapProductAction`）
- 崩溃窗口：`artifact committed before checkpoint is recovered without regenerating`
- 谱系 head CAS：`two concurrent revisions of v1 only one becomes v2 head`
- 原 Command 重试：`prepareRetry reuses commandId and increments attempt`
- 第二 Workflow Tool Call 全链路：`test/ai_product_action_domain_test.dart`
- 投影幂等：`projection is idempotent for the same artifact id`
- 取消零 Artifact：`cancel after model return before commit leaves zero artifacts`

仍未完成：200–300 条真实模型语义评测；Chat Sheet 仍保留 mind-map 与
`AiRegisteredProductAction` 的 sealed 分支（新领域走 Registered，不再扩 switch）。
