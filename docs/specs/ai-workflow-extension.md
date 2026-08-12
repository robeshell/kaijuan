# AI Workflow 扩展契约（Workflow Extension Contract v1）

| | |
|--|--|
| **状态** | v1 通用契约骨架已建立；生产恢复、Artifact repository 与无中心改动扩展仍在迁移 |
| **日期** | 2026-08-12 |
| **产品动作控制** | [ai-product-actions.md](./ai-product-actions.md) |
| **AI 总规范** | [ai.md](./ai.md) |
| **工程** | [ENGINEERING.md](../ENGINEERING.md)「AI 边界」 |
| **参考领域** | [ai-mind-map.md](./ai-mind-map.md)、[ai-translation.md](./ai-translation.md)、[ai-graph.md](./ai-graph.md) |

> 本规范定义“一个新的 AI 产品 Workflow 如何接入开卷”。它不决定用户是否已经授权执行；授权以 Product Action Protocol 为准。它也不规定某个领域如何写提示词或生成内容；领域规格仍是内容语义权威。

---

## 1. 结论

新增思维导图、整本翻译、知识库导出或未来演示文稿能力时，不得复制一套聊天路由，也不得把模型 Tool Call 直接接到业务 Service。所有可执行能力统一注册为 `AiProductActionDefinition`，经同一个控制平面签发 Command，再由对应 `AiWorkflowAdapter` 执行并提交类型化 Artifact 与 Receipt。

```text
AiAgentRuntime / 明确 UI 入口
  → AiActionProposal
  → AiProductActionController
  → ProductActionRegistry
      └─ AiProductActionDefinition
           ├─ schema + versions
           ├─ Policy metadata
           ├─ capability requirements
           ├─ Domain ActionGateway
           ├─ AiWorkflowAdapter
           └─ Artifact definition
  → AiAuthorizedCommand
  → AiWorkflowAdapter
  → Domain Artifact commit
  → AiActionReceipt
  → App-owned result projection
```

框架替换不改变这条链：Genkit、兼容 Runtime 或未来远端 Agent 只负责把模型输出投影为 Proposal；Workflow 注册、授权、执行事实和产品产物始终属于开卷。

---

## 2. 适用范围与非目标

### 2.1 适用范围

以下能力必须使用本契约：

- 创建或修订领域 Artifact；
- 启动可取消、可恢复或有预算的后台任务；
- 写入 App 数据库、文件、WebDAV 或外部系统；
- 执行导出、分享、覆盖、删除等产品动作；
- 需要由 Receipt 证明成功、部分成功、失败或取消的操作。

只读目录、章节正文、书内搜索和取样仍属于 Read Tool，不注册为 Product Action，但继续受冻结范围、预算、取消和注入防护约束。

### 2.2 非目标

- 不建立自然语言关键词路由表；
- 不要求每个 Workflow 使用 Genkit `defineFlow` 或 Agent；
- 不把所有 Workflow 改造成动态流程图或通用脚本语言；
- 不让一个通用 `Map<String, dynamic>` 取代领域模型；
- 不承诺模型永不误解用户，只保证误解不会绕过 Policy 产生未授权副作用；
- 不把未来参考场景自动加入产品路线图。

---

## 3. 注册定义

### 3.1 `AiProductActionDefinition`

每个动作必须以编译期注册的不可变定义接入：

```text
actionKind                 # 全局唯一、稳定，如 create_book_mind_map
definitionVersion          # 注册定义版本
proposalSchemaVersion      # 模型/显式入口提交的参数版本
commandSchemaVersion       # Gateway 解析后的命令参数版本
workflowVersion            # 执行语义版本
artifactKind?              # 成功时产生的领域 Artifact 类型
artifactSchemaVersion?     # Artifact 数据结构版本
displayMetadata            # 本地化名称、图标语义、确认文案键
riskClass                  # read | reversible | external | destructive
supportedProposalSources   # modelTool | explicitUi
supportedScopes            # section | work | publication | selectedUnits ...
requiredCapabilities       # 模型、设备、网络、存储与外部服务能力
retryPolicy                # 是否可重试、哪些终态可重试、attempt 上限
argumentSchema             # 严格、封闭的输入 schema
gateway                    # 临时别名和参数 → 真实身份与冻结参数
policyDescriptor           # Policy 所需元数据，不包含决策代码副作用
workflowAdapter            # 执行、恢复、取消和观察入口
artifactDefinition?        # 校验、提交、投影、同步和渲染入口
```

约束：

- `actionKind` 不得复用、动态拼接或按语言变化；删除动作后也不得把同名分配给新语义。
- Schema 默认拒绝未知字段；模型不能借自由参数传数据库 ID、路径、凭据或未注册子动作。
- 注册表启动时必须检查重复 action kind、重复工具名，以及同一 Artifact kind 的不兼容定义/版本声明；冲突时禁用相关动作并报告诊断，不得后注册覆盖前注册。创建和修订动作可以显式共享同一个 Artifact definition。
- UI 文案、图标和卡片渲染使用本地资源键，不接受模型提供的任意 Widget 或 HTML。
- 一个领域可注册多个动作，例如创建、修订、导出；不得用一个万能 `manage_artifact` 在 Workflow 内重新猜意图。

### 3.2 注册表职责

`ProductActionRegistry` 只提供定义发现和静态校验，不决定授权、不读实时阅读位置、不执行 Workflow：

```text
lookup(actionKind)
listAvailable(frozenContext, runtimeCapabilities)
validateDefinitionSet()
buildToolDescriptors(availableDefinitions, temporaryAliases)
```

Agent 每轮只看到 `listAvailable` 返回的最小工具集合。未满足能力、作用域或产品开关的动作不得暴露给模型；明确 UI 入口遇到不可用动作时也必须给出确定性原因，不能退回自由聊天假装完成。

工具描述由注册定义生成，不能在 Agent prompt、Runtime adapter 和 Controller 中分别维护三份 schema。Provider 特有格式转换只能发生在 `AiAgentRuntime` 内部。

---

## 4. 能力发现与门禁

### 4.1 能力不是 Provider 名称

Workflow 声明所需能力，不直接判断 `provider == OpenAI` 或模型名称：

```text
AiCapabilitySet
  model:
    structuredOutput
    nativeToolCalling
    longContext
    imageInput
    imageGeneration
    maxInputTokens
    maxOutputTokens
  runtime:
    trueTransportCancellation
    resumableAgentState
    tracing
  device:
    localFileWrite
    presentationRendering
    availableMemoryClass
  services:
    webSearch
    externalAssetFetch
  storage:
    journal
    checkpoint
    artifactRepository
    webdavSnapshot
```

`AiCapabilityResolver` 根据当前 Runtime、Provider、模型、平台、设置和依赖构造能力快照。快照随 Proposal 冻结，preflight 时重新核验易变能力。

### 4.2 门禁结果

动作定义可以声明：

- `required`：缺失即不可开始；
- `optional`：缺失时使用领域明确规定的降级；
- `oneOf`：若干受支持策略满足其一即可；
- 预算范围：输入、输出、阶段次数、外部调用和本地资源上限。

降级必须在领域规格中显式定义。例如演示文稿没有图像生成能力时可以只生成视觉建议和占位，不得悄悄调用未授权的外部图片服务。

---

## 5. Workflow 执行契约

### 5.1 `AiWorkflowAdapter`

所有领域 Workflow 对控制平面暴露同一组语义操作；实现可以是本地 Dart Service、Genkit structured output、远端服务或组合，但不得泄漏具体框架类型：

```text
preflight(AiAuthorizedCommand, AiWorkflowEnvironment)
  → AiWorkflowPreflightResult

start(AiAuthorizedCommand, AiWorkflowRunContext)
  → Stream<AiWorkflowEvent>

recover(AiWorkflowRecoveryRequest)
  → Stream<AiWorkflowEvent>

requestCancel(workflowRunId, cancellationReason)
  → AiWorkflowCancelAck

inspect(workflowRunId)
  → AiWorkflowInspection
```

`start` 不直接向 UI 返回任意模型文字。它发布类型化事件，由领域 Controller/reducer 投影为进度、预览、等待、错误和终态。

### 5.2 环境与输入

Workflow 只能读取：

- 不可变 `AiAuthorizedCommand`；
- Command 引用的冻结正文/结构快照；
- 已批准的设置、预算和能力快照；
- App 注入的模型 Session、取消信号、clock、ID 生成器、checkpoint 与领域 repository。

Workflow 不得读取当前翻页位置、composer 内容、未冻结附件或全局最近 Artifact 来补齐目标。缺失输入在 preflight 失败，不得猜测回退。

### 5.3 事件与 checkpoint

通用事件至少包括：

```text
accepted
stageStarted(stageId, stageVersion)
progress(current, total, unit, messageKey)
checkpointCommitted(checkpointId, stageId)
previewAvailable(previewRef)
usageUpdated(usage)
cancelAcknowledged
artifactReady(stagedArtifactRef)
succeeded(receiptDraft)
partiallySucceeded(receiptDraft)
failed(publicErrorCode, diagnosticRef)
cancelled
```

- 事件使用稳定 `workflowRunId`、单调 sequence 和 attempt，可幂等重放。
- checkpoint payload 由领域 Workflow 版本化，不写入聊天消息，也不使用 Genkit Snapshot 代替。
- 恢复只能从已提交 checkpoint 开始；Workflow 升级不能读取旧 checkpoint 时必须明确 `abandoned` 或运行注册的迁移器，不得静默从头重复副作用。
- `cancelRequested` 后仍可收到 Provider 晚到结果，但不得进入 Artifact 提交阶段。

### 5.4 确定性边界

“确定性 Workflow”不表示模型输出确定，而表示以下控制由代码确定：

- 冻结输入、阶段顺序和最大重试次数；
- 每阶段 schema、校验与停止条件；
- 预算、取消、checkpoint 和提交顺序；
- Artifact 身份、revision 与 Receipt；
- 是否允许降级、部分成功或恢复。

模型可以在某一受限阶段生成内容，但不能自由添加阶段、改写作用域、跳过授权、宣布提交成功或选择未注册外部副作用。

---

## 6. 版本模型

`protocolVersion` 只说明 Product Action 信封版本，不能代替领域版本。每条链至少区分：

| 版本 | 负责内容 | 兼容要求 |
|------|----------|----------|
| `protocolVersion` | Proposal/Decision/Command/Receipt 外层协议 | 控制平面读取 |
| `definitionVersion` | 注册元数据和能力要求 | 注册表校验 |
| `proposalSchemaVersion` | Tool/UI 原始参数 | Gateway 解析或拒绝 |
| `commandSchemaVersion` | Workflow 输入参数 | Workflow 必须明确支持 |
| `workflowVersion` | 阶段、checkpoint 和执行语义 | 恢复与诊断使用 |
| `artifactSchemaVersion` | 领域产物结构 | repository/renderer 迁移 |
| `promptVersion` | 内容生成提示词 | 质量追踪，不决定数据兼容 |
| `rendererVersion` | PNG/PPTX/Markdown 等派生渲染 | 可重新生成，不改变内容 revision |

规则：

- Command 固化执行时的 `definitionVersion + commandSchemaVersion + workflowVersion`。
- Artifact 固化 `artifactSchemaVersion`，并记录实际 Workflow/prompt 版本供诊断。
- 只改布局 renderer 不创建内容 revision；修改结构化内容必须产生新 revision。
- 新代码可以读取旧 Artifact，但不得用新 Workflow 恢复语义不兼容的旧 checkpoint。

---

## 7. Artifact 契约

### 7.1 通用信封

领域 Artifact 保留强类型 payload，并共享最小信封：

```text
artifactId
artifactKind
artifactSchemaVersion
revision
sourceArtifactId?
lineageRootId
contentHash / workKey?
scopeFingerprint
sourceSectionRefs[]
createdByCommandId
createdByWorkflowRunId
workflowVersion / promptVersion?
contentRef
previewRefs[]
createdAt / updatedAt
```

- `contentRef` 指向领域 repository 中的强类型内容，不把所有产物塞进一个 JSON 字段。
- Artifact 只有 repository compare-and-set 成功后才可进入 Receipt。
- Genkit session Artifact 只能作为运行时临时数据或流式预览，不能成为正式 `artifactId`、revision、WebDAV 或数据库事实源。
- 对话消息只保存稳定 Artifact 引用和显示快照，不内嵌大型二进制。

### 7.2 派生文件

PNG、PPTX、Markdown、压缩包等是 Artifact 的派生文件：

- 文件写入先使用临时路径，校验成功后原子提交；
- Journal 只保存引用、hash、大小和公开状态，不保存大文件内容；
- 导出到用户选择的位置属于独立外部写入动作；
- WebDAV 是否同步结构化 Artifact、派生文件或二者，由领域规格明确；大型二进制不得默认塞进聊天会话快照。

---

## 8. 幂等与提交

幂等键必须绑定一次可信提交身份，而不是只对规范化内容、范围和参数做 hash：

```text
idempotencyKey = stableKey(
  authorizationSubmissionId,
  resolvedActionKind,
  frozenScopeFingerprint,
  targetArtifactId?,
  expectedRevision?
)
```

因此：

- 同一确认/按钮事件因网络或平台重复回调，只执行一次；
- 失败后的安全重试复用原键并递增 attempt；
- 用户稍后再次明确点击“再生成一份”，获得新的 submission id，可以产生第二个 Artifact；
- 两次参数完全相同不等于同一个用户意图，不能被永久去重；
- 修订仍以 `targetArtifactId + expectedRevision` compare-and-set 防止覆盖。

失败重试和崩溃恢复引用既有 Command/Journal，不创建新 Proposal，也不重新让模型解释原始要求。用户若同时改变页数、范围、目标或其他业务参数，则不再是重试，必须重新走 Proposal、Policy 与授权。

提交顺序固定为：

```text
Command journaled
  → staged Artifact validated
  → repository compare-and-set / atomic commit
  → Receipt committed
  → conversation attachment/result projection
```

崩溃恢复时必须依据 Journal 和 repository 判断结果，不能重新询问模型“刚才是否成功”。

---

## 9. 成功、失败与对话投影

模型正文不能充当执行结果。产品消息由 App 根据 Receipt 确定性生成：

| Receipt | App 投影 |
|---------|----------|
| `succeeded` | 显示正式 Artifact 卡片与本地化成功文案 |
| `partiallySucceeded` | 显示已完成范围、未完成范围和可恢复动作 |
| `failed` | 显示公开错误、重试或调整入口，不附加伪 Artifact |
| `cancelled` | 显示已取消；晚到结果不可复活该任务 |
| `abandoned` | 显示无法安全恢复及原因，不自动重跑副作用 |

Agent 可以在执行前解释计划，也可以在 Receipt 之后基于正式 Artifact 回答问题；不得在 Receipt 之前说“已经生成/保存/导出”。协议修复最多用于撤回错误模型承诺，不得把文字承诺转换成授权或伪成功。

---

## 10. 新增 Workflow 的固定步骤

1. 在 PRODUCT 中声明产品价值、状态、入口和非目标；未立项的参考场景不得写成能力承诺。
2. 新建或更新领域 spec，定义范围、输入、结构化模型、交互、存储与质量验收。
3. 注册一个或多个明确 `actionKind`，定义封闭 schema、风险和能力要求。
4. 实现 Domain ActionGateway，把临时别名解析成冻结真实身份，不做授权和生成。
5. 在 Policy 矩阵登记显式 UI、自由输入、重试、外部写入和破坏性路径。
6. 实现 `AiWorkflowAdapter`、领域 checkpoint、Artifact repository 和 renderer/exporter。
7. 接入 Journal、Receipt 和 App-owned 结果投影；先验证失败、取消、崩溃与重复提交。
8. 增加语义最小对、契约、集成、恢复、Widget、真实 Provider 和性能边界测试后再开放工具。

新增动作不得要求修改通用 Controller 的 `switch(actionKind)` 主链。分发由注册定义完成；通用代码只认识协议接口和状态。

---

## 11. PPT/演示文稿参考场景（非当前产品承诺）

本节用于证明契约可以承接与思维导图不同的多阶段产物，不表示开卷已经决定交付 PPT。

### 11.1 动作拆分

```text
create_book_presentation    # 创建结构化演示文稿 Artifact
revise_book_presentation    # 基于 revision 修订
export_book_presentation    # 从正式 Artifact 派生并写出 PPTX
```

创建与导出必须拆开：生成本地可预览 Artifact 属于可逆产品动作；写入用户目录、分享或覆盖已有文件属于外部写入，使用独立授权和系统保存面板。

### 11.2 建议领域模型

```text
AiBookPresentation
  presentationId / revision
  title / subtitle?
  audience / purpose / tone
  themeRef
  sourceScope
  slides[]
    slideId / order
    role                 # cover | agenda | section | content | comparison | close
    title
    keyMessage
    bullets[]
    speakerNotes?
    evidenceRefs[]
    visualSpec?
    assetRefs[]
  sourceIndex[]
  validationSummary
```

模型返回结构化演示内容，不返回 PPTX 二进制，也不把 Markdown 标题列表冒充正式演示文稿。PPTX 由确定性 renderer 根据结构、主题 token 和素材引用生成。

### 11.3 Workflow 阶段

```text
scope preflight
  → source planning
  → narrative/slide plan
  → per-slide structured generation
  → evidence and duplication validation
  → optional approved asset generation
  → local preview render
  → Artifact commit
  → Receipt
```

每个阶段有固定预算、checkpoint 和重试上限。整本书过长时由开卷确定性分段与汇总，模型不能自行漏章后声称覆盖全书。

### 11.4 能力与降级

- `structuredOutput`、artifact repository 和 presentation preview renderer 为 required。
- long context 可以由确定性分段策略替代，但替代方案必须进入 `oneOf`。
- image generation 为 optional；缺失时只保存视觉建议或使用本地允许素材。
- PPTX renderer 缺失时可以创建可预览 Artifact，但不得暴露“导出 PPTX”动作。
- 外部图片搜索、下载和图片生成需要在确认卡显示来源、成本和网络行为。

### 11.5 对话语义最小对

| 用户输入 | 期望 |
|----------|------|
| “给这本书做一份 12 页的 PPT” | 创建 Proposal，确认范围、受众、页数、风格后执行 |
| “PPT 一般怎么做？” | 普通回答，不产生 Proposal |
| “把刚才总结整理成演示提纲” | 若用户只要文字提纲则普通回答；是否创建文件不清楚时补充 |
| “别做 PPT，只总结一下” | 普通总结，不产生 Proposal |
| 附件 + “第三页换个例子” | 指向该演示 Artifact 的修订 Proposal |
| “导出刚才的 PPT” | 对正式 Artifact 提出 export Proposal；目标不明确时选择，不猜最近文件 |

### 11.6 不会串到思维导图的原因

- `create_book_mind_map` 与 `create_book_presentation` 是两个封闭 schema 的工具；
- 每轮工具集合按能力和上下文最小暴露；
- 模型只提出 Proposal，确认卡展示解析后的真实动作和目标；
- Workflow 分发由注册表的明确 `actionKind` 决定，不由标题、关键词或模型回复正文决定；
- 成功卡片只根据对应 Artifact kind 与 Receipt 渲染；PPT Workflow 无法提交 `AiBookMindMap`。

这不能保证模型永不选错工具，但能保证选错时不会静默执行：自由输入首阶段需要确认，显式 PPT 按钮则直接构造 PPT Proposal，不经过语义路由。

---

## 12. 测试与上线门槛

### 12.1 注册与契约测试

- action/tool/Artifact kind 唯一；未知字段和未知版本拒绝；
- 注册定义生成的 Tool schema 与 Gateway schema 一致；
- 缺失 required capability 时动作不可见且不可通过显式入口绕过；
- 任意 Workflow 只能接受 Journal 中有效、未终结的 Command；
- 通用 Controller 在增加测试动作后无需修改分发代码。

### 12.2 生命周期测试

- preflight 失败不启动模型、不写 Artifact；
- 每阶段 checkpoint 可恢复，版本不兼容时明确 abandoned；
- 重试复用原 idempotency key，新的明确生成使用新 submission id；
- 取消后不提交 staged Artifact，晚到事件被隔离；
- Artifact 提交成功但 Receipt 写入前崩溃时，恢复返回既有 Artifact 并补 Receipt；
- compare-and-set 冲突不覆盖新 revision。

### 12.3 语义与 UI 测试

- 每个动作至少覆盖创建、修订、教程问答、否定、歧义、错误附件和跨书目标最小对；
- 确认卡展示动作、范围、目标、外部写入和费用/网络提示；
- 模型错误承诺不会显示正式成功卡；
- Receipt 五类终态均有稳定本地化投影；
- 新增动作后，既有思维导图、普通 Mermaid 和普通聊天回归集保持通过。

### 12.4 Provider 与性能测试

- 伪 Provider 覆盖格式错误、截断、重试、取消和晚到结果；
- 受支持的 BYOK Provider 至少验证 structured output、工具请求和 token 上限；
- 大书、多阶段与大型 Artifact 有内存、耗时、磁盘和输出文件大小边界；
- Trace 可以关联 proposalId、commandId、workflowRunId、artifactId，但不记录完整正文和凭据。

---

## 13. 与 Agent/Workflow 框架的边界

- Genkit Agent/Interrupt 可以实现模型回合、等待与恢复，但不能替代注册表、Policy、Command、Journal、领域 Artifact 和 Receipt。
- Genkit session Artifact 是会话状态，不是正式产品 Artifact；正式产物必须提交到 App repository。
- LangGraph 或其他远端编排器未来可以实现某个 `AiWorkflowAdapter`，但仍须遵守同一 Command、事件、取消和提交协议。
- Temporal 等耐久执行引擎未来可以承载跨设备、跨服务长任务，但不会取代 Provider adapter、领域校验或用户授权。
- 框架迁移只替换 Runtime/Adapter，不改变 Flutter UI、数据库与 WebDAV 的产品事实格式。

背景资料：

- [Genkit Dart：Interrupts](https://genkit.dev/docs/dart/interrupts/)
- [OpenAI Agents SDK：Guardrails and human review](https://developers.openai.com/api/docs/guides/agents/guardrails-approvals)
- [LangGraph：Overview](https://docs.langchain.com/oss/python/langgraph/overview)
- [Temporal：Durable execution](https://docs.temporal.io/)

---

## 14. 完成标准

- [x] `AiProductActionDefinition`、注册表冲突校验和动态工具目录骨架落地。
- [x] 能力快照与 required/optional/oneOf 门禁在目录和 Controller 两侧一致生效。
- [x] 通用 `AiWorkflowAdapter` 的事件、检查点、取消和恢复语义在生产 Workflow 落地。
- [x] Action/Command/Workflow/Artifact/Prompt/Renderer 版本彼此独立并实际传播。
- [x] Artifact 强类型 payload、持久化原子提交、派生文件和 WebDAV 边界落地。
- [x] 幂等键绑定可信 submission，既防重复回调又允许用户再次生成。
- [x] 所有生产成功/失败文案由 Receipt 和 App 投影产生，模型不能伪造成功。
- [x] 增加第二个测试 Workflow 不修改通用 Controller、工具解析和 Widget 分发代码。
- [ ] PPT 参考场景的语义最小对、能力降级和多阶段恢复由可执行契约测试证明。
- [x] Genkit/Legacy/未来远端 Runtime 切换不改变产品动作与 Artifact 契约。

当前证据：`lib/ai/ai_workflow_contract.dart`、`lib/ai/ai_workflow_executor.dart`、
`AiBookMindMapWorkflowAdapter`、`JsonAi*Store`、
`AiTestBookExportWorkflowAdapter` 与对应测试。派生文件 PNG 导出仍由既有思维导图
renderer 负责，不经通用 Artifact envelope 写二进制。PPT 仍是协议参考场景，
没有虚构为已交付的产品能力。
