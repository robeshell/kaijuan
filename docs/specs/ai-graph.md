# 本书知识图谱（AI M5）

| | |
|--|--|
| **状态** | 已实现（M5；v3 范围与 Genkit 结构化运行时已收口） |
| **日期** | 2026-08-10 |
| **PRODUCT** | [§6](../PRODUCT.md) · [§10.2](../PRODUCT.md) |
| **相关** | [ai.md](./ai.md)、[webdav-backup.md](./webdav-backup.md)、[reader-chrome.md](./reader-chrome.md)、[book-reader.md](./book-reader.md) |
| **引擎** | 图书 reflow only（v1）；漫画页图 AI 另案 |

> 产品状态只改 [PRODUCT.md](../PRODUCT.md) §6。本页写交互、边界、任务切分与验收。  
> M5 在 [ai.md](./ai.md) §9 的约定：「章级实体关系 + 出处；列表优先，图可视化可简」。

---

## 1. 结论（先读）

**知识图谱 = 一本书的实体（人物 / 地点 / 事件 / 组织 / 物件 / 概念 / 非人角色）+ 关系 + 出处的本地缓存视图**，是「本书 AI」工作区的第二个 Tab（对话 / 知识图谱）。

| 决策 | 取值 | 理由 |
|------|------|------|
| 范围 | **用户显式确认**：多作品文件先选作品，再选内容单元；程序只提供默认勾选建议。`allowUnreadContext` 继续限制未读内容是否可进入任务 | 出版结构与内容清洗都不可能仅靠标题规则百分之百可靠，最终决定权必须在用户 |
| 生成 | **章级增量**：按章节对比已处理集合，只抽新章；断点续跑 | 数十万字一次吞全书成本高、易超时；随读随抽体验好 |
| 协议 | **Schemantic schema + Genkit structured output**，不引 LangChain / 自由 Agent | OpenAI Compatible / Anthropic 分别由精确锁版 adapter 处理；App 仅消费统一结构化结果 |
| 存储 | 按 **contentHash** 的本地文件 `ai_graph/$hash.json`；随用户主动 WebDAV 快照备份；**Key 永不备份** | 与 `ai_chat/` 同构，备份合并逻辑可扩展复用 |
| 数据库 | **不用图数据库**（Neo4j 等） | 单书数百～数千实体、数千关系，JSON + 内存过滤绰绰有余；图库只在多书/图算法时才值得引入 |
| 可视化 | **列表优先，力导向图可简**（v1 允许只上列表） | ai.md §9 M5 已定；图渲染库决策见 §7 |

### 当前实现状态

- **G1–G4 已全部落地**：数据模型与抽取管线（`lib/ai/ai_graph.dart` + `ai_graph_service.dart`，含章级增量 / 合并 / 断点续跑）、图谱 Tab（`book_ai_chat_sheet.dart` 实体列表 / 文件内合订著作列表）、关系图（`book_ai_graph_view.dart` + `flutter_graph_view`）、全屏视图（`book_ai_graph_fullscreen.dart`）、WebDAV `aiGraphs` 备份（`backup_service.dart`）。
- 实现时的命名与 §9 规划略有出入（见 §12）；本页交互与验收描述仍然有效。

---

## 2. 目标与非目标

### 做

- **实体抽取**：`person / location / event / organization / item / concept /
  creature` 七类始终合法。展示方案只调整抽取侧重，不能改变 schema。UI 将后三类
  合并为“事物”索引，避免入口过载；底层仍保留独立类型，防止魔法物件、思想概念、
  非人角色被硬塞成地点或人物。
- **关系抽取**：类型化关系（小写 `snake_case` 词表，如 `father_of`、`married_to`、`work_at`、`lives_in`、`participates_in`），双向语义（抽到 `A-B` 时 UI 可双向展示）。
- **出处（证据）**：每条实体与关系至少一条原文证据；点击证据跳回书内位置（`BookLocator`：section + progressInSection）。
- **章级增量**：只对新章节抽取并合并进已有图谱；进度、停止、断点续跑、重生成（= 删除重建）。
- **辅文推荐排除**：参考书目 / 附录 / 索引 / 致谢 / 后记 / 年表，以及前言 / 序 / 自序 / 凡例 / 出版说明 / 编者按 / 导读 / 题记等，只由规则标为“建议排除”并默认取消勾选。它们仍须出现在范围列表，用户可以重新勾选；程序不得在选择器之前删除。
- **文件内多作品选书**：多作品出版物生成图谱前显示完整作品列表，用户可以直接选择任意一部，不依赖当前阅读位置。作品范围由共享的 `AiBookStructureResolver` 读取 TOC 层级、导航锚点、spine 与 heading 等确定性事实产生，不依赖大纲或额外 AI 请求；普通单本与单本分部/分卷不暴露为多作品列表。证据不足或同一 spine 内无法定位作品时保持不确定并进入完整单元手选，不得静默把多个作品混成一个任务。
- **多作品图谱存储与交互**：每部作品一个独立图谱文件（`ai_graph/$hash.$workKey.json`，workKey = `s` + 起始节；整本书图谱仍是 `$hash.json`），**互不覆盖**，可逐本生成/查看/删除。图谱 Tab 对文件内多作品出版物始终显示**作品列表**：每行 = 作品名 + 状态（已生成 / 未生成 / 生成中 / 失败）；当前阅读作品可以标注但不能自动打开或替用户选择。点击已生成项进入图谱，点击未生成/失败项进入范围确认。详情顶部提供“全部作品”返回。WebDAV 备份/恢复按 workKey 保留（行字段 `workKey`）。
- **生成范围选择**：作品边界先由共享结构识别确定；确认界面列出该作品内全部内容叶子。章节显示目录名或文档标题，禁止显示 `OEBPS/Text/*.xhtml` 等内部资源路径；每项包含勾选状态与“正文 / 建议排除 / 不可读取”说明，支持整行切换、独立滚动与持续可见的已选计数。“选择推荐 / 全选可读项 / 清空”收进单一“批量选择”菜单；弹窗标题下不重复堆叠“选择内容范围”“内容单元”和通用说明，排除建议直接跟随对应内容单元展示。展示方案分析是可选设置，加载失败不得阻塞范围确认。
- **防剧透**：`allowUnreadContext` 只决定本次生成可读取的正文范围。关时未读章节不进入生成；开时生成并保存全书图谱。展示以图谱自身持久化的 `includesUnread` 与实际数据为准，不再使用另一台设备的本地开关或尚未恢复的阅读位置二次裁剪缓存。
- **实体卡**：描述（依据驱动的 3–5 句）、别名、关系列表、证据列表、章节频次。
- **缓存与备份**：按 `contentHash` 落盘；手动 WebDAV 快照上传，恢复时按书合并、本地优先、不覆盖；Key / 搜索 Key / WebDAV 凭据永不备份。

### 不做（本能力内）

- 漫画 OCR / 气泡识别（远，另案）。
- 跨书知识图谱、全局知识库、自动打标签（Readwise 式，优先级低）。
- 图算法（社区检测、PageRank、路径查找）与 Neo4j / GraphRAG 类框架。
- 时间线 / 世界观地图 / 势力图（v2 候选；本页 §10 预留字段即可，不做界面）。
- 图谱进入本书对话的上下文（对话已有自己的 tool 协议；图谱只是缓存产物）。
- 阅读正文里的实体高亮（v2 候选）。
- 由对话「画关系图」作为主入口（对话输出不可靠、不可缓存复用；主视图用确定性图谱数据，对话入口至多作补充引导）。

---

## 3. 数据模型

### 3.0 schema v2 正确性契约（2026-08）

图谱缓存升级为 `version = 2`。v2 把“实体身份”和“显示名称”分开：

- `entityId` 是稳定、无展示语义的内部主键；`name` 只负责显示。
- 关系以 `sourceId + targetId + type` 为唯一键，同时冗余端点名称用于迁移和降级展示；改名不再改变关系身份。
- 同名同类型实体允许并存。别名索引为 `alias -> Set<entityId>`；只有唯一命中才可自动解析，多个命中进入歧义状态，禁止覆盖或强并。
- 抽取输出先视为 mention。`identityHint`（身份/角色提示）、本章关系和证据共同参与 mention → entity 的消歧；它不是跨章主键。同一文本单元多个同名同类行若共享明确别名则视为重复 mention 并融合；没有共享别名且身份线索不同时才拆分。跨文本单元仅有一个同名候选时，即使提示措辞漂移也复用已有 ID。
- v1 缓存读取时迁移为确定性的 legacy ID；迁移只保证继续展示，不声称恢复 v1 已经发生的同名误并。

生成与展示同时遵守以下边界：

- 正式实体/关系至少携带一条 `spanResolved=true` 的原文证据；只有章节级线索的候选进入 `needsReview`，不进入默认列表、关系图或家族树。
- 每章顺序合并后产生一次 graph checkpoint，由 controller/repository 原子落盘；停止、网络失败和应用重启均从最后 checkpoint 续跑。
- description、aliases、关系和证据保留来源范围；生成阶段按当时的已读边界裁剪输入，展示阶段不再按设备当前位置重复裁剪。
- 正文、标题、证据摘录和已知实体表统一放在 `<untrusted_context>` 中；Genkit 按当前步骤的 JSON Schema 约束输出，App 再执行证据、稳定 ID、关系端点和范围校验；不接受普通文本包装、fence 或正则恢复结果。

### 3.1 实体（`AiGraphEntity`）

```dart
class AiGraphEntity {
  final String entityId;        // v2 稳定内部主键
  final String name;            // canonical 名（大小写/繁简已规范，只增不删）
  final String identityHint;    // 同名消歧提示，不作为 UI 主标题
  final AiGraphEntityType type; // person/location/event/organization/item/concept/creature
  final List<String> aliases;   // 别名，并入 canonical 索引
  final String description;     // 依据驱动的 3–5 句
  final List<AiGraphEvidence> evidence; // 至少 1 条
  final Map<int, int> chapterFreq;      // sectionIndex -> 已定位出处数（不是原文词频）
  final int firstSection;               // 首次出现章节（演化/防剧透用）
  final int lastSection;                // 最后出现章节
}
```

- **唯一键 = `entityId`**；同名同类型实体可以同时存在。
- 同名歧义（同一文本单元内两个不同的人同名）：靠 `identityHint` + 关系端点提示区分；跨章唯一同名候选直接复用，避免模型把同一人的不同身份描述拆成多个实体。

### 3.2 关系（`AiGraphRelation`）

```dart
class AiGraphRelation {
  final String sourceId;      // v2 entityId
  final String targetId;
  final String source;        // canonical name
  final String target;        // canonical name
  final String type;          // snake_case 词表，如 married_to
  final String description;   // 一句话，依据驱动
  final List<AiGraphEvidence> evidence;
  final double weight;        // 证据条数 / 章节覆盖数，合并时平均
}
```

- **唯一键 = `sourceId + targetId + type`**；无向关系按 ID 规范化，显示名称不参与身份判断。
- 关系类型：v1 内置常见词表（血缘、婚姻、友谊/敌意、雇佣、隶属、居住、参与、认识等），**不限制**模型提出新类型（词表之外原样保留小写 snake_case）；UI 仅对已知类型着色。

### 3.3 证据 / 出处（`AiGraphEvidence`）

```dart
class AiGraphEvidence {
  final int sectionIndex;        // spine section（1-based，与 BookLocator 对齐）
  final String quote;            // 原文连续片段（LLM 输出，程序校验）
  final double progressInSection; // 程序回填的段落进度（BookLocator 同构）
  final bool spanResolved;       // quote 是否在原文中定位成功
}
```

- **LLM 只输出 `sectionIndex + quote`**；`progressInSection` 由程序在原文中做归一化搜索（去空白、统一全半角/大小写）后回填。
- 定位失败时降级为章节级证据（`spanResolved = false`），**不丢弃**；抽取器在后续批次不重复该引文。

### 3.4 图谱包（`AiBookGraph`，即落盘文件）

```jsonc
{
  "formatVersion": 1,            // 结构演进；升级后旧缓存不展示，走重生成
  "contentHash": "sha256…",
  "generatedAt": "2026-08-05T…",
  "coveredSections": [1, 2, 3],  // 已抽取章节；增量与断点续跑的依据
  "entities": [ /* AiGraphEntity[] */ ],
  "relations": [ /* AiGraphRelation[] */ ],
  "pendingAliases": [ /* 待审别名合并候选 */ ]
}
```

---

## 4. 抽取管线（`AiBookGraphService`）

复用 `AiBookStructureResolver` 的文件结构结果与用户确认后的 `AiBookSectionSlice` 正文单元；模型请求统一经 `AiWorkflowModelSession` / `AiStructuredOutputAdapter`，**不引 LangChain，也不让多个模型互相分工**。

### 4.1 流程

```text
输入：用户确认的 sections（细粒度逻辑单元）+ 已保存的生成范围
  → 范围裁剪：只消费已确认单元；确认窗中的勾选结果是最终输入，确认后不得再按 renderer 当前进度暗中移除单元
  → 已处理集合 = coveredSections ∩ 范围内；只对新 section 走抽取
  → 每 section 切成 800–2000 token 的 chunk（相邻 5–10% 重叠）
  → 每 chunk 一次 Genkit 结构化抽取调用（温度 0；带 sectionIndex）
  → JSON Schema 校验 → 业务校验（枚举 + 关系端点 + 引文存在性）→ 截断时有界分片，章节失败按原 checkpoint 策略隔离
  → 程序回填 quote → progressInSection
  → 顺序增量合并（见 4.2）→ 落盘 ai_graph/$hash.json
  → onProgress（completed/total = 章节数）
```

- **chunk 预算**：输出 `max_tokens` 设输入的 1/3–1/2；单章过长时先抽首尾再补中间，不能由书前部耗尽上限。
- **并行与限流**：chunk 间可并行，但按 TPM / 连接数做信号量；停止 = `CancelToken`（复用现有 `ai_outline.dart` 的取消协议），已完成的章节结果**保留**。
- **范围与增量**：`allowUnreadContext` 从关切到开 → 只补抽新增未读章节（coveredSections 并集）；从开切到关 → 已保存图谱内容与展示均不变，开关在下一次生成/补充时生效。
- **超长出版物**：范围选择器必须保留全部可读单元；150 万字符预算只用于正文样本。超出预算时按所有单元均衡保留样本，禁止按阅读顺序截断后部单元。

### 4.2 合并（顺序增量共指消解）

每批抽取结果**先落盘再合并**（中间产物可审计、可重放、天然断点）：

1. **对齐**：用维护中的别名索引（按实体类型分桶）把本批实体名映射到已有节点；无歧义别名并入已有实体，未匹配才建新节点。
2. **证据追加**：实体/关系命中已有唯一键 → `evidence` 追加、`chapterFreq` 累加、`first/lastSection` 更新、描述**不覆盖**（记入待合成列表）。
3. **描述合成**：同一实体证据超过阈值后，由一次 LLM 调用按证据合成单一描述（GraphRAG 式 `SUMMARIZE`），冲突时以证据为准；失败则保留旧描述并标 `needs_review`。
4. **关系合并**：同 `(source, target, type)` → `weight` 平均、证据追加。
5. **canonical 名只增不删**；重抽不重命名（保证旧数据可追溯）。
6. 全部完成后可选执行一次 **幻觉过滤**：实体/关系若无任何证据（`evidence` 为空或全部 `spanResolved=false`）标记，UI 不默认展示。

### 4.3 抽取 schema（Schemantic 结构化契约）

```jsonc
{
  "entities": [
    {
      "name": "伊丽莎白·班纳特",
      "type": "person",                    // person|location|event|organization|item|concept|creature
      "aliases": ["伊丽莎白", "丽萃"],
      "description": "班纳特家二小姐，聪慧、有主见……",
      "evidence": [{"section": 3, "quote": "……原文连续片段……"}]
    }
  ],
  "relations": [
    {
      "source": "伊丽莎白·班纳特",
      "target": "达西先生",
      "type": "married_to",
      "description": "小说结尾两人订婚结婚",
      "evidence": [{"section": 59, "quote": "……"}]
    }
  ]
}
```

- 所有字段必填；`evidence` 至少 1 条（防空证据污染）。
- **质量门槛**：用 5 个代表性章节制作人工标注样本，检查格式、引文定位、准确率和召回率，再调整提示词与模型组合。

### 4.4 调用规模与费用

- 调用次数由用户选择的内容单元、每节分片数、可选缺漏补查和关系复核共同决定，不能用固定次数或固定金额承诺。
- App 记录实际模型调用与可获得的用量信息；按节保存进度，使失败后只补未完成内容。缺漏补查只有在已抽取结果确实缺少某类重要实体时才执行一次有界调用。

---

## 5. 质量保障（正确性）

> **正确性是流程属性，不是产物属性**：不追求模型「一次抽对」，而是用证据可审计、程序校验、评测门槛、增量纠错四层把关，让每条关系都可回查、可纠错。

### 5.1 证据锚定（抗幻觉地基）

- 每条实体与关系**必须携带原文证据**（`sectionIndex + quote`）；`progressInSection` 由程序回填（§3.3）。
- `spanResolved = false`（证据定位失败）→ 条目**不默认展示**，标「引用待确认」；无证据条目直接丢弃。
- **幻觉过滤**：实体必须实际出现在原文中才保留（防模型把预训练知识如「《三国》有诸葛亮」漏进无关书）；抽取 prompt 硬性约束「仅基于给定原文，禁用书外知识」，正文全部作为 `<untrusted_context>` 引用材料（ai.md §7.4）。

### 5.2 程序校验（模型输出是候选，程序是裁判）

1. **结构校验**：七类实体枚举、关系类型词表、字段必填、`evidence` 非空。
2. **引文存在性**：quote 在原文归一化搜索；搜不到 → 重试（≤2 次）或降级为章节级证据，绝不静默收下。
3. **唯一键幂等**：`entityId`、`sourceId+targetId+type` upsert，重复批次不产生脏数据；证据按 `(sectionIndex, normalizedQuote)` 去重。
4. **歧义拒绝**：同名异人（两个「王五」）→ 映射待审名单，**绝不合并**——误并是关系图最脏的错误。

### 5.3 共指消解（防分裂与误并）

- alias→canonical 顺序增量缓存**按类型分桶**（§4.2）：同一人物别名并入；跨类型同名不并。
- 「分裂」（同一人拆两节点）靠别名归并消解；「误并」（两人并一节点）靠歧义拒绝 + 手动 override（§5.5）兜底。
- canonical 名只增不删；歧义别名映射 null 不强并。
- **合并后复核 pass（v2 候选）**：参照 ai-knowledge-graph（robert-mcdermott）的实体标准化独立 pass——全部抽取完成后由一次 LLM 调用批量复核别名归并正确性（同义不同名漏并 / 同名异人误并），仅产出待审建议、不自动改数据（进 `needs_review` 队列，由 §5.5 override 层采纳）。v1 用顺序增量已够，此 pass 是质量增强、非必需。

### 5.4 冲突与时间演变

- 同一对实体的关系跨章变化（爱→恨、未婚→已婚）**可能是真实剧情而非错误**：冲突**追加证据、不覆盖**，描述由合并 LLM 依据证据合成。
- 无法调和的标 `needs_review`，进复核队列；关键关系**多章证据聚合**（证据数 ≥ 2 提升展示权重），单章孤证降权。
- 关系方向错误（A 是 B 之父 vs 反向）无法程序判定，靠评测门槛（§5.7）与人工抽测把住。

### 5.5 UI 可审计与手动修正

- 每条关系/实体卡**可展开证据、点跳原文**（§6 交互）——用户一秒可验证对错，是最强的正确性保证。
- 实体删除（v1）/ 别名手动合并拆分（v2）作 override 层：可撤销、**不污染抽取数据**（重生成不清除）。

### 5.6 持续监控

- 生成后**抽样 1% 语义复核**（人工或 LLM judge），发现系统性偏差即调 prompt。
- 章级增量让问题**只影响新章**：改 prompt 后重抽新章即可，不用全书重来。

### 5.7 人工标注样本验收指标

用 **5 个代表性章节制作人工标注样本**，跑通以下指标再调整提示词与模型组合：

| 指标 | 含义 | 门槛建议 |
|------|------|----------|
| schema 合法率 | 输出通过校验的比例（可含重试） | ≥ 95% |
| quote 定位率 | 证据在原文定位成功 | ≥ 90% |
| precision | 抽出的关系真实存在（幻觉控制） | ≥ 90% |
| recall | 书中重要关系被抽到（遗漏控制） | ≥ 70%（长尾关系可低） |
| 方向错误率 | 关系方向错误的占比 | ≤ 5% |
| 误并 / 分裂率 | 人工抽检样本中节点合并错误 | ≤ 2% |

不达标 → 调 prompt / 换便宜模型组合再测；上线后每批新章按 1% 抽测维持。

---

## 6. 交互（知识图谱 Tab）

```text
本书 AI → 知识图谱
  → 未生成：范围说明 +「生成图谱」（含 stop/进度）
  → 生成中：章节批次进度 +「停止」（保留已完成章节）；状态条固定在图谱页签顶部、位于滚动内容之外，手机滚动位置、空快照或旧内容都不得遮掉它
  → 已生成：顶部范围 badge + 视图切换（实体列表 | 关系图）
       → 固定索引：人物/地点/事件/组织/事物；可搜索，每类实体使用独立的排序策略
       → 探索层：关系图/家族树；AI 仅推荐首次视图，不改变固定导航顺序
       → 关系图（可简）：力导向；节点=实体（类型着色）；边=关系（类型着色）
       → hover 高亮邻居（桌面；移动端点击聚焦）
       → 点击实体 → 实体卡：描述 / 别名 / 关系列表 / 证据列表（点证据跳原文并关面板）
       → 实体卡底部：前往原文（按 firstSection）；更多：删除该实体（合并错误时手动修正）
       → 顶部操作：重新生成（= 删除重建）；删除图谱
```

- **范围 badge**：按保存图谱标记展示；`includesUnread=false` → 「生成时已读范围」，`includesUnread=true` → 「全书」。不能用当前设备开关改写已保存图谱的范围标签。
- **跨设备展示一致性**：controller 直接校验并展示保存图谱，不基于当前设备设置或 renderer 的临时 section 重新生成 read-safe snapshot；因此桌面生成并备份的全书图谱在移动端仍显示同一实体与关系数量。
- **空快照不是成品**：没有任何可展示实体或关系的缓存不得进入人物/地点/事件等全 0 索引，也不得仅凭 `coveredSections` 判定增量工作已经完成。界面显示“尚无有效图谱数据”与重新生成入口；下一次生成自动清空这份空覆盖记录并重新抽取正文。
- **所见即所得的范围**：手机、平板、折叠屏和桌面端在确认窗显示并勾选的章节，必须原样进入抽取管线。阅读位置尚未恢复、停在封面或处于所选范围以前时，不得把已选工作集裁成 0；若内部工作集意外为空，应作为错误暴露，不能保存成“生成成功”的空图谱。
- **分类排序契约**：排序是展示层策略，不依赖生成时数组恰好的顺序。用户的选择按视图独立保留。

  | 视图 | 默认顺序 | 可选顺序 |
  |---|---|---|
  | 人物 | 涉及章节（降序） | 涉及章节、关系数量、出处数量、首次出场 |
  | 地点 | 首次出现 | 首次出现、涉及章节、出处数量 |
  | 事件 | 情节顺序 | 情节顺序、重要程度、涉及章节 |
  | 组织 | 关系数量（降序） | 关系数量、涉及章节、出处数量、首次出现 |
  | 事物 | 涉及章节（降序） | 涉及章节、关系数量、出处数量、首次出现、实体类型 |

  「涉及章节」=`chapterFreq.keys.length`；「出处数量」=`evidence.length`（它不是原文词频，禁止标成“出现次数”）；「关系数量」=去重后的入边+出边数；「首次出现/情节顺序」先比较 section，同一 section 再比较最早已定位证据的 `progressInSection`。所有比较器都必须提供确定性次级键，不得继承缓存或生成顺序。
- **无障碍等价入口**：关系画布不是唯一操作路径。嵌入视图与全屏视图都必须提供可聚焦、可键盘操作、可被读屏识别的实体列表；画布只承担空间探索。列表项可打开与画布节点相同的实体卡。家族树节点、折叠区和动态进度暴露名称、按钮/展开状态与 live region。
- **颜色与排版**：类型色只作为圆点、图形或边框等冗余提示；小字号标签正文使用主题语义文字色并满足 4.5:1。关系图和家族树的关键关系文字初始显示不小于 12px，自动适配不得把可读性完全依赖于手动放大。
- **窄屏导航**：人物/地点/事件/组织/事物索引允许横向滚动或换行，不以淡出截断隐藏标签；全屏缩放说明放在画布内的可消退提示中，窄屏 AppBar 只保留标题和操作按钮。
- **手动修正 override 层**：实体别名可手动合并 / 拆分（如「孙悟空 = 美猴王」），覆盖层与抽取数据分离、可撤销、重生成不污染（v1 最小实现：合并 = 追加别名到目标实体并删除被并实体；拆分 = 恢复抽取原始名）。不强求：v1 允许只做「删除实体」，别名手动合并留待 v2。
- **停止 / 重试**：失败章节提供「重试本章」；停止后保留已生成章节（与大纲一致）。
- 图谱 Tab 复用对话/大纲的**生成物语义**：结果不因关闭面板取消；读者主动停止或退出阅读器才取消；重新打开直接展示缓存。

### 状态与文案

| 场景 | 文案草案 |
|------|----------|
| 未生成 + allowUnreadContext 关 | 「图谱覆盖已读章节（第 1–N 章）。开启『允许未读上下文』可分析全书。」+「生成图谱」 |
| 未生成 + allowUnreadContext 开 | 「将分析全书生成人物、地点与事件图谱。」+「生成图谱」 |
| 生成中 | 页签顶部固定状态条显示当前阶段、章节进度 +「停止」；状态条不随内容滚动（停止后保留已完成章节） |
| 已生成但为空 | 不显示全 0 索引；提示“尚无有效图谱数据”，允许直接重新抽取，旧 `coveredSections` 不得跳过正文 |
| 已生成 | 范围 badge + 实体数 / 关系数 +「重新生成」「删除图谱」 |
| 无证据实体 | 实体卡标记「引用待确认」；列表默认不展示 |

---

## 7. 可视化与渲染（v1 决策）

- **v1 允许只上实体列表**（ai.md M5「列表优先，图可视化可简」）；关系图作为可延后的子项。
- 若做关系图，首选 **`flutter_graph_view`**（力导向布局质量好、`vertexPanelBuilder` 即实体卡雏形、数据转换器与节点/边模型天然匹配）；`graphview` 备选（不支持连线点击）；自研 CustomPainter 兜底（2–4 周，非必要不上）。
- 大图（>500 节点）**局部图优先**：默认显示当前实体 1–2 度邻域，避免整本图谱过载。
- 渲染代码跨平台一套；差异化只在输入（桌面 hover/滚轮 vs 移动点击/双指缩放）与标签 LOD。
- 布局计算放后台 isolate，坐标缓存，避免 UI 卡顿。
- **社区着色与中心性尺寸（G4 增强，参照 ai-knowledge-graph）**：力导向图可叠加 Louvain 社区检测（按社区着色，凸显「敌对两派」式群落）与中心性定节点大小（degree / betweenness）；两者均为展示层，不改图谱数据，不影响证据锚定基线。

---

## 8. 持久化与备份

### 8.1 本地存储

| 数据 | 存储 | 进 WebDAV 备份？ |
|------|------|------------------|
| 图谱包 | `ai_graph/$hash.json`（按 contentHash） | **是**（用户主动 WebDAV 快照）；不含 Key |
| 手动别名 override | 图谱包内 `overrides` 段（v2） | 同上 |

- 主键是 **contentHash**（与对话一致）：删书库条目不删图谱文件；同一文件再导入（hash 不变）图谱自动续上；文件内容变了（hash 变）→ 新书、新图谱。
- 「删除图谱」只删该 hash 的图谱文件，不动对话与大纲。
- `formatVersion` 升级后旧缓存不展示，走「重新生成」。

### 8.2 WebDAV 快照

- `BackupRecords` 增加 `aiGraphs`（`optionalList`，向后兼容旧快照）；导出时读 `ai_graph/*.json` 校验 `contentHash` 为 sha256。
- 恢复合并：按 contentHash 归属；实体按 `name+type` upsert、`evidence` 追加、`coveredSections` 取并集；**本地已有图谱优先**（同 aiChats 的大纲策略：本地优先、不覆盖）；Key / 搜索 Key / WebDAV 凭据均不备份。
- 恢复预览与结果文案带图谱条数（沿用 `restoredAiChats` 模式新增 `restoredAiGraphs`）。

---

## 9. 分层与边界

```text
lib/ai/ai_graph.dart          — 模型（entity/relation/evidence/graph 包）+ AiGraphStore
lib/ai/ai_graph_scope.dart    — 用户范围计划：完整内容单元 + 默认勾选建议，不删除辅文
lib/ai/ai_graph_service.dart  — 管线：消费确认范围 → 抽取 → 校验回填 → 顺序增量合并（内联，未独立 merge 文件）→ 落盘 → 进度/取消
lib/library/backup/           — aiGraphs 导出 / 恢复合并（扩展现有 aiChats 逻辑）
lib/presentation/controllers/book_reader_controller.dart — 既有 AI 应用门面：图谱缓存、范围、生成/取消/checkpoint 与文件操作；不向 Workspace 暴露可写字段
lib/presentation/widgets/reader/book_ai_graph_workspace.dart — 图谱 Tab 组合边界（作品选择、实体索引、视图/排序、确认、详情、证据与全屏路由）
lib/presentation/widgets/reader/book_ai_chat_sheet.dart — 只组合对话 / 图谱工作区，不持有图谱状态机
lib/presentation/widgets/reader/book_ai_graph_view.dart / book_ai_graph_fullscreen.dart — 关系图视图
```

- 表现层只经 controller；Widget **不得**持有 `http.Client`、不得读写安全存储、不得拼装抽取 prompt。
- 抽取 / 复核 / 润色全部复用 `AiWorkflowModelSession` + `AiStructuredOutputAdapter`（`AiSettings` + 安全存储 + 总开关；关时 `openModelAdapter()` 返回 null，业务层不得绕过）。
- 防提示词注入：沿用 ai.md §7.4——正文与网页摘要作为 `<untrusted_context>` 引用材料；每类模型输出由独立 Schemantic schema 校验，随后仍必须通过证据定位、稳定 ID、端点与范围等业务校验；不再解析 fenced JSON 或正则恢复包装回答。

---

## 10. 落地切片与验收

### G1 — 数据模型 + 抽取管线 ✅

- 模型、Schemantic 结构化契约、单章抽取 + quote 回填 + 业务校验与截断分片。
- 验收：5 章人工标注样本的格式合法率与语义准确率达标（指标见 §5.7）；引文定位成功率高；失败可重试，不重复计费。

### G2 — 增量合并 + 缓存 + 备份 ✅

- 顺序增量共指、coveredSections、断点续跑；`ai_graph/$hash.json`；`BackupRecords.aiGraphs` 导出/恢复。
- 验收：只补新章不重抽旧章；stop 后已完成章节保留；杀进程后重启续跑不重复抽取；恢复合并不覆盖本地；Key 不进快照。

### G3 — 图谱 Tab UI ✅

- 固定实体索引（人物/地点/事件/组织/事物，按上述分类策略搜索与排序）→ 实体卡（描述/别名/关系/关系出处/实体出处）→ 点出处跳原文并关面板；范围 badge 取自保存图谱，跨设备保持一致。
- 验收：allowUnreadContext 关时未读章节不进入生成；开到关切换不清空也不隐藏已有数据；跨设备打开同一缓存时实体与关系数量一致；打开面板不重复请求。

### G4（可延后）— 关系图视图 ✅

- 力导向图 + hover 高亮 + 局部图；flutter_graph_view 集成。
- 验收：>500 节点不卡 UI；点击节点进实体卡；桌面/移动输入差异正常。

---

## 11. 文档回写清单（已回写）

- [x] `PRODUCT.md` §6 能力表「知识图谱」状态 → 已有（MVP）；§6.4 M5 标记
- [x] `ai.md` §4.4 占位句 → 指向本页；§9 M5 段落更新
- [x] `ENGINEERING.md` AI 边界补 `lib/ai/ai_graph*` 与备份条目（§3 AI 边界已含）
- [x] `docs/README.md` specs 表新增本页并标 M5 已有
- [x] `webdav-backup.md` AI 内容范围（对话 + 大纲 + 图谱）
- [x] 本页状态栏 → 已实现

---

## 12. 开放问题（实现后状态）

- 手动别名 override（合并/拆分）：v1 已做「删除实体」；别名合并 / 拆分留 v2（§5.5 覆盖层）。
- 关系图渲染库：已采用 `flutter_graph_view`（G4 落地），图质量优先于零依赖偏好；列表视图仍可完全避开。
- `allowUnreadContext` 文案：已按实际行为修正（对话 / 大纲不裁剪；图谱在生成输入阶段裁剪，已保存结果不二次裁剪）。
- **展示方案驱动 + 家族树 + 地点叙事顺序**：已实现，见 [ai-graph-narration.md](./ai-graph-narration.md)（第 0 步只推荐首次视图、固定索引/探索导航、方向性关系约定、连线架构图家族树、organization 独立索引、地点首次出现顺序；组织树后置）。
