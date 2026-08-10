# 工程结构：单 App 双引擎

产品决策见 [PRODUCT.md](./PRODUCT.md)。

**目标**：一个 git 仓库，打出一个 **开卷** 本地阅读 App；内部同时包含漫画页图引擎与图书 reflow 引擎。

当前仓库已切换到 **单 App 入口**；Android 已移除 product flavor，Apple 端旧 scheme 继续逐步收口。

---

## 1. 目标形态（推荐）

```text
kaijuan/                            # 仓库名
  docs/                             # 产品与设计
  lib/                              # 单 App 代码
    main.dart                       # 唯一入口
    main_comic.dart / main_book.dart # 兼容重定向到 main
    brand/brand_config.dart         # 单 App 配置
    library/import/                 # 方式适配、格式判定、内容寻址、元数据、DB 提交
    readers/comic/                  # 页图引擎
    readers/book/                   # reflow 引擎
    ai/                             # BYOK Provider、设置存储（不进 WebDAV 备份）
    presentation/                   # UI / controllers
  android/ ios/ macos/ windows/ linux/
  tool/                             # 构建与辅助脚本
```

### 品牌配置

```text
BrandConfig
  displayName: 开卷
  applicationId: com.kaijuan.reader
  accent presets + default accent
  default reading theme
  import extension whitelist: cbz, zip, epub, fb2, fbz, mobi, azw3, pdf, txt, md
  databaseName: app_library        # 沿用已有数据
  storageNamespace: ''             # support root
```

入口：

```text
lib/main.dart → runApp(App(brand: BrandConfig.app))
```

---

## 2. 过渡形态（当前）

- `lib/main.dart` 是唯一入口。
- `lib/main_comic.dart` / `lib/main_book.dart` 重定向到 `bootstrap()`，仅兼容旧 `-t` 入口；Android 不再接受 `--flavor comic/book`。
- `BrandConfig.app` 单例；`AppBrand` enum 已移除。
- 数据沿用 `app_library` + support root，**不**迁移旧 `book_library`。

---

## 3. 共享与边界

| 放入 core/lib | 漫画引擎 | 图书引擎 |
|---|---|---|
| ReaderKind/Format、locator 约定 | ComicSession、四模式 | Reflow 引擎、目录 |
| AppDatabase 表结构 | 页图缓存 | 分页/排版 |
| 进度 / 书签 API 形状 | 漫画 chrome 附加控件 | 字号面板 |
| 间距圆角色板 | | |
| 书架/书库通用 widgets | | |
| EpubImportRouter | | |

### 导入两层

- `ImportMethod` 表示来源方式（本地文件、目录扫描、拖拽、分享、WiFi、WebDAV、OPDS）；它只负责把来源变成候选，不知道 book/comic。
- `ReaderFormat` 表示内容格式（CBZ、ZIP、EPUB、FB2、MOBI、AZW3、PDF、TXT、Markdown）；它决定格式服务和必要的 kind 探测。
- `ImportCandidate` 是两层之间的边界，至少携带来源方式、显示名称、可重复读取的字节流和可选 MIME。
- `ImportPipeline` 统一执行候选的 staging、SHA-256、格式路由、失败隔离和结果汇总。方式适配器不得绕过它直接落库。
- `WifiTransferService` 只负责临时局域网 HTTP、会话令牌和上传临时文件；上传完成后必须以 `ImportMethod.wifi` 交给 `ImportPipeline`，不得直接写正式目录或数据库。
- `RemoteSourceController` 负责 WebDAV / OPDS 连接记录、凭据访问、目录状态和远程导入队列；表现层不得直接持有 HTTP 客户端或安全存储。
- WebDAV / OPDS 适配器只负责协议解析和远程字节流，必须把选中的文件转换为 `ImportCandidate`，再交给 `ImportPipeline`；不得直接写正式文件或数据库。
- `BackupService` 负责用户自有 WebDAV 的逻辑快照、内容寻址对象和恢复合并；不得复制 SQLite 文件，也不得把备份误当成实时同步。
- 阅读时长仍是快照数据而非跨设备 CRDT：恢复旧 `dayStats` 时必须先校验日期与非负计数，再按整行选择本地或远端较大的有效累计，禁止分别合并 active/comic/book；单本累计取较大值。若未来需要精确叠加多设备新增时长，必须另立带设备来源的单调计数器或不可变 session 记录，不能继续扩展当前日汇总行。
- WebDAV 导入与备份共用连接和凭据，但目录选择器分流：导入只把文件送入 `ImportPipeline`，备份只返回相对 WebDAV 根目录的文件夹路径，不进入导入队列。
- `BackupController` 是设置页唯一入口；备份页面不得直接访问 Drift、`WebDavSession` 或安全凭据。
- 备份清单使用 `contentHash` 和相对对象路径，不得持久化本机绝对 `filePath`、WebDAV 密码或临时缓存。

详细的格式矩阵与方式状态见 [specs/import.md](./specs/import.md)。

禁止：core 依赖某个品牌文案；image 引擎包 import book 引擎（仅 import service / router 可桥接）。

### 图书语言能力边界

- 选区词典 / 翻译由 `BookReaderController` 调用 `BookLanguageProvider`，表现层不直接持有平台通道。
- 默认 `PlatformBookLanguageProvider` 只调用设备已有能力：Android 使用系统 Intent 选择器，Apple 使用系统词典 / Translation framework；不内置外网词典，也不发起网络请求。
- `BookLanguageProvider` 的请求包含 `dictionary`、`selectionTranslation`、`fullBookTranslation` 三种操作；后续 AI Provider 可替换默认实现，承载单句结果或整本书任务，不改选区菜单协议。

### AI 边界（BYOK）

知识图谱 v3：入口与共享的 `AiBookStructureResolver` 保持不变；识别结果之后采用“生成目标 → 内容单元 → 构建任务”三层边界。`AiGraphScopePlanner` 把书内作品与全部可读单元整理为确定性选择计划，只给出正文/辅文的默认勾选建议，不能替用户删除范围；图谱管线只接收用户确认后的正文切片，负责多类型抽取、可选补漏、证据定位、消歧、合并与方向复核，并通过 checkpoint 回调发布不可变快照。实体与关系以稳定 ID 相连，关系图、家族树及实体详情都不得用名称作为身份键；家族树只消费父母/祖辈到子女的代际边，旁系亲属保留在关系图但不进入层级。电子书正文、标题、证据摘录和已知实体表一律作为不可信上下文注入模型。

本书 AI 采用组合边界，新增职责不得继续堆入阅读器 god-controller：

- `BookReaderController` 暂时作为兼容门面暴露 AI 命令，并持有阅读引擎回调；正文抽取缓存由 `AiBookCorpusCache` 独立负责，作品识别及“当前位置属于哪部作品”由 `AiBookStructureSession` 作为对话/大纲/图谱的唯一结构事实源。
- `AiBookChatToolHost` 只依赖正文缓存、本轮冻结上下文和作品范围，不得依赖表现层 controller；即使阅读引擎忽略范围参数，也必须再次本地收窄，防止相邻作品正文泄漏。
- `AiChatService` 把供应商的单次输出限制视为传输分段而非回答失败：收到 `length` / `max_tokens` 后以同一冻结上下文自动续写、去重拼接到同一回答，并设置有界保护。流式传输只允许在首个可见文字前重试瞬时故障；首字后失败保留部分正文，不得从头静默重跑。表现层按节流频率保存 pending 回答检查点，终态写入必须排在检查点之后并覆盖它。
- AI 运行时采用“开卷确定性编排器 + 可替换模型适配层”。`AiRunState` / `AiRunEvent` 是 App 自有的纯 Dart 契约；回答正文与供应商可见思考过程分别采用**完整快照**而非不可回退 delta，支持自动续写去重拼接和消费者幂等重放。本书对话只暴露事件流，UI 不得自行推测运行阶段或把思考过程拼入回答正文。
- 对话、图谱与设置的模型和文件存储分别放置；JSON 原子写入、备份恢复与安全凭据不得混入模型类。生成数据面只经 `AiModelAdapter`，模型目录是独立只读 `AiModelCatalog`；旧 Provider 双栈不得重建。
- 下一阶段再把对话发送状态和大纲/图谱任务状态迁入独立 workspace/conversation controller；迁移前先补 Widget 流程测试，不以 `part` 或跨文件私有字段制造形式拆分。
- 图谱模型、文件存储、抽取、合并消歧、质量门和描述润色是独立职责。管线 orchestrator 只编排这些组件，拆分不得改变提示词、算法阈值、缓存 schema 或 checkpoint 时机。

- 产品范围见 [PRODUCT.md §6](./PRODUCT.md) 与 [specs/ai.md](./specs/ai.md)。
- `lib/ai/`：`AiModelAdapter`（所有生成的单回合、原生工具调用与结构化输出边界）、`AiModelCatalog`（只读模型目录）、`AiSettings`（非机密、原子 JSON）、`SecureAiCredentialStore`（模型 Key + 搜索 Key 分槽）、`AiBookStructureResolver`（纯 Dart；把 TOC/spine/heading 事实归一为单本、分段单本、多作品出版物或不确定结构，供对话/大纲/图谱共享）、`AiGraphScopePlanner`（纯 Dart；把识别结果和完整内容单元变成用户可确认的范围计划）、选区语言 `AiLanguageService`、本书对话 `AiChatService`（最多四轮的原生 tool loop，非 LangChain；`get_toc` / `get_current_chapter` / `get_chapter` / `search_book` / `sample_book`）、`AiBookOutlineService`、`AiBookGraphService` + `AiGraphStore`、可选联网 `AiWebSearchService`（Tavily / Brave）+ `ai_chat/` 会话文件。
- 图书思维导图使用独立 `BookMindMapWorkflow` + `AiBookMindMapStore`，但产品入口和结果承载属于本书对话。对话层只把自然语言确定性路由为“当前章”或“当前作品/整书”并冻结 `contentHash/workKey/sectionIndices`；Workflow 经 `AiWorkflowModelSession.completeJson` 分批生成并原子 checkpoint，完成后把扁平稳定节点作为结构化对话附件持久化。它不依赖 `AiBookGraph` 或 Mermaid；通用聊天 Mermaid 仍走富内容渲染。布局算法和画布位于纯 Dart/Flutter 表现边界，Genkit、SVG/HTML 与模型临时 ID 不进入业务缓存。详见 [ai-mind-map.md](./specs/ai-mind-map.md)。
- AI 回复的富内容渲染保持在 `presentation/widgets/reader/`：`AiResultBody` 负责 Markdown AST 与扩展块分发，代码、图形、媒体分别由独立 Widget 承担；Mermaid 通过随包原生 headless 引擎离线生成 `resvg-safe` SVG，声明式 chart 先转为受限 Mermaid 语法。屏幕显示使用 Flutter 原生 SVG surface，避免为列表中的每张图常驻创建 WebView；Merman 仍放在 `<style>` 类选择器中的 mindmap 节点、连线和文字颜色，必须在隔离线程内按当前主题物化为元素属性后再交给 `flutter_svg`，否则简化 SVG 解析器会把未命中的形状按默认黑色填充。图形主题由 Widget 把当前语义 `ColorScheme` 编译为 Merman options，缓存键必须包含主题，皮肤或强调色变化时重新生成；不得让渲染引擎直接依赖 `BuildContext`，也不得写死默认暖橙。渲染器不得进入 Provider/Service，也不得执行模型提供的 HTML 或脚本；未知语言和解析失败统一降级为可复制源码块。
- Apple 端暂用 CocoaPods 集成原生插件（`flutter.config.enable-swift-package-manager: false`）：`merman 0.7.0` 的 SwiftPM 二进制目标位于 package 目录外，Flutter 生成插件软链接后 Xcode 无法解析；其 macOS dylib 还携带上游 CI 的绝对 install name，因此 Runner 在 Pods 嵌入完成后通过 `patch_merman_install_names.sh` 把 App、插件 Framework 和 dylib 的引用统一改成 `@rpath/libmerman_ffi.dylib`，并用本次 Xcode 构建身份重新签署被修改的嵌套代码。待上游同时修复二进制布局与 install name 后再移除兼容层并恢复 SwiftPM；不得修改 Pub 缓存或用开发机全局 `flutter config` 掩盖约束。
- 预设服务商：OpenAI、Anthropic、DeepSeek、Grok；另支持「自定义（OpenAI 兼容）」端点和本地 Ollama。OpenAI Compatible 与 Anthropic 分别使用官方 Genkit Dart 插件；两者不共享 wire adapter，也不做跨协议回退。
- 表现层只经 `AiSettingsController`；Widget **不得**持有 `http.Client`、不得读写安全存储、不得拼装供应商请求体。
- AI 异常在进入 Widget 前必须经过统一的用户错误映射；供应商原文、HTTP 状态码、JSON/SSE/schema、异常类名与堆栈仅写调试日志。Widget 不得把 `error.toString()` 或未经映射的 `AiProviderException.message` 直接展示。
- API Key（模型与搜索）**不得**写入 `ai_settings.json`、WebDAV 备份清单或调试导出。
- 携带 Key 的远程模型端点必须使用 HTTPS；明文 HTTP 只允许无 Key 的 loopback 本地后端。Adapter 的流式成功终态必须来自协议完成事件，异常 EOF/空闲超时不得伪装成成功。
- 总开关关闭时 `openModelAdapter()` 返回 null，业务层不得绕过开关发生成请求。
- 本书 AI「联网」默认关；仅开关开且已配搜索 Key 时才调用搜索 API，结果注入 chat system prompt 的补充区。

#### AI 运行时实现与边界

| 层 | 当前实现 | 保持不变 / 禁止越界 |
|----|----------|----------------------|
| 事件与状态 | `AiRunEvent` 带稳定 `runId`、单调序号、冻结作用域、进度、回答快照、可选思考过程快照、usage 与唯一终态；`AiRunState` 纯 reducer 可幂等重放；controller 保留最近 20 个 run 状态 | 回答与思考过程事件均是可替换快照，不是 token delta；事件不直接成为 Drift / WebDAV schema |
| 开卷编排器 | `AiRunOrchestrator` 统一预算、取消、超时、模型/工具/续写计数、checkpoint hook 与错误分类；对话为最多四轮的受控 Tool Agent | 不把作品定位、权限、持久化或 UI 状态交给模型框架；不做多 Agent |
| 模型适配层 | `lib/ai/adapters/` 隔离 `GenkitOpenAiModelAdapter` 与 `GenkitAnthropicModelAdapter`；精确固定 `genkit 0.15.1`、`genkit_openai 0.3.7`、`genkit_anthropic 0.2.11`。App 自有 `AiModelAdapter` 只表达单次回合、原生工具请求、可选推理 delta、推理展示类型、工具连续性元数据和结构化 JSON；Anthropic 模型列表仍走只读 `GET /v1/models` transport；可重试 transport/HTTP 错误只允许在首个可见文本或推理输出前自动重试一次。Provider 推理字段由 adapter 内的能力策略映射：DeepSeek `thinking.type`，Anthropic `thinking` adaptive/disabled，OpenAI / xAI / Ollama `reasoning_effort`，自定义兼容端点开启时尽力发送通用字段、关闭时完全省略。锁版 `genkit_openai` 会把 schema 一律映射成 OpenAI `json_schema`；DeepSeek 只接受原生 `json_object`，因此隔离的 HTTP decorator 只对 DeepSeek 把该字段降为 `json_object`，并把同一 JSON Schema 注入模型消息；Genkit 仍负责 JSON 解析，Schemantic/Workflow 继续执行结构与业务校验。OpenAI Compatible 返回的 `reasoning_content` / `reasoning` / `thinking` 与 Anthropic `ReasoningPart` 统一映射为 App 事件；供应商要求跨工具回合保留的推理内容、签名和不可见 `redacted_thinking` 必须按原顺序回传 | Genkit、插件 SDK 与供应商协议类型不得进入 UI、controller、数据库和备份 schema；不得声称展示完整思维链；不得把 DeepSeek 兼容分支扩散到其他 Provider、改成 fence 截取或绕过 schema/业务校验；插件或供应商协议升级必须重新跑对应适配器协议、取消和异常终态测试 |
| 协议选择 | OpenAI / DeepSeek / Grok / 自定义 / Ollama 使用 Genkit OpenAI Compatible adapter；Anthropic 使用 Genkit Anthropic adapter；适配器缺失或端点不支持时本轮明确失败 | 不做跨协议隐式回退、手写 Messages 对话 adapter、fenced JSON 或旧 Provider 对话回退；不放宽五个只读工具、冻结作品范围和本地参数预算 |
| 确定性工作流 | 词典/选区翻译使用无工具 `streamTurn`；大纲、图谱和图书思维导图的每类输出使用独立 Schemantic schema + `completeJson`；所有模型调用由 `AiWorkflowModelSession` 报告调用次数/usage 并统一关闭 adapter，图谱与思维导图保持各自 checkpoint/存储格式。Anthropic constrained output 会强制 `return_output` 工具，与 thinking 的官方组合边界不稳定，因此 adapter 对结构化调用固定发送 disabled thinking，普通流式调用仍服从用户偏好。DeepSeek 使用官方 JSON Object mode，schema 指令、Genkit JSON parser 和 Workflow 业务校验缺一不可；无效、空白或截断输出仍进入 `RunFailed`。失败和用户取消必须投影为不同且可见的 UI 终态 | 不把批处理改造成自由 Agent 或 Genkit defineFlow/Agent，不混用图谱/思维导图/聊天 Mermaid 数据，不自行解 fence、正则恢复 JSON 或引入第二套生成 transport |

`AiRunEvent` 只表达运行事实，不是持久化 schema。`AiRunCheckpoint` 自身带版本，但 payload 仍由既有工作流存储负责；当前图谱继续写原有 `AiBookGraph` 快照，不把临时事件写入 `ai_chat` / Drift / WebDAV。对话终态可把供应商公开的推理过程或推理摘要写入 `AiChatMessage.reasoningContent`，并以 `reasoningKind` 区分展示文案，随同一会话 JSON 和 WebDAV 快照保存；它与回答正文分栏、默认折叠，不参与回答复制和后续普通消息历史。签名等协议连续性元数据只存活于当前运行，不写入会话或备份。Genkit 内部 trace 只允许留在 adapter 边界，产品运行事实以 `AiRunEvent` 为准。

模型 I/O 收口完成后的唯一依赖方向为：业务 Workflow → App 自有 `AiModelAdapter` → 隔离的 Genkit Provider 插件。模型目录读取单独抽为只读 catalog transport；连接测试通过 adapter 发起无工具单回合。UI、controller 和业务 Workflow 不得再依赖 `AiProvider`、Genkit、Schemantic 生成类型或供应商 SDK。结构化 schema 定义集中在 AI 基础设施边界，使用 Schemantic 生成并由 adapter 消费；模型返回后仍执行既有业务语义校验，JSON Schema 不能代替来源覆盖、稳定 ID、证据定位等产品规则。

### 表现层导航边界

- `AppShell` 持有根级书架 / 书库 / 设置状态，并在内容区提供嵌套 Navigator。书单、合集、导入确认、远程来源与 WebDAV 备份等管理型子页推入内容 Navigator，宽屏侧边栏和窄屏 BottomBar 不随子页消失。
- 点击根导航目标时先清理内容 Navigator 的子页栈，再切换根页面，避免子页被错误保留到另一 Tab。
- 漫画与图书阅读器继续使用 root Navigator，以维持沉浸式全屏和独立阅读 chrome。
- root Navigator 注册共享 `RouteObserver`；阅读时长采集把 route 可见性与正文 ready、App lifecycle、TTS 状态共同作为计时资格，加载/错误页面和被模态 route 覆盖的阅读器不得累计。

### 折叠屏 / 多窗口布局

- 断点实现在 `lib/core/theme/context.dart`（`resolveAppWindowClass` 等纯函数 + context getter）；**宽度**决定 compact/medium/wide，**短高度**只走 `appIsShortViewport`（压缩底栏/工具面板），不再把宽折展开误判为 compact。
- 导航 chrome 互斥且必有其一：
  - 移动：宽 ≥ `kAppMobileSideRailMinWidth`（840）侧栏，否则底栏。
  - 桌面：宽 ≥ `kAppDesktopSideRailMinWidth`（900）侧栏，更窄时临时底栏，避免窄窗被 216px rail 挤扁。
- **内容密度** `appContentWide`（非 compact）与 **导航壳** `appUsesMobileShell` 正交：展开折可以「宽内容 + 底栏」或「宽内容 + 侧栏」，禁止用同一个 `wide` 混指两者。
- 底 inset 动态计算：`AppNavigationChromeMetrics` 与底栏高度同步，`appContentBottomPadding` / `appFabBottomInset` = 栏高 + 系统底 inset + gap（不再写死 140/88）。
- 封面网格 `appCoverGridMaxExtent` 随窗口类放大；中央竖折痕通过 `resolveHingeGutterBoost` 加 gutter。
- Android `resizeableActivity=true`；图书 WebView 折叠切屏恢复见上文「图书排版实现」。

### 图书排版实现

- EPUB 正文采用 Anx Reader 维护的 MIT `foliate-js` 内核，经 `flutter_inappwebview` 承载；保留其 Paginator 的章节按需挂载、手势方向锁定、跟手滚动、200–300ms 吸附动画和 ResizeObserver 重排，不再维护 Kaika 自有分页器。
- 禁止在 Dart UI isolate 上用 `TextPainter` 预分页整章、邻章或整本。系统 WebView 的 HTML/CSS columns 负责 reflow，Dart 只维护 locator、偏好和 chrome。
- EPUB 与 `foliate-js` 静态资源由只绑定 `127.0.0.1` 的 **App 级共享** loopback server 流式提供；端口尽量复用并持久化，稳定 WebView origin 以便二次打开命中静态资源缓存。各阅读/导入 session 只挂载自己的 `/books/<id>.epub`，关闭时卸挂，不销毁共享 listener。前端按 Anx Reader 的 `fetch → File → zip.js BlobReader` 链路打开，禁止 Dart `readAsBytes` 后展开成 JavaScript 整数数组。
- WebView 实例在普通尺寸变化时保持存活，由 foliate Paginator 的 ResizeObserver 以当前 anchor/CFI 重排。尺寸/生命周期切换开始时先冻结最后一个稳定 CFI，并忽略离屏或零尺寸阶段的 relocation。部分 Android 折叠屏切换物理显示器时系统会主动终止 WebView renderer；adapter 必须移除失效 WebView，并在 resumed 后用冻结的 CFI 重建，不能继续调用已死亡的 renderer。
- 首次打开只能由 `View.init(lastLocation)` 发起一次定位；空 CFI 不得额外并发调用 `renderer.next()`，否则 Android WebView 会同时创建两个章节 iframe，形成 ResizeObserver/分页重排竞争。
- 引入或修改的 BSD / MIT / Apache 源码与依赖必须保留许可证声明；应用业务层继续自有，开源 renderer 通过 adapter 接入 controller。

完整的 Anx 导入、打开、阅读和 App 分层对照见 [research/foliate-architecture.md](./research/foliate-architecture.md)。核心取舍是复用 Foliate 的格式/rendition 语义，不复制 Anx 的 UI、DAO 直连或全局 service 组织。

### 图书全链路边界

| 边界 | 职责 | 禁止 |
|---|---|---|
| `EpubImportRouter` / `EpubKindProbe` | Dart ZIP/OPF 有界抽样，判定 book/comic | WebView、整本 `readAsBytes()`、写 DB、弹 UI |
| `BookImportService` | hash、内容落盘、metadata、事务提交 | 构建阅读 WebView、持有 screen context |
| `BookReaderController` | locator、书签、偏好、chrome、持久化 | 解析 EPUB、操作 DOM、直写 renderer 状态 |
| `FoliateJsBookEngineAdapter` | controller 与 typed Foliate event 的适配 | 直连 drift、承载书库业务 |
| `BookLoopbackServer` | App 级 loopback、固定 origin、白名单资源与按 id 挂载书籍 | 接受客户端绝对路径、离开阅读器即杀 listener |
| `BookRenditionSession` | 单书 mount、WebView generation lease、阶段耗时 | UI 状态、书签和偏好、独占销毁共享 server |
| `foliate-js` | EPUB 解析、TOC、CFI、reflow、输入 | 认识 Kaika 数据表和导航层 |

**kind 判定**由 `EpubKindProbe`（Dart ZIP/OPF，最多 12 节均匀抽样）完成，不打开 WebView；阈值与 Foliate 样本语义对齐：≥80% 抽样节为「低文字且含页图」才路由漫画，封面或零散插图不得把正文 EPUB 判成漫画。页图 EPUB 走 comic import 后全程无 WebView。

**图书元数据 / 封面 / 阅读**仍用 Foliate：`BookImportService` 在 kind=book 后通过 metadata-only 不可见 WebView 读取 title/cover/sectionCount；阅读阶段再由可见 rendition 打开。导入 probe 必须有超时、错误回传和无条件 dispose，且不得进入阅读 controller。

### 导入提交协议

```text
source
  → 单次流式复制到 .import-staging，同时计算 SHA-256
  → 在 staging 文件上完成 kind/metadata/page list/cover
  → 内容与封面按 hash 原子 rename 到 library/covers
  → AppDatabase upsert
  → 任一步失败：删除 staging，并补偿删除本事务新建的 target
```

- staging、`library` 与 `covers` 必须位于同一个 support root，确保 rename 不跨文件系统。
- rollback 只能删除当前事务实际创建的 target；同 hash 的既有文件不得删除。
- 正式目录在解析完成前不可见半成品。文件提交后若 DB 写入失败，执行补偿回滚。
- debug timing 分为 `foliate-probe`、`book`、`comic` 三条管线；至少标记 validated、content-staged、metadata/page-list、cover-staged、files-committed、database-committed 或 rolled-back。
- 导入与打开 timing 同时写入进程内 `PipelineDiagnostics`；设置 → 关于可复制导出，不只依赖 debug console。
- 启动时对 `.import-staging/*.partial` 做年龄门限清扫（默认 24h），只删确认过期且非活跃事务的残留。

---

## 4. 数据沿用

| 项 | 策略 |
|----|------|
| DB 文件名 | `app_library`（沿用已有） |
| 内容文件目录 | `…/library` + `…/covers`（support root） |
| 偏好 JSON | `comic_reading.json` / `book_reading.json` / `theme.json` |
| 旧 `book_library` | 不自动合并；需要可重导 EPUB |

---

## 5. 构建与运行

### 5.1 日常开发

```sh
flutter pub get
flutter run -d macos
flutter run -d <android-device>

# 旧脚本兼容（brand 参数被忽略）
tool/run_brand.sh comic
tool/run_brand.sh book macos

# 等价
flutter run -t lib/main.dart
```

macOS 日常开发不再强制 `--flavor comic`。若 Xcode scheme 仍绑定 flavor，可先用 `comic` scheme（显示名已改为开卷）；`book` scheme 标 deprecated。

### 5.2 验证

```sh
dart run build_runner build --delete-conflicting-outputs   # drift 生成（改表结构后必跑）
flutter analyze
flutter test
flutter build apk --debug
```

CI（`.github/workflows/ci.yml`）在 `main` push / PR 上跑 analyze + test，并缓存 drift 生成。

### 5.3 原生 flavor 收口

- Android：**无 productFlavor**；普通 `flutter run` / `assembleDebug` 直接构建；namespace 与 applicationId 均为 `com.kaijuan.reader`，应用名 **开卷**。
- iOS/macOS：保留 `comic` scheme；`book` scheme 标 deprecated；App 显示名 **开卷**（`.app` / `PRODUCT_NAME` 同）。
- 图标：`brands/icons/kaijuan_master-v2.svg` 为可编辑母版；`comic/master_1024.png` 为正式栅格源，`book` 目录镜像同一身份供旧 scheme 使用。

后续清理：删除 Apple 端 `book` scheme/xcconfig/icon set，以及 Android 已失效的旧 flavor 图标目录。

### 5.4 图标

```sh
python3 tool/generate_brand_icons.py
```

当前源图：`brands/icons/kaijuan_master-v2.svg`；导出的兼容栅格为 `brands/icons/comic/master_1024.png`。

### 5.5 发布打包

**不要**直接 `flutter build … --release` 发版。版本以 `pubspec.yaml` 为唯一来源：`MAJOR.MINOR.PATCH` 对用户可见；`+build` 为内部 build number。

```sh
# 预览下一版本（不改文件）
dart run tool/release.dart --dry-run

# bump patch 一次，构建所选平台，产物写入 dist/
dart run tool/release.dart android
dart run tool/release.dart android macos
dart run tool/release.dart windows

# 不 bump，用当前版本重打
dart run tool/release.dart android --no-bump

# 已有 drift 生成物时可跳过 codegen
dart run tool/release.dart android --no-bump --skip-codegen

# macOS 本地包会同时产出 ZIP 和 DMG；DMG 内含 /Applications 拖拽入口
dart run tool/release.dart macos --no-bump --skip-codegen
```

| 平台 | 产物（`dist/`） | 宿主要求 |
|------|-----------------|----------|
| android | `kaijuan-x.y.z-android.apk`、`.aab` | 任意 |
| ios | `kaijuan-x.y.z-ios-unsigned.zip` | macOS |
| macos | `kaijuan-x.y.z-macos.zip`、`.dmg`（`开卷.app`） | macOS |
| windows | `kaijuan-x.y.z-windows.zip`；可选 `.msix`、`-setup.exe` | Windows |

Windows 安装包细节见 [`packaging/windows/README.md`](../packaging/windows/README.md)。MSIX 依赖 `msix` dev 包与 `msix_config`（`pubspec.yaml`）；Setup.exe 需 [Inno Setup 6](https://jrsoftware.org/isinfo.php)。

macOS 本地包使用 ad-hoc 签名，产物可用于本机安装和验收；外部分发仍需 Developer ID 签名与公证。可用 `codesign --verify --deep --strict build/macos/Build/Products/Release/开卷.app` 和 `hdiutil verify dist/kaijuan-x.y.z-macos.dmg` 做验证。

**GitHub Release**：推送 `vMAJOR.MINOR.PATCH` tag 触发 `.github/workflows/release.yml`，为 Android / iOS / macOS / Windows 打 unsigned 包并上传 Release（不含 MSIX / Inno，那些仅本地 `release.dart windows` 产出）。

**签名（本地/商店，未接入 CI）**

| 平台 | 模板 / 位置 |
|------|-------------|
| Android | `android/key.properties.example` → 复制为 `key.properties` + upload keystore；当前 `build.gradle.kts` release 仍用 debug 签名 |
| Apple | 本地便携包使用 ad-hoc 签名；商店包使用 Xcode 开发/分发证书；CI 产物为 `--no-codesign` |
| Windows MSIX | `msix_config` 测试证书 sideload；商店需 Partner Center 身份 |

bump 失败时 `release.dart` 会回滚 `pubspec.yaml`。

---

## 6. 迁移步骤（已完成）

1. **文档** — PRODUCT / ENGINEERING 改为单 App ✅
2. **BrandConfig + 单 main** ✅
3. **偏好 / DB 沿用已有布局** ✅
4. **双 import service + EpubImportRouter** ✅
5. **LibraryController 类型筛选 + 混排** ✅
6. **UI 打开路径 / 设置 / 文案** ✅
7. **Apple 原生 scheme 收口** — P2 可选

---

## 7. 与当前代码映射

| 现在 | 说明 |
|------|------|
| `lib/main.dart` | 唯一入口 |
| `BrandConfig.app` | 单 App 配置 |
| `EpubImportRouter` | EPUB 自动探测与路由 |
| `LibraryController` | 双 service + `LibraryKindFilter` |
| `AppDatabase.watchLibraryEntries([kind])` | 可选 kind 查询 |
| `readers/comic/*` | 漫画页图引擎 |
| `readers/book/*` | 图书 reflow：导入探测与阅读渲染统一使用 Anx Reader foliate-js + 系统 WebView |

**图书引擎**：业务管线、locator 和输入适配保留 Kaika controller 边界；排版、分页和触摸交互复用 Anx Reader 的 foliate-js + 平台 WebView。

**图书平台能力**：`BookReaderCapabilities` 是模式入口的单一判定；iOS / iPadOS / Android 开放滚动与翻页，macOS / Windows（以及非目标 Linux 桌面）仅开放翻页。controller 必须再次约束模式，不能只依赖设置 UI 隐藏。

**阅读偏好入口**：漫画与图书偏好继续由各自 preferences 持久化，但只允许在对应阅读器内修改；App「设置」页不承载阅读模式、方向、字号、版心或阅读背景。

**图书 CSS 管线**：foliate-js 在 WebView 中按 EPUB 原始路径加载章节 CSS、图片与嵌入字体；Kaika 通过 Anx style bridge 注入阅读基线（微信读书式黑体栈、宽版心侧边距、上下 meta 留白、`textIndent=2`、主题正文/链接/标题色、规格化标题倍率）。页眉章节 / 页脚全书页码由 Flutter `BookPageMetaOverlay` 叠在 Foliate 边距带上。正文字体三源：`book` / 系统 CSS 栈 / 用户字体（`support/fonts` + loopback `/fonts/<id>` → `fontPath`）。空 `fontPath` 不写 `@font-face`。旧 `FlutterHtmlBookEngineAdapter` / Dart paginator / Dart pageMap 已删除，仓库只保留一条阅读渲染链。

---

## 8. 非目标（工程）

- 强制上 Firebase 多项目
- 两 App 共用 App Group（已合并为一个 App）
- 一次 PR 完成 monorepo 全拆

细节实现以迭代 PR 为准；**结构争议以本文 + PRODUCT 为准**。
