# 本书 AI 对话：AnxReader 对照

| | |
|--|--|
| **状态** | 对比完成（2026-08-04）；待开卷落地项见 §7 |
| **参考基线** | [`Anxcye/anx-reader`](https://github.com/Anxcye/anx-reader) commit `107f4fa74db0e7247c846c49d6211df3edf9887c`（2026-05-29），MIT。本地浅克隆于 `/tmp/anx-reader`。 |
| **相关** | [ai.md](../specs/ai.md)、[PRODUCT §6](../PRODUCT.md)、[foliate-architecture.md](./foliate-architecture.md) |

> 只写对话（M2）的对照；翻译/词典/大纲不在本文范围。开卷产品结论以 [ai.md](../specs/ai.md) 为准，本页是研究基线 + 差距清单。文中的开卷 fenced-JSON 架构是历史对比基线；当前实现已经迁移到 App 自有编排器、隔离 Genkit adapter 与原生 Function Calling。

---

## 1. 结论（先读）

AnxReader 的对话是**全局 AI 助手 + 阅读内嵌面板**，同一个 `AiChatStream` 组件复用三处（全局 Tab / 阅读器侧栏或弹出 / 设置测试），跑 **LangChain ReAct agent**，15 个工具，并把思考流与工具步骤实时渲染成时间线。

开卷的对话是**围着一本书的伴侣**，自研轻量 fenced-JSON 协议，5 个书内工具，不引入 LangChain；按 contentHash 隔离会话。

两条路线对各自产品定位都成立。**AnxReader 强在工程完整性（思考流可见、多 Key 轮换、限流、可编辑 prompt、工具可配）；开卷强在轻量、种子注入省轮次、联网两段式防幻觉、contentHash 会话语义。** 差距集中在工程体验，而非协议方向。

---

## 2. 各自架构

### 2.1 AnxReader

```text
UI 复用同一 AiChatStream：
  全局 Tab（home_page） / 阅读器侧栏或 bottom sheet / 设置测试页
        │
        ▼
Riverpod AiChat（keepAlive，全局共享同一会话）
        │  sendMessageStream → 先落 draft(completed:false) → 流式
        ▼
aiGenerateStream(useAgent: true)                      [lib/service/ai/index.dart]
        │  RPM 限流 → 选 provider（AiKeyRotator 轮换 key）
        ▼
LangchainAiRegistry.resolveByProtocol(openai/anthropic/google)   →  ChatOpenAI / ChatAnthropic / ChatGoogleGenerativeAI
        │  动态拼系统 prompt（isReading 角色 + 工具目录 + 语言）
        ▼
CancelableLangchainRunner.streamAgent                 [lib/service/ai/langchain_runner.dart]
        │  ReAct：ToolsAgentOutputParser 解析 toolCalls；maxIterations=120
        │  思考/回复/工具步骤 → base64 时间线信封 <think-block>/<reply>/<tool-step>
        ▼
AI 前端解析时间线：思考折叠面板 + 每个工具一张 tile + markdown 回复
```

工具注册表 `AiToolRegistry`（15 个，可在设置开关）：

| 书内（isReading 时优先） | 全局 |
|--------------------------|------|
| `current_reading_metadata` | `calculator` / `current_time` |
| `current_book_toc` | `bookshelf_lookup` / `bookshelf_organize` |
| `current_chapter_content` | `notes_search` / `reading_history` |
| `chapter_content_by_href` | `tags_list` / `books_tags_list` / `apply_book_tags` |
| `book_content_search` | `mindmap_draw` |

每个工具 = `RepositoryTool`（name / description / inputJsonSchema / timeout）+ 仓储层；结果统一 JSON 信封 `{status, name, data}` 或 `{status, name, message}`。书内搜索用 **headless WebView 跑 foliate-js** 搜真实渲染文本（15s 超时、3min session 复用）。

### 2.2 开卷

```text
阅读器 chrome / 选区菜单 → showBookAiChatSheet
        │  showAppAdaptivePanel：compact 底 sheet / 中宽右侧栏
        ▼
_BookAiChatSheet（面板内状态；会话按 contentHash 落盘 ai_chat/）
        │  联网开关（可选 web hits）→ loadAiChatContext（章+选区+TOC）
        ▼
BookReaderController.streamBookChat → AiChatService.streamReply     [lib/ai/ai_chat_service.dart]
        │  种子 prompt：书名/作者/当前章(截1w)/选区(截4k)/目录标题列表 + 工具目录
        │  ≤4 轮 tool 往返 → 最后流式正文
        ▼
AiChatTools 协议：模型输出 fenced JSON
  ```kaijuan_tools
  [{"name":"search_book","query":"张居正"}]
  ```
_BookChatToolHost（5 个）：get_toc / get_current_chapter / get_chapter / search_book / sample_book
        │  正文来自 spine 抽取纯文本缓存 + AiChatRetrieve 关键词切片
        ▼
流式 markdown（AiResultBody）渲染，无思考/工具时间线
```

---

## 3. 逐维度对比

| 维度 | AnxReader | 开卷（现状） | 差距/影响 |
|------|-----------|--------------|-----------|
| **定位** | 全局助手 + 阅读内嵌，同一会话共享 | 仅阅读器内、按书隔离 | 产品决策不同；开卷 spec 明确不做全局 Tab |
| **Agent 框架** | LangChain 全家桶（openai/anthropic/google 包） | 自研 fenced JSON + 手工循环 | 开卷依赖少；AnxReader 换语言模型原生 tool-call 支持 |
| **工具轮次上限** | 120（可循环到答为止） | 4（超限强制回答） | 开卷省 token 但复杂问题可能截断；AnxReader 重（无界循环） |
| **工具可见性** | **思考面板 + 每步 tool tile + 失败 tile** | 完全不可见，工具轮次黑盒 | **开卷最大的 UX 缺口**：模型后台调工具时界面无反馈，像"卡住" |
| **书内正文供给** | 默认**不注入**，模型自己调 `current_chapter_content` | **默认注入当前章正文**（种子）+ 工具按需取 | 开卷简单问题零工具往返，更省；AnxReader 模型要多调一轮 |
| **书内检索** | headless WebView 跑真实渲染文本（准但重） | spine 纯文本抽取 + 关键词切片（轻但非全文索引） | 开卷够用且快；长书/排版复杂可能漏 |
| **系统 prompt** | 动态拼（isReading 角色 + 工具目录 + 语言名 + 长 guidance） | 静态 + 每轮注入书信息/选区/当前章 | 开卷种子更实；AnxReader 的"isReading 切换角色"思路可借鉴 |
| **联网** | 无专用联网工具（模型仅靠工具/知识） | 独立搜索 Key（Tavily/Brave）+ 面板开关 + 【书中】/【补充说明】两段 | **开卷更强**：书内/书外分离防幻觉，可追溯 |
| **多 provider / 切模型** | 顶栏 provider 下拉 + 模型选择 dialog + 每会话记 serviceId/model | 全局单 provider，对话内不可切 | 开卷按 spec「单模型即可」；会话没记 provider |
| **Key 轮换** | `AiKeyRotator` round-robin 多 key + `advanceKeyIndex` | 单 key | 限流服务（DeepSeek 等）容易撞 429 |
| **RPM 限流** | 滑动 1min 窗口（aiRpm 可配） | 无 | 多 key 场景配合用 |
| **Reasoning 处理** | 分离 reasoningContent / `<think>`，折叠面板展示 | 无（直接 markdown） | 深思考模型（o1/deepseek-r 类）开卷会直接把思考混进正文 |
| **会话持久化** | DB 表，会话列表 drawer，续聊/删除/清空/完成状态 | contentHash 单文件，无跨书列表 | 开卷按 spec「v1 不做跨书列表」；但**无"续聊/历史"入口**，重开面板即当前会话 |
| **快捷问法** | 内置 + **用户自定义 prompts（可编辑模板）** | 硬编码 `kAiChatShortcuts` 5 个 | AnxReader 可编辑模板/自定义 prompt 更灵活 |
| **工具可配** | 设置里开关每个工具 | 固定 5 个 | 开卷暂无暴露需求 |
| **错误处理** | 统一 `_mapError`（401/429/network/timeout）→ 可读文案 | 逐点 `AiProviderException` | 开卷已有；可补 429 限流提示 |
| **测试** | — | **60 个 AI 测试**覆盖协议/prompt/会话隔离 | 开卷更可测（无框架纯函数） |

---

## 4. 开卷明显更好的设计（保持）

1. **种子注入当前章正文**：局部问题不用工具、不烧 token 往返，AnxReader 做不到这种"默认够用"。
2. **联网两段式【书中】/【补充说明】**：书内证据 + 书外来源分离，符合开卷「不编造书中未出现情节」的产品约束；AnxReader 无此机制。
3. **contentHash 会话语义**：换书隔离、删书再导入自动续上、清空对话不动书——比 AnxReader 的全局会话列表更贴近"围着一本书"的定位。
4. **轻量零依赖**：无 LangChain 全家桶，启动与包体友好，纯函数可单测。

---

## 5. 对照出的差距（开卷"没做完"的候选）

按价值从高到低：

### G1. 工具执行对用户不可见（✅ 已落地）
模型在后台跑 `get_toc`/`search_book` 等时，界面无任何反馈；工具回合可能重复 4 次才出正文，用户看着输入框像卡死。
- AnxReader 的做法：时间线信封（`<tool-step status>`）+ 前端渲染成步骤 tile（进行中/成功/失败），失败还能看到错误。
- 开卷方案（**已落地**）：不引入 XML 信封。`AiChatService.streamReply` 带 `onToolStatus(String?)` 回调——执行工具前触发（如「正在检索『张居正』…」），进入最终流式前清空；`_BookAiChatSheet` 渲染带 spinner 的进度行。

### G2. 深思考模型把思考混进正文（已闭环，勿改）
`streamReply` 直接把流式文本当 markdown 渲染，但 provider 层已把思考隔离在正文之外：
- `anthropic_provider.dart`：`extractStreamDeltaText` 跳过 `thinking_delta`，仅当正文为空才兜底 `thinking`。
- `openai_compatible_provider.dart`：DeepSeek 默认发 `thinking: {type: disabled}`；`_coerceText` 优先 `content`，`reasoning_content` 只在 content 为空时兜底。
- 结论：**无需改动**。若以后要让用户看到思考流，另开「思考折叠面板」功能（AnxReader 用 `<think>` 信封剥离 + 折叠面板），不在本文范围。

### G3. 429 / 限流无提示（✅ 已落地）
撞到 DeepSeek 等限流时开卷给「请求失败：…」。已把 429/`rate limit` 映射为「服务限流，稍后重试」（`ai_provider.dart` 短请求 1 次重试 + provider 层文案）；可配 RPM 滑窗（复制 AnxReader `_throttleIfNeeded`）仍未做，留作可选。

### G4. 会话无「续聊/历史」入口
spec 说 v1 不做跨书列表，但**同一本书**至少应有：进入面板默认续当前会话 ✓（已有）、「清空对话」✓（已有）；缺的是**本会话的 model/provider 记录**——切了模型后旧消息没有归属信息，重新生成时会用新模型。AnxReader 在会话条目里记 `serviceId`/`model`。

### G5. 快捷问法硬编码
`kAiChatShortcuts` 5 个写死。AnxReader 支持设置里编辑 prompt 模板 + 用户自定义。开卷 M2 可不做，留给 M3+（导出/大纲页一起给自定义 prompt）。

---

## 6. 建议落地顺序

| 优先级 | 项 | 对应 ai.md | 工作量 |
|--------|----|-----------|--------|
| P0 | **G1 工具状态流**：`streamReply` 带 `onToolStatus` 回调 + 进度行 ✅ 已落地 | M2 收尾 | 小 |
| P0 | **G2 剥思考字段**：✅ 已确认闭环（provider 层隔离，见 §5，勿改） | M2 收尾 | — |
| P1 | **G3 429 文案** ✅ 已落地（RPM 滑窗可选，未做） | M2 收尾 | 小 |
| P1 | **G4 会话记录 model/provider** | M2 收尾 | 小 |
| P2 | G5 可编辑快捷问法 / 自定义 prompt | 并入 M3+ | 中 |
| P2 | 书内检索升级（可选，headless WebView 太重，不抄） | — | 大 |

> 注意：以上是**对话收尾**。SPEC 里的下一块大工作是 M3 大纲 / M4 整本翻译任务，见 [ai.md §9](../specs/ai.md#9-落地切片与验收)。

---

## 7. 结论回写

- [x] G1 已落地：`streamReply` 带 `onToolStatus` 回调，工具回合以状态文本流式可见
- [x] G2 已确认闭环（provider 层剥离），ai.md §4.3 注明深思考模型隔离
- [x] G3 已落地：429/`rate limit` 映射「服务限流，稍后重试」文案
- [ ] G4 会话记录 model/provider、G5 可编辑快捷问法仍为待办
