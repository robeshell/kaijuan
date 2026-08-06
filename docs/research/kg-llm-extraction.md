# LLM 三元组抽取：研究与工程实践（本书知识图谱）

> 定位：**研究 / 学习资料**，服务于 [specs/ai-graph.md](../specs/ai-graph.md)（M5 规格）。
> `ai-graph.md` 写「做什么」（交互、数据模型、验收）；本页写「为什么这么做」——外部被验证的实践、权威出处、与规格的对照，以及一份快速学习路径。
> 结论先行；细节按需展开。

## 1. 结论（先读）

**单书本地小图谱（数百～数千实体），LLM 抽取 + 程序校验是正确的工程取舍**；参考实现与论文已把关键难点（schema 漂移、recall 不足、共指分裂、幻觉）的解法验证清楚，`ai-graph.md` 的决策与主流实践一致，且有两处**有意偏离**（不做关系推断、不接 Wikidata 对齐）值得知道理由。

| 实践（外部验证） | 出处 | ai-graph.md 对应 | 状态 |
|---|---|---|---|
| schema-guided extraction（实体类型 + 关系词表约束） | GraphRAG、OneKE | §4.3 fenced JSON 契约 | 已采纳 |
| 温度 0、仅基于给定文本（禁用书外知识） | GraphRAG、ai-knowledge-graph | §4.1 / §5.1 | 已采纳 |
| 证据锚定（每条记录必带原文引用，程序校验定位） | wiki-graph、GraphRAG | §3.3 Evidence | 已采纳（更严格：`spanResolved`） |
| GraphRAG 式描述合成（`SUMMARIZE`） | GraphRAG 论文 | §4.2 步骤 3 | 已采纳 |
| 顺序增量 alias → canonical 缓存（按类型分桶） | ai-knowledge-graph Phase 2 的轻量版 | §4.2 / §5.3 | 已采纳 |
| 全量标准化复核 pass（LLM 批量对齐实体名） | ai-knowledge-graph | §5.3 v2 候选 | v2 候选 |
| gleaning（多轮补漏，recall 70%→95%） | LightRAG（2024-10） | §4.4「默认不开」 | 有意延迟 |
| 关系推断（transitive / 词法 / 社区间） | ai-knowledge-graph Phase 3 | §2 不做清单 | **有意偏离** |
| Wikidata QID 公开实体对齐 | wiki-graph WikiSpine | §2 不做清单 | **有意偏离** |
| golden set 验收（precision/recall/schema 合法率） | 通用 IE 评测实践 | §5.7 | 已采纳 |

---

## 2. 为什么用 LLM 抽三元组

- **传统管线**：NER（实体识别）→ 关系分类 → 共指消解，每一步要领域标注数据、串联误差放大、换领域重训。对「一本书一个领域」的阅读 App 不可行。
- **LLM 抽取**：零标注；schema 直接用 prompt 表达（见 §3）；few-shot 即可约束输出格式；开放域效果足够支撑「角色关系速查」这类体验。
- **已知局限**：幻觉（抽了原文没有的内容）、漏抽（单轮 recall 只有 65–80%，见 §6）、成本（几十万字 ≈ 200–400 次调用）、输出格式不稳定（需程序校验兜底）。
- **结论**：LLM 负责「候选」，程序负责「裁判」（schema 校验 + 引文定位 + 幂等合并），见 `ai-graph.md` §5——这正是 GraphRAG / wiki-graph / OneKE 共同采用的架构。

---

## 3. 抽取模式：schema-guided extraction

**核心思想：先定 schema（抽什么），再让 LLM 抽。** 相比 open extraction（让模型自由定实体边界），schema 约束显著提升格式稳定性与合并效率；schema 一旦漂移，漏抽和幻觉同时上升（wiki-graph 明确把「schema 是私人 rulebook、漂移即丢信息」列为设计要点）。

### 3.1 schema 三要素

1. **实体类型枚举**（person / location / event …）——LLM 只产出这些类型的实体。
2. **关系类型**（词表 or 开放）——`ai-graph.md` 的做法：内置常见词表 + 不限制新类型（小写 snake_case 原样保留），兼顾稳定与开放。
3. **每条记录的必填字段**——含证据字段（quote），防空证据污染。

### 3.2 权威实例

- **GraphRAG（微软）** 的实体/关系抽取 prompt 是最广泛被复用的模板，官方文档给出可替换 token：
  - `{input_text}` 输入文本 · `{entity_types}` 实体类型 · `{tuple_delimiter}` / `{record_delimiter}` / `{completion_delimiter}` 三种分隔符（分隔元组、记录、标记生成完成）
  - prompt 分两段：先列出全部实体，再基于已列实体识别关系；要求只从给定文本抽取、不依赖外部知识。
  - 官方 Manual Prompt Tuning 文档：[microsoft.github.io/graphrag/prompt_tuning/manual_prompt_tuning](https://microsoft.github.io/graphrag/prompt_tuning/manual_prompt_tuning/)（默认 prompt 全文在 graphrag 仓库 `prompts` 相关源码/issue #869）。
- **OneKE（WWW 2025 Demo，[arXiv:2412.20005](https://arxiv.org/abs/2412.20005)）**：dockerized schema-guided 系统，schema 配置化 + **错误用例调试与纠正**（把抽错的例子喂回配置库，针对性修正 prompt）；明确支持「raw PDF Books」抽取，跨域（科学 / 新闻）。「错误用例纠正」机制值得借鉴到我们的重试逻辑（`ai-graph.md` §4.1 失败分类重试）。
- 我们项目的契约见 `ai-graph.md` §4.3：fenced JSON、全字段必填、`evidence` 至少 1 条——与 GraphRAG 的 tuple 式输出等价，但 JSON 结构对 Flutter 端解析更直接。

---

## 4. prompt 设计要点（被反复验证的清单）

1. **温度 0**（GraphRAG、ai-knowledge-graph 均 ≤0.2）：抽取任务要确定性，不需要创造。
2. **禁用书外知识**：正文作为 `<untrusted_context>` 引用材料；硬性约束「仅基于给定原文」——防「《三国》有诸葛亮」式预训练知识漏进无关书（`ai-graph.md` §5.1）。
3. **few-shot**：2–3 个领域内示例（人物关系/事件描述各一），比长篇指令有效。
4. **输出预算**：`max_tokens` 设输入的 1/3–1/2（`ai-graph.md` §4.1）；LightRAG 给单响应实体/关系行数设上限（默认 100 总行 / 40 实体行，配 `completion_delimiter` 早停），防止单 chunk 输出失控截断。
5. **失败分类重试（≤2 次）**：schema 格式错 → 复述契约重试；引文定位失败 → 重试或降级章节级证据（`ai-graph.md` §5.2）。
6. **输出早停标记**：GraphRAG 的 `completion_delimiter`——让模型输出完标记后停止，配合 max_tokens 避免半截 JSON。
7. **per-chunk 先抽首尾再补中间**：单章过长时避免前部耗尽输出上限（`ai-graph.md` §4.1）。

---

## 5. 分块与上下文窗口

- **经验值**：ai-knowledge-graph 用 100–200 词 / 20 词重叠（短块利于关系局部性）；`ai-graph.md` 用 800–2000 token / 5–10% 重叠（更长块省调用数，代价是注意力分散——正是 gleaning 要补的洞）。
- **语义切分优于固定窗口**：按章/节切分（`_planStructure` 导航单元）本身就是语义切分——同一剧情上下文天然聚在一个 chunk，跨 chunk 的实体碎片最少。
- **章级增量是项目相对通用工具的特殊优势**：`coveredSections` 让「读多少抽多少」，把成本摊到阅读进度上（`ai-graph.md` §1/§4.1），通用工具（一次灌全书）做不到。

---

## 6. 多轮补漏：gleaning

- **现象**：单轮 LLM 抽取典型只拿到文档实体的 **65–80%**（注意力限制、代词/间接提及漏网）。
- **做法**：把首轮已抽实体名喂回，「MANY entities were missed. Already found: … Find ADDITIONAL entities」；迭代直到收敛或达到 `max_gleaning`。
- **效果与成本**（LightRAG 论文 2024-10，edgequake 复现）：

  | 轮次 | recall | 边际 | 成本倍数 |
  |---|---|---|---|
  | 0（单轮） | ~70% | — | 1x |
  | 1 | ~88% | +18% | 2x |
  | 2 | ~95% | +7% | 3x |
  | 3+ | ~97% | <2% | 4x |

  推荐 1–2 轮；3 轮后边际收益 <2% 不值得。
- **项目决策**：`ai-graph.md` §4.4「默认不开 gleaning」——章级增量 + 每章多 chunk 已缓解漏抽，且成本是硬约束；**建议作为开放问题保留**：对关键章节（如主线高潮章）可开 1 轮 gleaning。
- 实现参考：LightRAG（[HKUDS/LightRAG](https://github.com/HKUDS/LightRAG)，`entity_extract_max_gleaning`）、HiRAG（[entity extraction & gleaning](https://deepwiki.com/hhy-huang/HiRAG/3.2-entity-extraction-and-gleaning)）。

---

## 7. 实体对齐与共指消解（防分裂 / 防误并）

三种被验证的路线，可组合：

| 路线 | 做法 | 代表 | 项目取舍 |
|---|---|---|---|
| A. 顺序增量缓存 | 维护 `alias → canonical` 映射，按实体类型分桶；新名字先查缓存，未命中才建新节点 | `ai-graph.md` §4.2/§5.3 | **已采纳**（v1） |
| B. 全量标准化 pass | 全部抽取完成后，一次 LLM 调用批量复核「哪些名字指向同一实体」，产出待审建议 | ai-knowledge-graph Phase 2（201 个实体 → 181 个标准形，LLM 对齐 15 组） | **v2 候选**（`ai-graph.md` §5.3 复核 pass） |
| C. 公开实体对齐 | 用 Wikipedia/Wikidata 当「公共字典」，先召回候选 QID 再让 LLM 消歧 | wiki-graph（WikiSpine） | **有意偏离** |

- **为什么 C 有意偏离**：WikiSpine 路线对「人物、机构、地点」这类事实性实体极好（跨书、跨章稳定累积到同一 QID），但**小说角色、私设地名是它明确覆盖不到的**（wiki-graph 自己承认这一取舍）。我们是小说/书籍阅读器，私有实体是主体 → 走 A + B，不接 Wikidata。
- **同名歧义绝不合并**：两个同名不同人（两个「王五」）→ 待审名单，绝不强并——误并是关系图最脏的错误（`ai-graph.md` §5.2）。这是所有实现里最容易翻车、也最值得写死规则的点。
- canonical 名**只增不删** + 手动 override 层（v2 合并/拆分，v1 至少删除实体）：保证重生成可追溯（`ai-graph.md` §5.5）。

---

## 8. 关系：方向、去重与「推断」的取舍

- **去重**：无向关系统一 `source < target` 字典序，唯一键 `source+target+type`；证据追加、`weight` 平均（`ai-graph.md` §3.2）。
- **方向错误**程序无法判定 → 靠 golden set 门槛（≤5%）与人工抽测（`ai-graph.md` §5.7）。
- **关系推断**（ai-knowledge-graph Phase 3：transitive 推理 + 社区间 LLM 推断 + 词法相似）：demo 里 564 条三元组中有 **355 条（63%）是推断出来的**，虚线上色显示。
  - **项目有意偏离**：推断关系没有原文证据，是幻觉放大器；对「阅读伴侣」场景，宁可稀疏也要每条可回查。社区检测 / 中心性只用于**展示层**着色与节点大小（`ai-graph.md` §7 G4），不改图谱数据。
  - 一句话取舍：**推断关系适合「知识发现」工具，证据锚定适合「可信阅读图谱」**——我们的产品定位是后者。

---

## 9. 证据与溯源（可信图谱的地基）

- wiki-graph 的核心结构 **Entity / Triple / Evidence**：`subject --predicate--> object`，每条证据可回源到章节与原文句子（URI 形式，如 `wikg://entity/Q8018 evidence`、`chapter/part/source#4..8`）。
- 我们的同构设计（`ai-graph.md` §3.3 `AiGraphEvidence`）：`sectionIndex + quote + progressInSection`，其中 `progressInSection` 由**程序**在原文归一化搜索后回填（去空白、统一全半角/大小写），LLM 只输出 `sectionIndex + quote`——定位失败降级章节级证据（`spanResolved=false`）、**不丢弃**。
- 为什么程序回填而不是让 LLM 给位置：LLM 给的位置不可信、不可精确到段落；程序搜索是确定性的，失败可重试（≤2 次）再降级（`ai-graph.md` §5.2）。
- 展示层：点击证据跳回书内位置（`BookLocator`）是「一秒验证对错」的体验闭环，是比任何离线指标都强的正确性保障。

---

## 10. 幻觉控制（要点汇总）

1. **证据锚定**：实体/关系必须携带原文证据；无证据条目丢弃（`ai-graph.md` §5.1）。
2. **书外知识禁用**：`<untrusted_context>` + 硬约束（`ai.md` §7.4）。
3. **幻觉过滤 pass**：实体/关系若全部证据 `spanResolved=false` → 标记、UI 不默认展示。
4. **冲突追加不覆盖**：关系跨章变化（爱→恨、未婚→已婚）可能是真实剧情，追加证据、由合并 LLM 依据证据合成描述（`ai-graph.md` §5.4）——这是「剧情演变」与「模型翻脸」的正确区分方式。

---

## 11. 评估：golden set 与指标

- **为什么必须 golden set**：prompt 定稿前不测，等于拿真实用户当实验。`ai-graph.md` §5.7 用 **5 个代表性章节人工标注**，跑通六项指标再上线：

  | 指标 | 门槛 |
  |---|---|
  | schema 合法率 | ≥ 95% |
  | quote 定位率 | ≥ 90% |
  | precision（关系真实存在） | ≥ 90% |
  | recall（重要关系被抽到） | ≥ 70% |
  | 方向错误率 | ≤ 5% |
  | 误并 / 分裂率 | ≤ 2% |

- 上线后持续：每批新章抽样 1% 语义复核（人工或 LLM judge）；章级增量让问题只影响新章、改 prompt 重抽即可（`ai-graph.md` §5.6）。
- GraphRAG 论文（[arXiv:2404.16130](https://arxiv.org/abs/2404.16130)）的启示：图谱构建的收益分 **local**（单实体/关系问答，RAG 也能做）与 **global**（跨全书主题/群体问题，需社区摘要 + map-reduce）。我们的 v1 图谱服务于「角色关系速查」（local 为主），不需要 GraphRAG 的社区摘要层——那是「整本译/知识图谱进阶」的事。

---

## 12. 学习路径（快速 + 权威）

按投入时间排序，全部免费/公开：

| 投入 | 学什么 | 链接 |
|---|---|---|
| 30 分钟 | 本页 + GraphRAG 抽取 prompt 的 token 结构 | [Manual Prompt Tuning](https://microsoft.github.io/graphrag/prompt_tuning/manual_prompt_tuning/) |
| 半天（动手） | **Neo4j GraphAcademy「Building Knowledge Graphs with LLMs」**：LLM Graph Builder + Python 从非结构化文本建图谱、设 schema、解释结果 | [graphacademy.neo4j.com](https://graphacademy.neo4j.com/)（进阶，需 Cypher 基础；[课程公告](https://neo4j.com/blog/developer/new-building-knowledge-graphs-llms/)） |
| 1 天（概念） | **斯坦福 CS520: Knowledge Graphs**：重点前 5 讲（What is a KG / 数据模型 / schema 设计 / 从数据建 KG / 从非结构化输入建 KG），每讲有 Notes+Slides+Video | [web.stanford.edu/class/cs520](https://web.stanford.edu/class/cs520/)（[「What is a Knowledge Graph?」Notes](https://web.stanford.edu/class/cs520/2020/notes/What_is_a_Knowledge_Graph.html)） |
| 数天（系统） | 中文教材二选一：《知识图谱：方法、实践与应用》（王昊奋等，电子工业出版社 2019）／《知识图谱——从理论到实践》（清华大学出版社）；概念补 W3C RDF 1.1 Primer（三元组标准入门，很短） | [RDF 1.1 Primer](https://www.w3.org/TR/rdf11-primer/) |
| 随时（代码对照） | 四个开源实现对照着读：wiki-graph（证据溯源 + Wikidata 对齐）、ai-knowledge-graph（四阶段管线 + 推断）、OneKE（schema-guided + 错误用例纠正）、LightRAG（gleaning + 输出上限） | 见 §14 |

**小说/网文专项参考**（与我们场景最像）：Neo4j NODES AI 2026「Graph-Powered Storyworlds」（用图谱保持 100 万字 LitRPG 的角色/道具/地点/任务连贯）；中文社区 `writeGOD`（作家辅助，知识图谱+向量检索，支持百万字）、`AI-Reader-V2`（小说角色关系图/地图/时间线，本地存储）。

---

## 13. 与 ai-graph.md 的对照（实现时复查）

| # | 外部实践 | ai-graph.md 决策 | 复查点 |
|---|---|---|---|
| 1 | GraphRAG `completion_delimiter` 早停 | §4.1 chunk 预算 | 是否要在 fenced JSON 契约里加「输出以 ``` 结尾」的硬约束 |
| 2 | OneKE 错误用例调试 | §4.1 失败分类重试 | 重试 prompt 是否携带「上次失败原因」复述 |
| 3 | LightRAG 单响应行数上限 | §4.1 max_tokens 预算 | 单 chunk 实体/关系行数是否也需要上限 |
| 4 | gleaning 边际收益 | §4.4 默认不开 | 关键章节手动开 1 轮 gleaning 是否进开放问题 |
| 5 | ai-knowledge-graph 全量标准化 | §5.3 v2 候选 | G1–G2 落地后评估是否需要 |
| 6 | wiki-graph URI 溯源 | §3.3 Evidence + §6 点证据跳原文 | 证据展示粒度是否到段落级（progressInSection） |
| 7 | 关系推断（63% 比例警示） | §2 不做 | 若未来加「推理视图」，必须与原证据边视觉区分（如 ai-knowledge-graph 虚线） |

---

## 14. 参考清单

**课程 / 文档**
- 斯坦福 CS520: Knowledge Graphs — https://web.stanford.edu/class/cs520/
- Neo4j GraphAcademy — https://graphacademy.neo4j.com/ · 课程公告 — https://neo4j.com/blog/developer/new-building-knowledge-graphs-llms/
- GraphRAG Manual Prompt Tuning — https://microsoft.github.io/graphrag/prompt_tuning/manual_prompt_tuning/
- W3C RDF 1.1 Primer — https://www.w3.org/TR/rdf11-primer/

**论文**
- GraphRAG: From Local to Global（微软，2024）— https://arxiv.org/abs/2404.16130
- OneKE: A Dockerized Schema-Guided LLM Agent-based Knowledge Extraction System（WWW 2025 Demo）— https://arxiv.org/abs/2412.20005
- LightRAG（gleaning 出处，2024-10）— https://github.com/HKUDS/LightRAG

**开源实现**
- oomol-lab/wiki-graph（Entity/Triple/Evidence + Wikidata 对齐 + 回源 URI）— https://github.com/oomol-lab/wiki-graph
- robert-mcdermott/ai-knowledge-graph（四阶段：抽取→标准化→推断→可视化；Louvain/中心性）— https://github.com/robert-mcdermott/ai-knowledge-graph
- HKUDS/LightRAG（gleaning 配置、输出上限 PR #2950）— https://github.com/HKUDS/LightRAG
- HiRAG entity extraction & gleaning — https://deepwiki.com/hhy-huang/HiRAG/3.2-entity-extraction-and-gleaning
- edgequake gleaning 深潜（recall/成本曲线复现）— https://github.com/raphaelmansuy/edgequake/blob/edgequake-main/docs/deep-dives/gleaning.md
- M-YiXi/writeGOD（中文，小说知识图谱+向量检索）— https://github.com/M-YiXi/writeGOD
- mouseart2025/AI-Reader-V2（中文，小说角色关系/地图/时间线）— https://github.com/mouseart2025/AI-Reader-V2

**案例**
- Neo4j NODES AI 2026: Graph-Powered Storyworlds（1M+ 字网文连贯性）— https://neo4j.com/videos/nodes-ai-2026-graph-powered-storyworlds-using-neo4j-to-keep-1m-word-litrpg-epics-coherent-w-ai/
