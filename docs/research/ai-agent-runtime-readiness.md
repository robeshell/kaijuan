# AI Agent 运行时就绪性

> 日期：2026-08-11
> 当前结论：普通对话已经具备 App 自有 `AiAgentRuntime` 替换边界，但锁定的 Genkit Dart `0.15.1` 不满足生产切换条件；默认继续使用 `LegacyAiAgentRuntime`。

## 已完成

- `AiAgentRuntime` 冻结一次 turn 的书籍范围、历史、工具、联网结果、推理偏好和取消信号；UI 不依赖 Genkit 类型。
- `LegacyAiAgentRuntime` 保持现有原生 Function Calling、续写、取消和错误语义。
- `AiAgentRuntimeGate` 在运行时工厂之外逐项校验真实请求取消、Provider 矩阵、工具及 Interrupt/Resume、Trace/Snapshot 和统一契约测试；条件不足时确定性回退，并提供 blocker 列表。
- `tool/ai_runtime_harness.dart` 默认用进程内 OpenAI Compatible 伪端点覆盖读工具、产品行动、结构化导图、自动续写和 transport 取消；只有显式 BYOK 环境变量才访问真实端点，报告不含 Key、提示词、正文或原始回答。

## 当前阻塞证据

锁定依赖：

```text
genkit 0.15.1
genkit_openai 0.3.7
genkit_anthropic 0.2.11
```

`genkit-0.15.1/lib/src/ai/agents/agent.dart` 的 in-process transport 明确说明：attached turn 的 `CancellationToken` 尚未传入 `generate`；`abort` 只更新持久化 snapshot，不能停止正在进行的模型请求。该缺口违反开卷“停止必须中止底层 HTTP”的既有契约，因此不能用 UI 已显示 cancelled 作为替代验收。

当前工作环境也未安装 `genkit` CLI，无法在本轮产生 Agent Trace/Snapshot 证据。CLI 缺失不影响 App adapter 和离线 Harness 测试，但它是 Genkit Agent 发布门禁的一项未满足条件。

## 自动验证

```sh
flutter test test/ai_agent_runtime_gate_test.dart
flutter test test/ai_runtime_e2e_test.dart
flutter test tool/ai_runtime_harness.dart --reporter expanded
```

显式真实模型验证：

```sh
AI_HARNESS_MODE=live \
AI_HARNESS_PROVIDER=openai-compatible \
AI_HARNESS_BASE_URL=https://example.com/v1 \
AI_HARNESS_MODEL=model-id \
AI_HARNESS_API_KEY=... \
flutter test tool/ai_runtime_harness.dart --reporter expanded
```

Harness 不从 App Keychain 读取凭据。真实 BYOK 验证只能证明当前 App runtime/adapter 链路，不会把 Genkit Agent 的 attached cancellation 标记为已通过。

## 解除门禁的顺序

1. 升级到已把 attached `CancellationToken` 传入实际模型请求的 Genkit Dart 版本，并以可观察的服务端断连或请求中止证明，不只检查 App 终态。
2. 对 OpenAI Compatible、DeepSeek、Grok、自定义端点、Ollama 与 Anthropic 跑同一 Runtime 契约矩阵。
3. 验证只读工具、产品行动 interrupt、resume 后幂等、失败重试和 snapshot 回放。
4. 使用 Genkit CLI 留存脱敏 Trace ID，确认 tool、interrupt、resume、模型错误和取消 span。
5. 新增版本专属 `AiAgentRuntimeCapabilities` 记录并通过功能开关灰度；兼容 Runtime 与确定性产品 Workflow 继续保留。

在五项全部完成前，不实现一个“能编译但取消失真”的生产 `GenkitAgentRuntime`，也不勾选规格中的替换完成项。
