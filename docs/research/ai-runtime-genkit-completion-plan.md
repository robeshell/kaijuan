# AI 运行时 Genkit 完整收口计划

> 日期：2026-08-10
> 基线提交：`41d35817cae`（统一 `AiRun`、本书对话原生工具调用、OpenAI Compatible / Anthropic Genkit adapter）
> 目标：让词典、选区翻译、结构化大纲、知识图谱和连接测试全部依赖同一套 App 自有模型契约，删除旧 `AiProvider` 完成链路。

## 1. 当前事实

已经完成：

- 本书对话只依赖 `AiModelAdapter`，工具调用使用 OpenAI Compatible Function Calling 或 Anthropic Tool Use。
- `AiRunOrchestrator`、`AiRunEvent`、`AiRunState` 已覆盖对话、语言、大纲与图谱的状态、取消、预算、进度和 checkpoint。
- 两个 Genkit adapter 已隔离 SDK 类型并锁定版本；旧 `kaijuan_tools`、手写 Anthropic 对话 adapter 和 Provider 对话回退已删除。

尚未完成：

- 词典与翻译仍通过 `AiProvider.stream/complete` 生成普通文本。
- 结构化大纲与知识图谱仍通过提示词约定 JSON，再手工去 fence、`jsonDecode`、正则恢复或格式重试。
- 设置页同时暴露 `openProvider()` 与 `openModelAdapter()`；连接测试、模型列表和确定性 Workflow 仍维持第二套模型 transport。
- `OpenAiCompatibleAiProvider`、`AnthropicAiProvider`、`AiProviderFactory` 与 `AiRunTrackingProvider` 因上述调用仍无法删除。

这意味着运行状态已经统一，但模型 I/O 尚未统一。全量测试通过只证明当前行为稳定，不代表迁移结束。

## 2. 目标架构

```text
UI / controller
    ↓ 只消费 AiRunEvent / 调用业务命令
确定性 Workflow（语言 / 大纲 / 图谱）与受控 Tool Agent（对话）
    ↓ 只依赖 App 自有契约
AiModelAdapter + AiStructuredOutputAdapter
    ↓ 唯一供应商边界
Genkit OpenAI Compatible / Anthropic adapter

设置页模型列表 → AiModelCatalog（只读 HTTP catalog，不生成内容）
设置页连接测试 → AiModelAdapter 无工具单回合
```

不采用 Genkit Agent、Genkit session、远程 flow 或强制后端。开卷继续拥有任务路由、书籍/作品范围、工具权限、预算、取消、checkpoint、持久化、WebDAV 和 UI 状态。Genkit 只负责 Provider 归一化、流式传输、原生工具、结构化输出和 trace。

## 3. 迁移边界

本轮允许修改：

- 模型请求/响应契约、adapter 生命周期、结构化 schema、调用计数和供应商错误归一化。
- 词典/翻译、大纲/图谱服务的模型调用方式与对应测试替身。
- 设置页连接测试与模型列表基础设施。
- 迁移完成后删除没有调用者的旧 Provider、解析器、工厂和测试。

本轮不修改：

- 五个书内只读工具、四轮工具上限、作品冻结范围和正文预算。
- 翻译目标语言判断、系统词典/系统翻译 fallback、结果卡交互。
- 大纲的分批/覆盖/汇总策略及缓存模型。
- 图谱的分章、并发、稳定 ID、证据回填、共指消歧、关系方向、质量门、增量合并和 checkpoint 算法。
- Drift、会话 JSON、图谱缓存和 WebDAV schema。
- BYOK、本地 Ollama、五端与无强制后端原则。

## 4. 分阶段执行

### P1 — 统一工作流模型会话与 schema 基础

实施：

- 为确定性 Workflow 建立只依赖 `AiModelAdapter` 的运行会话包装：每个 run 打开一个 adapter，所有模型调用计入 `AiRunExecution.modelStarted`，在成功、失败、取消时统一 `close()`。
- 保持 `AiModelTurnRequest` 作为普通文本生成契约，保持 `AiStructuredOutputAdapter.completeJson` 作为结构化生成契约；不把 Genkit 类型暴露到服务层。
- 新增集中式 Schemantic schema 模型与 `schemantic_builder`；生成文件进入正常代码生成流程。
- 明确 schema 校验与业务语义校验两层：前者保证字段/类型，后者继续验证批次覆盖、稳定 ID、证据和范围。

验收：

- adapter 生命周期、调用计数、取消关闭和异常关闭都有纯 Dart 单测。
- OpenAI Compatible 与 Anthropic 对同一结构化 schema 返回一致的 App 自有结果。
- `flutter analyze` 无新增 warning。

### P2 — 词典与选区翻译

实施：

- `AiLanguageService` 改用无工具 `streamTurn`，由文本 delta 形成现有回答快照。
- 正常完成、长度截断、EOF/异常、首字前重试和取消统一采用 adapter 语义。
- 保留同语言短路、目标语言偏好、系统能力 fallback、复制/写笔记完成门槛。
- 删除语言服务对 `AiProvider`、`completeWithRetry` 和 tracking provider 的依赖。

验收：

- 字典、简繁/中英翻译、空输出、截断、取消、首字后失败保留部分文本全部有测试。
- 两类本地伪服务协议测试至少各覆盖一次流式语言请求。

### P3 — 结构化大纲

实施：

- 为批次摘要和最终 reduce 分别定义 Schemantic schema。
- `_summarizeBatch`、`_reduceSummaries` 改用 `completeJson`。
- 保留批次隔离、全书跨度、缩小批次重试、全部 batch ID 覆盖和最终 3–10 单元语义校验。
- 删除 fence 截取、宽松 `jsonDecode`、格式修复提示词和只为伪 JSON 存在的解析重试。

验收：

- 第一次结构化响应即可通过 schema；缺 batch、重复 batch、空单元等仍由业务校验拒绝。
- 回归长书、分段单本、取消、缩小批次重试和缓存序列化测试。

### P4 — 知识图谱全部模型步骤

按风险从小到大迁移，每一步完成后运行图谱专项测试：

1. 叙事展示计划与描述润色。
2. 模糊实体合并、共指和关系方向审查。
3. 缺失类型 gleaning 与章节实体/关系抽取主链。

每类输出建立独立 Schemantic schema，不使用一个无限宽的“万能图谱 JSON”。迁移只替换模型 I/O；现有证据回填、稳定 ID、别名融合、关系去重、亲缘方向、质量门和 checkpoint 保持原实现。

删除：

- 图谱模型响应的 fence/包装剥离。
- 正则提取 JSON 数组/对象的恢复路径。
- 通过提示词反复要求“只输出可 jsonDecode JSON”的格式补丁。

验收：

- 现有图谱、合成书、家族树、范围、缓存和 WebDAV 相关测试全部保持通过。
- 新增 schema 缺字段、错误枚举、未知实体端点、不完整证据、取消与单章失败 checkpoint 测试。

### P5 — 设置基础设施拆分与旧代码删除

实施：

- 提取 `AiModelCatalog`，只负责 OpenAI Compatible / Anthropic `/models` 查询、取消和错误映射；不提供生成接口。
- 设置页连接测试通过 `AiModelAdapter` 发起短的无工具单回合并立即关闭。
- controller 只暴露 `openModelAdapter()` 与 model catalog；删除 `openProvider()`。
- 全仓确认无调用者后删除：
  - `AiProvider` / `AiProviderFactory`
  - `OpenAiCompatibleAiProvider` / `AnthropicAiProvider`
  - `AiRunTrackingProvider`
  - `completeWithRetry` / `streamWithRetryBeforeFirstText` 等只属于旧 transport 的帮助代码
  - 对应旧 completion/stream 测试与文档表述

不删除 App 自有 `AiModelAdapter`，也不把模型目录请求塞进 Genkit adapter；目录是只读控制面，生成是模型数据面。

验收：

- `rg` 不再出现业务层 `AiProvider`、旧 JSON fence parser 或旧 completion transport。
- 总开关关闭时模型列表之外的生成入口不发请求；本地 Ollama 无 Key 仍可连接和生成。
- OpenAI、DeepSeek、Grok、自定义、Ollama、Anthropic 工厂路由测试通过。

### P6 — 审计与完整验证

自动验证：

```sh
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/ai_language_service_test.dart
flutter test test/ai_outline_test.dart
flutter test test/ai_graph_service_test.dart test/ai_graph_synthetic_book_test.dart
flutter test test/genkit_openai_model_adapter_test.dart test/anthropic_model_adapter_test.dart
flutter test
```

Genkit trace smoke（可选真实 Key，不进入默认测试，不记录 Key）：

- 提供 `tool/ai_genkit_smoke.dart`，注册一次性 flow，分别覆盖纯文本和结构化输出。
- 使用 `npx genkit-cli flow:run ... -- dart run tool/ai_genkit_smoke.dart`，检查 trace 中的模型、schema、流式终态和错误；不启动常驻服务。
- OpenAI Compatible 与 Anthropic 至少各保留一份脱敏的执行结论，不提交 prompt 正文、书籍正文或凭据。

人工测试矩阵：

- 设置：五类云端/自定义路由、Anthropic、Ollama；获取模型、测试连接、错误 Key、停止。
- 语言：词典、翻译、切换目标语言、同语言短路、生成中关闭。
- 对话：直接回答、每个书内工具、连续工具、自动续写、停止/关闭一次生效。
- 大纲：短书、长书、合集作品范围、第一次生成。
- 图谱：初次生成、取消后续跑、已有 checkpoint 增量、范围排除、家族树。

## 5. 提交策略与完成定义

建议保持可回滚的小提交：

1. `refactor(ai): add workflow model session and schemantic schemas`
2. `refactor(ai): move language workflows to model adapters`
3. `refactor(ai): use structured output for outlines`
4. `refactor(ai): use structured output for graph generation`
5. `refactor(ai): remove legacy provider completion transports`
6. `test(ai): add genkit traces and full migration coverage`

每个提交必须通过对应专项测试和 `flutter analyze`。最终完成同时满足：

- 所有生成能力只通过 `AiModelAdapter` / `AiStructuredOutputAdapter`。
- 业务层没有 Genkit、Schemantic、供应商 SDK 类型。
- 不存在旧 Provider 完成链路、fenced 工具协议、提示词伪结构化输出或跨协议回退。
- 现有产品范围、缓存、WebDAV、安全边界和人工测试矩阵通过。
- 完整 `flutter test` 通过后，再从干净安装开始端到端人工测试。
