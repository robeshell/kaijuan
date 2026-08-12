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

#### 目标运行时（分阶段迁移）

本书 AI 从阅读器 god-controller 中拆出独立 Workspace，目标依赖方向固定为：

```text
BookAiChatView
  → BookAiWorkspaceController
    → BookAiConversationController
      → AiAgentRuntime
        → LegacyAiAgentRuntime | GenkitAgentRuntime
      → AiActionProposal
    → AiProductActionController
      → ProductActionRegistry
        → AiProductActionDefinition
          → Domain ActionGateway
          → AiWorkflowAdapter
          → AiArtifactDefinition
      → AiActionPolicy
      → AiActionJournal
      → AiAuthorizedCommand
    → BookAiMindMapController
      → deterministic BookMindMap Workflow
    → BookContextGateway / App repositories / WebDAV snapshot
```

- `BookAiWorkspaceController` 持有独立的 `BookAiConversationController` 与 `BookAiMindMapController`。前者拥有有界会话消息、联网/模型 run、流式投影、重试身份、部分回答 checkpoint、终态提交和会话持久化；后者拥有原生导图附件、批次进度、确定性顺序执行、产物谱系和产品 turn 终态。Widget 只冻结阅读上下文、承载范围选择交互、调用 Controller 并渲染投影，不再自行订阅模型流或执行 Workflow 循环。
- `AiAgentRuntime` 是 App 自有的纯 Dart 契约，输入包含冻结作用域、历史、可用产品别名和预算，输出继续使用 `AiRunEvent` 完整快照语义。任何 Genkit 类型不得越过该边界进入表现层或产品持久化。
- `AiProductActionController` 是所有产品动作的单一控制平面：模型 Tool Call、显式快捷入口和范围卡片统一投影为 `AiActionProposal`，经纯 Dart `AiActionPolicy` 得到允许、对话内确认、补充或拒绝结果；只有有效授权才能签发不可变 `AiAuthorizedCommand`。失败重试与崩溃恢复仍经同一 Controller，但只引用既有 Command/Journal 并创建新的 Workflow attempt，不重新解析意图。Controller 在 Workflow 前原子写入 `AiActionJournal`，完成后提交 `AiActionReceipt`。正式状态、字段和迁移顺序见 [specs/ai-product-actions.md](./specs/ai-product-actions.md)。
- `ProductActionRegistry` 只接受编译期 `AiProductActionDefinition`：每个动作必须声明唯一 action kind、封闭 schema、风险、作用域、所需能力、Gateway、`AiWorkflowAdapter`、可选 Artifact definition 及独立版本。注册表负责冲突校验、可用性发现和最小 Tool 目录，不决定授权、不读取实时翻页位置、不执行 Workflow。新增动作不得要求修改通用 Controller 的 action switch；完整契约见 [specs/ai-workflow-extension.md](./specs/ai-workflow-extension.md)。
- `AiWorkflowAdapter` 是确定性领域执行的稳定边界，统一暴露 preflight、start、recover、requestCancel 和 inspect 语义，并只发布 App 自有类型化事件。实现可以调用本地 Dart Service、Genkit structured output 或未来远端编排器，但 Command、checkpoint、取消、Artifact 原子提交和 Receipt 不得使用框架类型作为产品事实。
- `AiCapabilityResolver` 按 Runtime、Provider、模型、平台、设置和依赖生成能力快照。动作按 required/optional/oneOf 声明 structured output、长上下文、真实取消、渲染器、文件写入或外部服务等能力；未满足 required 能力时既不暴露给 Agent，也不能由显式 UI 绕过。
- `LegacyAiAgentRuntime` 在迁移期包装当前 `AiChatService`，保证提示词、原生 Function Calling、四轮工具上限、八轮续写、取消和错误语义不变；`GenkitAgentRuntime` 通过功能开关和同一契约测试灰度替换。
- Genkit Agent 在通过运行时契约后可以拥有普通对话的模型工具循环、运行时 Session/Snapshot、Interrupt/Resume、Retry 和 Trace；开卷仍拥有 EPUB 解析、书籍/作品范围授权、预算、产品任务取消、领域 Artifact 版本、checkpoint、数据库、WebDAV 与 UI 状态。
- `create_book_mind_map`、`revise_book_mind_map`、图谱和翻译等是产品工具。Agent 只提交 App 签发的别名与用户要求，其 Tool Call 只能产生 Proposal；模型、别名解析和范围校验都不构成执行授权。`AiBookMindMapActionGateway` 等 App 网关解析真实身份并复核冻结范围，`AiProductActionController` 按 Policy 获取授权、写入 Journal，再把 Command 交给领域 Controller 和确定性 Workflow。模型不得直接写数据库 ID。网关是纯校验/解析边界，不读取实时翻页位置、不决定授权，也不渲染 UI。
- Genkit Dart 当前仍是 Preview 依赖，必须精确锁版。升级只能发生在隔离 adapter/runtime 内，并经过伪 Provider、DeepSeek/OpenAI Compatible、Anthropic、流式取消、工具调用、Interrupt 和会话恢复契约测试；生产路径必须可回退到兼容运行时。
- 当前锁定的 Genkit Dart `0.15.1` 明确没有把本地 attached Agent 的取消信号传入正在进行的 `generate`。在 SDK 修复且开卷的模型矩阵验证通过前，`GenkitAgentRuntime` 不得成为默认运行时；不能用仅更新 UI 状态的“假取消”替代底层 HTTP 中止。
- 默认切换由 App 自有 `AiAgentRuntimeGate` 执行，而不是靠注释或人工约定。即使请求使用 Genkit Agent，也必须同时存在 runtime factory，并通过 attached 请求真实取消、Provider 矩阵、工具与 Interrupt/Resume、Trace/Snapshot、统一 Runtime 契约测试；任一条件缺失即确定性回退 `LegacyAiAgentRuntime`，并保留可观察 blocker 列表。
- Genkit `SessionStore` 与 `Artifact` 只承载运行时状态和事件引用，不替代 `AiChatSession`、`AiBookMindMap`、`AiBookGraph` 等产品事实；本地文件与 WebDAV schema 不跟随 SDK 类型变化。
- 产品 Artifact 共享最小信封但保留强类型领域 payload；Action、Command、Workflow、Artifact、Prompt 与 Renderer 各自版本化。PNG、PPTX、Markdown 等是可重新生成的派生文件，不进入 Journal；外部导出使用独立产品动作和平台保存确认。
- Genkit Interrupt/Resume 或 `toolApproval` 只能作为 `GenkitAgentRuntime` 对等待态的实现；App 的 Proposal、Policy、Command、Journal、Receipt 与领域 Artifact 必须在兼容运行时下同样成立。输入附件只绑定目标 Artifact，不授权任意后续文字；显式快捷入口可以按 Policy 预授权，自由对话提出的创建/修订动作首阶段必须对话内确认。

知识图谱 v3：入口与共享的 `AiBookStructureResolver` 保持不变；识别结果之后采用“生成目标 → 内容单元 → 构建任务”三层边界。`AiGraphScopePlanner` 把书内作品与全部可读单元整理为确定性选择计划，只给出正文/辅文的默认勾选建议，不能替用户删除范围；图谱管线只接收用户确认后的正文切片，负责多类型抽取、可选补漏、证据定位、消歧、合并与方向复核，并通过 checkpoint 回调发布不可变快照。实体与关系以稳定 ID 相连，关系图、家族树及实体详情都不得用名称作为身份键；家族树只消费父母/祖辈到子女的代际边，旁系亲属保留在关系图但不进入层级。电子书正文、标题、证据摘录和已知实体表一律作为不可信上下文注入模型。

本书 AI 采用组合边界，新增职责不得继续堆入阅读器 god-controller：

- `BookReaderController` 暂时作为兼容门面暴露 AI 命令，并持有阅读引擎回调；正文抽取缓存由 `AiBookCorpusCache` 独立负责，作品识别及“当前位置属于哪部作品”由 `AiBookStructureSession` 作为对话/大纲/图谱的唯一结构事实源。
- `BookStructureIndex` 位于共享 domain：Foliate 惰性扫描出版物标题、完整 nav 与全部 spine heading，只返回标题、层级、顺序、字符计数及 href/fragment/CFI。`AiBookStructureSession` 优先消费该索引；结构分类由纯 Dart 的候选生成器与分层求解器组成。顶层先识别出版物、季/辑/系列和套装等容器，再合成各容器中由分卷、作品树、中间分组、重复“标题→目录”和章节序号重启证明的强边界，最后只接受互不交叉的可定位作品范围；不再要求整本 EPUB 采用一种目录形态。局部合成方案仍与单本、全局树形和扁平方案共同评分，合成后仍有近分异构冲突则保持整本 `uncertain`，不伪造局部确定状态。锚点缺失、范围交叉是不可被分数覆盖的硬拒绝；App 书名、OPF 标题和原文件名均不可信，其中的册数只能低权重加分，不能删除、拼接或否决结构范围。多作品仍必须由出版物级合集信号、可定位范围和目录形态交叉佐证，拆成上/中/下的同一作品先合并。旧 `[§]` 正文标记只保留为兼容 fallback；结构索引与正文预算、AI 内容排除规则互不依赖。详见 [book-structure.md](./specs/book-structure.md)。
- `AiBookChatToolHost` 只依赖正文缓存、本轮冻结上下文和作品范围，不得依赖表现层 controller；即使阅读引擎忽略范围参数，也必须再次本地收窄，防止相邻作品正文泄漏。
- `AiChatService` 把供应商的单次输出限制视为传输分段而非回答失败：收到 `length` / `max_tokens` 后以同一冻结上下文自动续写、去重拼接到同一回答，并设置有界保护。流式传输只允许在首个可见文字前重试瞬时故障；首字后失败保留部分正文，不得从头静默重跑。表现层按节流频率保存 pending 回答检查点，终态写入必须排在检查点之后并覆盖它。
- AI 运行时采用“开卷确定性编排器 + 可替换模型适配层”。`AiRunState` / `AiRunEvent` 是 App 自有的纯 Dart 契约；回答正文与供应商可见思考过程分别采用**完整快照**而非不可回退 delta，支持自动续写去重拼接和消费者幂等重放。本书对话只暴露事件流，UI 不得自行推测运行阶段或把思考过程拼入回答正文。
- 对话、图谱与设置的模型和文件存储分别放置；JSON 原子写入、备份恢复与安全凭据不得混入模型类。生成数据面只经 `AiModelAdapter`，模型目录是独立只读 `AiModelCatalog`；旧 Provider 双栈不得重建。
- 对话发送状态和大纲/图谱任务状态按上面的目标运行时迁入独立 workspace/conversation controller；迁移前后均用 Widget 流程测试守住行为，不以 `part` 或跨文件私有字段制造形式拆分。
- `BookAiReaderGateway` 承担阅读快照到 Agent turn 的上下文、工具宿主、联网与追问桥接；`book_ai_chat_components.dart` 只放无业务状态的对话展示组件。`BookReaderController` 与 `book_ai_chat_sheet.dart` 不再通过 `part` 共享私有状态来伪装拆分。
- 大文件继续按可独立验证的组合边界拆分，不以 `part`、跨文件私有状态或只有一层转发的兼容门面充数：
  - `BookAiGraphWorkspace` 独占图谱 Tab 的视图/排序/折叠、生成确认、作品选择、实体详情、证据跳转及全屏路由；生成/取消/checkpoint 继续经 `BookReaderController` 既有 AI 应用门面进入 `AiGraphService`，不在 Workspace 复制图谱缓存或持久化状态。主 AI Sheet 只选择 Tab、组合对话/图谱工作区。
  - `BookAiMindMapCoordinator` 组合既有 `BookAiMindMapController` 与对话 Controller，独占附件、范围选择等待态、布局持久化、揭示与指针交互状态；`BookAiMindMapRoutes` 独占证据跳转和原生全屏路由。产品动作解析、授权、Journal 和 Workflow 调度迁入 `AiProductActionController` 与领域 Controller；主 Sheet 只提交 UI 事件和渲染结构化等待态，不复制提示词、Policy 或生成状态机。
  - `BookAnnotationsController` 独占批注列表、选择菜单状态机、数据库 watch、Foliate annotation bridge 与笔记操作；`BookSearchController` 独占搜索/图片查看状态和对应 bridge；`BookReaderPreferencesController` 独占排版偏好、字体存储与持久化；`BookReaderBridge` 独占 Foliate 页导航、seek 与正文读取回调。`BookReaderController` 组合这些职责，只保留阅读定位、书签、chrome、生命周期、AI 应用门面与 TTS 公共门面。
  - 系统听书继续由独立 `BookTtsController` 持有引擎、句游标、速率与播放循环；`BookReaderController` 保留既有 TTS 公共门面，避免修改 UI 与 Foliate bridge 契约。
  - 子 Controller 只通过公开构造依赖、不可变输入和显式回调协作；不得各自复制当前 section、locator、作品或会话状态。拆分不得改变 UI、AI 提示词、思维导图/图谱结构与持久化、WebDAV、阅读器行为或系统 TTS 行为。
- `tool/ai_runtime_harness.dart` 是运行时验收入口，通过 `flutter test tool/ai_runtime_harness.dart --reporter expanded` 运行：默认启动进程内伪 OpenAI Compatible 端点，验证普通回答、书内工具、产品 Proposal、授权/拒绝、结构化思维导图、续写和真实 transport 取消；只有显式设置 `AI_HARNESS_MODE=live` 及 BYOK 环境变量时才访问真实端点。Harness 不读取 Keychain、不打印正文/Key，输出机器可读 JSON 报告；通过 Genkit CLI 包装运行时还必须保留 Trace ID 供人工复核。协议迁移完成前，Harness 必须区分“现有行动事件已通过”和“授权控制链未实现”，不得把 Tool Call 当作授权验收。
- 图谱模型、文件存储、抽取、合并消歧、质量门和描述润色是独立职责。管线 orchestrator 只编排这些组件，拆分不得改变提示词、算法阈值、缓存 schema 或 checkpoint 时机。

- 产品范围见 [PRODUCT.md §6](./PRODUCT.md)，AI 总规格见 [specs/ai.md](./specs/ai.md)，产品动作控制协议见 [specs/ai-product-actions.md](./specs/ai-product-actions.md)。
- `lib/ai/`：`AiModelAdapter`（所有生成的单回合、原生工具调用与结构化输出边界）、`AiModelCatalog`（只读模型目录）、`AiSettings`（非机密、原子 JSON）、`SecureAiCredentialStore`（模型 Key + 搜索 Key 分槽）、`AiBookStructureResolver`（纯 Dart；把 TOC/spine/heading 事实归一为单本、分段单本、多作品出版物或不确定结构，供对话/大纲/图谱共享；章/篇标题及破折号连续副标题即使共享 spine/导航锚点也不是作品边界）、`AiGraphScopePlanner`（纯 Dart；把识别结果和完整内容单元变成用户可确认的范围计划）、选区语言 `AiLanguageService`、本书对话 `AiChatService`（最多四轮的原生 tool loop，非 LangChain；`get_toc` / `get_current_chapter` / `get_chapter` / `search_book` / `sample_book`）、`AiBookOutlineService`、`AiBookGraphService` + `AiGraphStore`、可选联网 `AiWebSearchService`（Tavily / Brave）+ `ai_chat/` 会话文件。
- 图书思维导图是本书对话的直接结构化生成，由 `AiBookMindMapService` 经 `AiWorkflowModelSession.completeJson` 完成一次所选范围调用。入口只匹配窄生成命令并保留用户原始提示；调用前复用 `AiBookStructureSession`：当前章冻结 Foliate 文档，普通单书一次发送完整有效正文，分卷/作品范围来自共享分层求解器，混合合集先合成各局部容器中的强边界，合成后仍冲突才进入确认。结构层只决定正文范围，不生成摘要、不抽样，也不向模型暴露候选分数。`segmentedSingleWork` 按既有分部/分卷范围依次生成，`multiWorkOmnibus` 和带候选作品的 `uncertain` 结构先由对话流中的纵向选择卡片展示作品/章节统计并等待选择，不打开 Dialog 或 Bottom Sheet。正文只移除设置中明确的出版外围标题、版权/目录信号和纯标题容器；Foliate 的多标题切片先初始化完整 `body` Range，再设置标题边界，最后一个同级标题后的正文不能丢失。供应商上下文不足时明确失败。模型只返回含 `contentKind`、`organizingPrinciple` 与扁平节点的主题树 Schema；同一次生成先选择一个主导组织原则，再使用书型专用编辑模板和少量结构示例约束同级平行、层级职责、去重及目录反例。正文规模只用于输出 token 容量，不再向模型提示目标节点数。App 校验父引用、环/孤儿和非空文本，对引用有效的多根 forest 合成一个确定性根，随后重新分配稳定 ID，并把能逐字定位的可选引文转换为阅读器坐标。旧 `BookMindMapWorkflow` 的 batch/reduce、checkpoint、`AiBookMindMapStore`、`ai_mind_map/` 和重复 WebDAV记录全部删除；唯一持久化事实是 `ai_chat/` 消息附件。对话卡片与全屏画布继续共享同一产物和布局回调；每个画布按自身当前折叠状态，通过内部独立 `RepaintBoundary` 导出完整未变换画布。桌面使用系统保存面板，移动端保存到相册，并按最大尺寸与像素预算降低超大图导出倍率以避免内存峰值。普通聊天 Mermaid 与知识图谱保持独立。详见 [ai-mind-map.md](./specs/ai-mind-map.md)。
- AI 回复的富内容渲染保持在 `presentation/widgets/reader/`：`AiResultBody` 负责 Markdown AST 与扩展块分发，代码、图形、媒体分别由独立 Widget 承担；Mermaid 通过随包原生 headless 引擎离线生成 `resvg-safe` SVG，声明式 chart 先转为受限 Mermaid 语法。屏幕显示使用 Flutter 原生 SVG surface，避免为列表中的每张图常驻创建 WebView；Merman 仍放在 `<style>` 类选择器中的 mindmap 节点、连线和文字颜色，必须在隔离线程内按当前主题物化为元素属性，并移除 `flutter_svg` 不支持且已无渲染作用的 `<style>`、`<marker>`、`<filter>` 及其引用后再交给原生 surface，避免默认黑色与反复告警。图形主题由 Widget 把当前语义 `ColorScheme` 编译为 Merman options，缓存键必须包含主题，皮肤或强调色变化时重新生成；不得让渲染引擎直接依赖 `BuildContext`，也不得写死默认暖橙。渲染器不得进入 Provider/Service，也不得执行模型提供的 HTML 或脚本；未知语言和解析失败统一降级为可复制源码块。
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
| 对话产品工具 | 当前兼容路径中，未附加产物的自由输入只进入 `AiChatService` 的同一受控模型回合；除五个只读书内工具外，App 按本轮上下文动态声明 `create_book_mind_map` / `revise_book_mind_map`。模型不调用产品工具时正常回答；调用时必须作为该回合唯一的终止工具请求，`AiRunOrchestrator` 发出类型化产品行动事件，由 Controller 再校验并启动确定性 Workflow。若模型未调用产品工具却在正文中明确声称已交付原生思维导图，`AiChatService` 撤回该草稿并进行至多一次仅暴露产品工具的协议修复。当前“继续修改”附件会把后续输入直送修订链，这两处均属于 Product Action Protocol v1 要替换的兼容行为，不得作为目标架构继续扩展。普通模型回合只暴露 `artifact_1` / `work_1` 等临时别名，不暴露数据库 ID；原生附件以 `artifactId / sourceArtifactId / revision` 追踪谱系，普通 Mermaid 不进入产物目录 | 不增加前置意图模型、自由文本关键词路由、标题包含匹配、`targetMode` 规则矩阵或第二套 transport。模型 Product Tool Call 只能产生 Proposal；目标实现必须经 App Policy 得到 allow、对话内确认、补充或拒绝结果，签发并持久化 `AiAuthorizedCommand` 后才可启动 Workflow。Controller 使用发送前冻结的章节、作品、manifest、会话 `workKey` 和产物目录重新映射别名，并校验同书范围、预算、取消和运行状态；这些校验不替代授权。附件只绑定冻结的真实产物身份，不把普通评价、提问或否定句授权为修订。读工具与产品终止工具不得在同一模型响应中混用。普通聊天 Mermaid 和图书原生导图保持独立；完整迁移见 [ai-product-actions.md](./specs/ai-product-actions.md) |
| 开卷编排器 | `AiRunOrchestrator` 统一预算、取消、超时、模型/工具/续写计数、checkpoint hook 与错误分类；对话为最多四轮的受控 Tool Agent | 不把作品定位、权限、持久化或 UI 状态交给模型框架；不做多 Agent |
| 模型适配层 | `lib/ai/adapters/` 隔离 `GenkitOpenAiModelAdapter` 与 `GenkitAnthropicModelAdapter`；精确固定 `genkit 0.15.1`、`genkit_openai 0.3.7`、`genkit_anthropic 0.2.11`。App 自有 `AiModelAdapter` 只表达单次回合、原生工具请求、可选推理 delta、推理展示类型、工具连续性元数据和结构化 JSON；Anthropic 模型列表仍走只读 `GET /v1/models` transport；可重试 transport/HTTP 错误只允许在首个可见文本或推理输出前自动重试一次。Provider 推理字段由 adapter 内的能力策略映射：DeepSeek `thinking.type`，Anthropic `thinking` adaptive/disabled，OpenAI / xAI / Ollama `reasoning_effort`，自定义兼容端点开启时尽力发送通用字段、关闭时完全省略。锁版 `genkit_openai` 会把 schema 一律映射成 OpenAI `json_schema`；DeepSeek 只接受原生 `json_object`，因此隔离的 HTTP decorator 只对 DeepSeek 把该字段降为 `json_object`，并把同一 JSON Schema 注入模型消息；Genkit 仍负责 JSON 解析，Schemantic/Workflow 继续执行结构与业务校验。OpenAI Compatible 返回的 `reasoning_content` / `reasoning` / `thinking` 与 Anthropic `ReasoningPart` 统一映射为 App 事件；供应商要求跨工具回合保留的推理内容、签名和不可见 `redacted_thinking` 必须按原顺序回传 | Genkit、插件 SDK 与供应商协议类型不得进入 UI、controller、数据库和备份 schema；不得声称展示完整思维链；不得把 DeepSeek 兼容分支扩散到其他 Provider、改成 fence 截取或绕过 schema/业务校验；插件或供应商协议升级必须重新跑对应适配器协议、取消和异常终态测试 |
| 协议选择 | OpenAI / DeepSeek / Grok / 自定义 / Ollama 使用 Genkit OpenAI Compatible adapter；Anthropic 使用 Genkit Anthropic adapter；适配器缺失或端点不支持时本轮明确失败 | 不做跨协议隐式回退、手写 Messages 对话 adapter、fenced JSON 或旧 Provider 对话回退；不放宽五个只读工具、冻结作品范围和本地参数预算 |
| 确定性工作流 | 词典/选区翻译使用无工具 `streamTurn`；大纲、图谱和图书思维导图的结构化输出使用各自 Schemantic schema + `completeJson`；所有模型调用由 `AiWorkflowModelSession` 报告调用次数/usage 并统一关闭 adapter。图谱保留自己的增量 checkpoint；思维导图是按自然书籍范围的一次直接生成，不再拥有 batch/reduce、checkpoint 或独立结果缓存。Anthropic constrained output 固定关闭 thinking，普通流式调用仍服从用户偏好；DeepSeek 使用官方 JSON Object mode，schema 指令、Genkit JSON parser 和基础树校验缺一不可。结构化 JSON 无法解析、输出截断或树拓扑非法时明确失败，不自行补逗号、解 fence、正则恢复或接受残缺 JSON | 不把批处理改造成自由 Agent 或 Genkit defineFlow/Agent，不混用图谱/思维导图/聊天 Mermaid 数据，不自行修复 JSON 或引入第二套生成 transport |

`AiRunEvent` 只表达模型与任务运行事实，不是持久化 schema。Product Action Protocol 迁移后，Proposal、Decision、Command 与 Receipt 可以投影为新的类型化运行事件，但可恢复授权和幂等事实只写 App 自有 `AiActionJournal`，不得靠回放模型文字重建。`AiRunCheckpoint` 自身带版本，但 payload 仍由既有工作流存储负责；当前图谱继续写原有 `AiBookGraph` 快照，不把临时事件写入 `ai_chat` / Drift / WebDAV。对话终态可把供应商公开的推理过程或推理摘要写入 `AiChatMessage.reasoningContent`，并以 `reasoningKind` 区分展示文案，随同一会话 JSON 和 WebDAV 快照保存；它与回答正文分栏、默认折叠，不参与回答复制和后续普通消息历史。签名等协议连续性元数据只存活于当前运行，不写入会话或备份。Genkit 内部 trace 只允许留在 adapter 边界，产品运行事实以 `AiRunEvent` 为准，产品授权事实以 Journal 为准。

思维导图附件只为对话轮次绑定可信目标，不把任意后续文字直接授权为修订。Agent 可以基于附件正常回答，也可以提出修订 Proposal；Policy 确认用户确实要求修改并取得授权后，修订 Command 才占用发送槽位、锁定 `targetArtifactId + expectedRevision`，并冻结附件所在会话的 `workKey`。正文范围恢复下沉到 Controller 预检，Widget 只能提交结构化附件事件、用户指令和确认结果。Controller 不得把一个活动生成 Future 复用给参数不同的后续请求。恢复正文范围时，附件 `workKey == null` 表示整本出版物，非空值必须在当前 manifest 中精确匹配，匹配失败即中止，不得退回当前阅读作品。上一版导图与正文都属于不可信引用数据；并发修订使用 revision compare-and-set，旧 Command 不得覆盖新版本。

对话 composer 只允许一个提交入口：Flutter `EditableText.onSubmitted`、发送按钮、快捷入口和重试最终都经过同一互斥锁。桌面 Enter 不得同时由外层 `Focus.onKeyEvent` 再触发一遍；真实输入在首次提交时冻结，输入连接在任何异步结构/搜索/模型工作前结束并跨过当前 frame，防止 macOS IME 在 semantics/layout 阶段回写 controller。重复平台 action 不得产生第二个 `turnId` 或重复 Workflow。

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
