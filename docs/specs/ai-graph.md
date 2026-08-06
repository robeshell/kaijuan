# 本书知识图谱（AI M5）

| | |
|--|--|
| **状态** | 已实现（M5；G1–G4 落地） |
| **日期** | 2026-08-06 |
| **PRODUCT** | [§6](../PRODUCT.md) · [§10.2](../PRODUCT.md) |
| **相关** | [ai.md](./ai.md)、[webdav-backup.md](./webdav-backup.md)、[reader-chrome.md](./reader-chrome.md)、[book-reader.md](./book-reader.md) |
| **引擎** | 图书 reflow only（v1）；漫画页图 AI 另案 |

> 产品状态只改 [PRODUCT.md](../PRODUCT.md) §6。本页写交互、边界、任务切分与验收。  
> M5 在 [ai.md](./ai.md) §9 的约定：「章级实体关系 + 出处；列表优先，图可视化可简」。

---

## 1. 结论（先读）

**知识图谱 = 一本书的实体（人物 / 地点 / 事件）+ 关系 + 出处的本地缓存视图**，是「本书 AI」工作区的第三个 Tab（对话 / 大纲 / 知识图谱）。

| 决策 | 取值 | 理由 |
|------|------|------|
| 范围 | **跟随 `allowUnreadContext`**：关 = 只处理已读章节及之前的正文；开 = 全书 | 该设置注释与 UI 已预留「防剧透」语义；与大纲「始终全书」相反，形成差异化 |
| 生成 | **章级增量**：按章节对比已处理集合，只抽新章；断点续跑 | 数十万字一次吞全书成本高、易超时；随读随抽体验好 |
| 协议 | **fenced JSON**（复用对话的 robust 解析），不引 LangChain / 原生 tool-call | 与 ai.md 既定取舍一致；跨 OpenAI / Anthropic / DeepSeek 可移植 |
| 存储 | 按 **contentHash** 的本地文件 `ai_graph/$hash.json`；随用户主动 WebDAV 快照备份；**Key 永不备份** | 与 `ai_chat/` 同构，备份合并逻辑可扩展复用 |
| 数据库 | **不用图数据库**（Neo4j 等） | 单书数百～数千实体、数千关系，JSON + 内存过滤绰绰有余；图库只在多书/图算法时才值得引入 |
| 可视化 | **列表优先，力导向图可简**（v1 允许只上列表） | ai.md §9 M5 已定；图渲染库决策见 §7 |

### 当前实现状态

- **G1–G4 已全部落地**：数据模型与抽取管线（`lib/ai/ai_graph.dart` + `ai_graph_service.dart`，含章级增量 / 合并 / 断点续跑）、图谱 Tab（`book_ai_chat_sheet.dart` 实体列表 / 合集著作列表）、关系图（`book_ai_graph_view.dart` + `flutter_graph_view`）、全屏视图（`book_ai_graph_fullscreen.dart`）、WebDAV `aiGraphs` 备份（`backup_service.dart`）。
- 实现时的命名与 §9 规划略有出入（见 §12）；本页交互与验收描述仍然有效。

---

## 2. 目标与非目标

### 做

- **实体抽取**：人物、地点、事件三类（v1）；`organization / item / concept` 类型字段预留，v1 不生成。
- **关系抽取**：类型化关系（小写 `snake_case` 词表，如 `father_of`、`married_to`、`work_at`、`lives_in`、`participates_in`），双向语义（抽到 `A-B` 时 UI 可双向展示）。
- **出处（证据）**：每条实体与关系至少一条原文证据；点击证据跳回书内位置（`BookLocator`：section + progressInSection）。
- **章级增量**：只对新章节抽取并合并进已有图谱；进度、停止、断点续跑、重生成（= 删除重建）。
- **排除附录类单元**：参考书目 / 附录 / 索引 / 致谢 / 后记 / 年表等不进图谱（复用大纲元数据过滤后再加图谱专属过滤）。这些单元人物关系价值低、输出密度最高（易截断），还带进一次性人名；正文章节不受影响。**前言 / 序 / 自序 / 代序 / 凡例 / 出版说明 / 编者按 / 导读 / 题记**同样过滤（作者前言与故事无关）。
- **合集选书**：合集 / 分卷书生成图谱前先让用户**单选一部著作**，只生成该书范围（一整个合集的人物关系混杂多本书，图谱会崩坏）。检测与候选**优先基于大纲**（`planStructure` 已把「同一部作品或一卷的连续节合并」为一个 unit，故「覆盖 ≥2 节的大纲单元 ≥2 个」即判定合集，候选 = 这些单元，end 由下一单元 start 推导、最后一本开放至书末）；**无大纲时自动补跑一次轻量结构识别**（复用 `planStructure`，单次短调用，相对几十次抽取可忽略），识别到合集同样弹选择器，识别失败退回全量生成。普通书（章节多为单节单元）不弹选择器、行为不变。
- **多作品图谱存储与交互**：每部著作一个独立图谱文件（`ai_graph/$hash.$workKey.json`，workKey = `s` + 起始节；整本书图谱仍是 `$hash.json`），**互不覆盖**，可逐本生成/查看/删除。图谱 Tab 对合集书显示**著作列表**（不弹窗）：每行 = 著作名 + 状态徽章（已生成 / 未生成 / 生成中进度）；点击已生成的进入该著作图谱视图（顶部「‹ 全部著作」返回），未生成的点击即生成。WebDAV 备份/恢复按 workKey 保留（行字段 `workKey`）。
- **防剧透**：`allowUnreadContext` 关时，未读章节的实体、关系与证据**既不生成也不展示**（图谱按当前阅读位置过滤，读得越深图越全）。
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

### 3.1 实体（`AiGraphEntity`）

```dart
class AiGraphEntity {
  final String name;            // canonical 名（大小写/繁简已规范，只增不删）
  final AiGraphEntityType type; // person | location | event（v1）
  final List<String> aliases;   // 别名，并入 canonical 索引
  final String description;     // 依据驱动的 3–5 句
  final List<AiGraphEvidence> evidence; // 至少 1 条
  final Map<int, int> chapterFreq;      // sectionIndex -> 出现次数（合并时累加）
  final int firstSection;               // 首次出现章节（演化/防剧透用）
  final int lastSection;                // 最后出现章节
}
```

- **唯一键 = `name + type`**；同名不同类（人物「王五」vs 地点「王五」）是不同节点。
- 同名歧义（两个不同的人同名）：**绝不合并**，靠类型 + 描述 + 关系上下文区分；抽取器无法消歧时映射到待审名单，不强并。
- 实体 `id` 由 `name + type` 派生（如 `sha1(name)|person`），不存自增号。

### 3.2 关系（`AiGraphRelation`）

```dart
class AiGraphRelation {
  final String source;        // canonical name
  final String target;        // canonical name
  final String type;          // snake_case 词表，如 married_to
  final String description;   // 一句话，依据驱动
  final List<AiGraphEvidence> evidence;
  final double weight;        // 证据条数 / 章节覆盖数，合并时平均
}
```

- **唯一键 = `source + target + type`**（无向关系生成时统一 `source < target` 字典序排序，避免 A-B 与 B-A 分裂）。
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

复用 `AiBookOutlineService` 的章节切分（`planStructure`：导航单元 / 逻辑单元）与 `AiChatService` 的 fenced JSON robust 解析，**不引 LangChain**。

### 4.1 流程

```text
输入：sections（导航单元切分结果）+ allowUnreadContext（决定范围）
  → 范围裁剪：关 = 只保留已读 section；开 = 全部（随后排除附录类单元，见 §2）
  → 已处理集合 = coveredSections ∩ 范围内；只对新 section 走抽取
  → 每 section 切成 800–2000 token 的 chunk（相邻 5–10% 重叠）
  → 每 chunk 一次 fenced JSON 抽取调用（温度 0；带 chunk_id + sectionIndex）
  → robust 解析 → 校验（schema + 枚举 + 引文存在性）→ 失败分类重试（≤2 次）
  → 程序回填 quote → progressInSection
  → 顺序增量合并（见 4.2）→ 落盘 ai_graph/$hash.json
  → onProgress（completed/total = 章节数）
```

- **chunk 预算**：输出 `max_tokens` 设输入的 1/3–1/2；单章过长时先抽首尾再补中间，不能由书前部耗尽上限。
- **并行与限流**：chunk 间可并行，但按 TPM / 连接数做信号量；停止 = `CancelToken`（复用现有 `ai_outline.dart` 的取消协议），已完成的章节结果**保留**。
- **范围与增量**：`allowUnreadContext` 从关切到开 → 只补抽新增未读章节（coveredSections 并集）；从开切到关 → 图谱内容不变（避免删数据），但 UI 展示过滤为已读范围（见 §6 防剧透）。

### 4.2 合并（顺序增量共指消解）

每批抽取结果**先落盘再合并**（中间产物可审计、可重放、天然断点）：

1. **对齐**：用维护中的 `alias → canonical` 缓存（**按 person / location / event 分桶**）把本批实体名映射到已有节点；无歧义别名并入已有 canonical，未匹配才建新节点。
2. **证据追加**：实体/关系命中已有唯一键 → `evidence` 追加、`chapterFreq` 累加、`first/lastSection` 更新、描述**不覆盖**（记入待合成列表）。
3. **描述合成**：同一实体证据超过阈值后，由一次 LLM 调用按证据合成单一描述（GraphRAG 式 `SUMMARIZE`），冲突时以证据为准；失败则保留旧描述并标 `needs_review`。
4. **关系合并**：同 `(source, target, type)` → `weight` 平均、证据追加。
5. **canonical 名只增不删**；重抽不重命名（保证旧数据可追溯）。
6. 全部完成后可选执行一次 **幻觉过滤**：实体/关系若无任何证据（`evidence` 为空或全部 `spanResolved=false`）标记，UI 不默认展示。

### 4.3 抽取 schema（fenced JSON 契约）

```jsonc
{
  "entities": [
    {
      "name": "伊丽莎白·班纳特",
      "type": "person",                    // person|location|event
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
- **质量门槛**：落地前用 5 个代表性章节做 golden set，跑通 `schema 校验率 × 语义准确率` 再定稿 prompt（研究建议）。

### 4.4 成本

- 几十万字 ≈ 200–400 次调用（便宜模型 1–3 美元量级）；章级增量让「读多少抽多少」成本随阅读进度摊开。
- 默认不开 gleaning；合并/消歧用贵模型一次过，抽取用便宜模型。

---

## 5. 质量保障（正确性）

> **正确性是流程属性，不是产物属性**：不追求模型「一次抽对」，而是用证据可审计、程序校验、评测门槛、增量纠错四层把关，让每条关系都可回查、可纠错。

### 5.1 证据锚定（抗幻觉地基）

- 每条实体与关系**必须携带原文证据**（`sectionIndex + quote`）；`progressInSection` 由程序回填（§3.3）。
- `spanResolved = false`（证据定位失败）→ 条目**不默认展示**，标「引用待确认」；无证据条目直接丢弃。
- **幻觉过滤**：实体必须实际出现在原文中才保留（防模型把预训练知识如「《三国》有诸葛亮」漏进无关书）；抽取 prompt 硬性约束「仅基于给定原文，禁用书外知识」，正文全部作为 `<untrusted_context>` 引用材料（ai.md §7.4）。

### 5.2 程序校验（模型输出是候选，程序是裁判）

1. **schema 校验**：类型枚举（person/location/event）、关系类型词表、字段必填、`evidence` 非空。
2. **引文存在性**：quote 在原文归一化搜索；搜不到 → 重试（≤2 次）或降级为章节级证据，绝不静默收下。
3. **唯一键幂等**：`name+type`、`source+target+type` upsert，重复批次不产生脏数据。
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

### 5.7 golden set 验收指标（上线门槛）

落地前用 **5 个代表性章节人工标注** golden set，跑通以下指标再定稿 prompt / 模型组合：

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
  → 生成中：章节批次进度 +「停止」（保留已完成章节）
  → 已生成：顶部范围 badge + 视图切换（实体列表 | 关系图）
       → 实体列表：按类型分组、可过滤（人物/地点/事件）、可搜索、按章节频次排序（可选加「关系数 / degree 中心性」排序档，纯本地计算、零 LLM 成本；degree 越高越接近关系枢纽）
       → 关系图（可简）：力导向；节点=实体（类型着色）；边=关系（类型着色）
       → hover 高亮邻居（桌面；移动端点击聚焦）
       → 点击实体 → 实体卡：描述 / 别名 / 关系列表 / 证据列表（点证据跳原文并关面板）
       → 实体卡底部：前往原文（按 firstSection）；更多：删除该实体（合并错误时手动修正）
       → 顶部操作：重新生成（= 删除重建）；删除图谱
```

- **范围 badge**：`allowUnreadContext` 关 → 「仅已读章节」（读到 N 章，图谱止于 N）；开 → 「全书」。
- **防剧透展示过滤**：范围开→关切换不清数据，只过滤展示（未读章节证据隐藏、节点若全部证据未读则灰显或隐藏）。
- **手动修正 override 层**：实体别名可手动合并 / 拆分（如「孙悟空 = 美猴王」），覆盖层与抽取数据分离、可撤销、重生成不污染（v1 最小实现：合并 = 追加别名到目标实体并删除被并实体；拆分 = 恢复抽取原始名）。不强求：v1 允许只做「删除实体」，别名手动合并留待 v2。
- **停止 / 重试**：失败章节提供「重试本章」；停止后保留已生成章节（与大纲一致）。
- 图谱 Tab 复用对话/大纲的**生成物语义**：结果不因关闭面板取消；读者主动停止或退出阅读器才取消；重新打开直接展示缓存。

### 状态与文案

| 场景 | 文案草案 |
|------|----------|
| 未生成 + allowUnreadContext 关 | 「图谱覆盖已读章节（第 1–N 章）。开启『允许未读上下文』可分析全书。」+「生成图谱」 |
| 未生成 + allowUnreadContext 开 | 「将分析全书生成人物、地点与事件图谱。」+「生成图谱」 |
| 生成中 | 章节进度 +「停止」（停止后保留已完成章节） |
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
lib/ai/ai_graph_service.dart  — 管线：范围裁剪 → 抽取 → 校验回填 → 顺序增量合并（内联，未独立 merge 文件）→ 落盘 → 进度/取消
lib/library/backup/           — aiGraphs 导出 / 恢复合并（扩展现有 aiChats 逻辑）
lib/presentation/controllers/ — 图谱控制器（或并入 BookReaderController 的 AI 工作区状态）
lib/presentation/widgets/reader/book_ai_chat_sheet.dart — 图谱 Tab（实体列表 / 合集著作列表）
lib/presentation/widgets/reader/book_ai_graph_view.dart / book_ai_graph_fullscreen.dart — 关系图视图
```

- 表现层只经 controller；Widget **不得**持有 `http.Client`、不得读写安全存储、不得拼装抽取 prompt。
- 抽取 / 合并复用 `AiProvider`（`AiSettings` + 安全存储 + 总开关；关时 `openProvider()` 返回 null，业务层不得绕过）。
- 防提示词注入：沿用 ai.md §7.4——正文与网页摘要作为 `<untrusted_context>` 引用材料；只接受整条回复为 fenced JSON block 的抽取结果，普通回答不触发合并。

---

## 10. 落地切片与验收

### G1 — 数据模型 + 抽取管线 ✅

- 模型、fenced JSON 契约、单章抽取 + quote 回填 + 校验重试。
- 验收：5 章 golden set，`schema 校验率` 与 `语义准确率` 达标（指标见 §5.7）；quote 定位成功率高；失败可重试不重复计费。

### G2 — 增量合并 + 缓存 + 备份 ✅

- 顺序增量共指、coveredSections、断点续跑；`ai_graph/$hash.json`；`BackupRecords.aiGraphs` 导出/恢复。
- 验收：只补新章不重抽旧章；stop 后已完成章节保留；杀进程后重启续跑不重复抽取；恢复合并不覆盖本地；Key 不进快照。

### G3 — 图谱 Tab UI ✅

- 实体列表（类型过滤/搜索/频次排序）→ 实体卡（描述/别名/关系/证据）→ 点证据跳原文并关面板；范围 badge + 防剧透过滤。
- 验收：allowUnreadContext 关时未读章节实体/证据不出现；开到关切换不清数据；打开面板直接展示缓存不重复请求。

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
- `allowUnreadContext` 文案：已按实际行为修正（对话 / 大纲不裁剪、图谱才裁剪）。
- **展示方案驱动 + 家族树 + 地图文字版**：已实现，见 [ai-graph-narration.md](./ai-graph-narration.md)（第 0 步方案输出、方向性关系约定、连线架构图家族树、organization 实体反哺、地点链；组织树后置）。
