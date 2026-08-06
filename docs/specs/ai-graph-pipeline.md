# 图谱构建 pipeline 与领域方法对齐

> 状态：**已对齐**（2026-08-07 完成）
> 目的：把「我们的知识图谱生成流程」与知识图谱构建领域的标准方法一一对上，
> 每个阶段使用有据可查的方法，不再凭经验打补丁。
> 依据：用户实测《万历十五年》发现「慈圣太后/慈圣皇太后/孝定皇太后」同一人
> 未合并、「正德皇帝→万历皇帝」错误关系——根因是共指消解（实体合并）只靠
> 精确 alias 匹配 + 浅启发式，未按领域 ER 管线实现。

## 1. 流程对照表

权威框架：Hogan et al., "Knowledge Graphs", ACM Computing Surveys 54(4):71,
2021（creation → enrichment → quality assessment → refinement → publication）
；Ji et al., IEEE TNNLS 33(2), 2022（knowledge acquisition：entity
discovery / relation extraction / knowledge fusion）。

| # | 阶段 | 领域标准方法 | 出处 | 我们的实现 | 状态 |
|---|---|---|---|---|---|
| 0 | 正文切片 | 抽取预处理（文档级滑窗） | 非独立标准阶段（工程预处理） | TOC/spine 切分 + metadata/appendix 过滤 + 用户手动排除 | ✅ 我方特有，已对齐 |
| 1 | 实体识别 NER | LSTM-CRF 序列标注 → LLM-based IE | Lample et al., NAACL 2016；LLM-IE 综述 arXiv:2312.17617 | LLM 逐章单次输出实体 | ✅ |
| 2 | 关系抽取 RE | distant supervision / 分类 → LLM | Zhao et al. RE 综述 | LLM 输出关系 + 方向性约定（亲属/师徒/隶属/效力/追随） | ✅ |
| 3 | 实体链接/共指 | 端到端神经共指（OntoNotes） | Lee et al., EMNLP 2017 | 精确 alias 缓存 | ✅ 已对齐（见 §2.1） |
| 4 | 记录链接/实体消解 | Fellegi–Sunter 概率匹配；blocking | Fellegi & Sunter, JASA 1969；Christen 2012；Dedupe/Splink | 无 → 按 ER 管线重做（候选+打分+阈值） | ✅ 已对齐（见 §2.1） |
| 5 | 知识融合 | 置信度加权事实融合 | Dong et al., Knowledge Vault, KDD 2014 | mergeKey 去重 + 端点归一 | ✅ 已对齐 |
| 6 | 质量评估 | 18 维度（准确/完整/一致/时效） | Zaveri et al., Semantic Web 7(1), 2016 | scope 硬规则 + evidence 锚定 + mergeLog 审计 | ✅ 已对齐 |
| 7 | 证据锚定 provenance | 事实置信度/上下文溯源 | Hogan 综述 identity/context 议题 | quote→原文 span 定位 + 跳转 | ✅ |
| 8 | 增量构建 | incremental KGE / 流式记录链接 | IncDE arXiv:2405.04453；IEEE 流式 RL 2021 | coveredSections + existing 合并 | ✅ |
| 9 | 应用层 | QA/可视化 | Hogan 综述 coverage 章 | 列表/力导向/家族树/时间线/地点链 | ✅（展示方案属此层） |

## 2. 对齐计划（按差距大小排序）

### 2.1 共指消解 + 记录链接（#3+#4，最大差距）→ 已重做（ER 管线）

现状（重做前）：`_mergeChunk` 里 `canonical` 缓存，`_resolveCanonical/_resolveAliases`
精确匹配 + `_resolveSimilarName`（后缀/子串启发式）。缺领域 ER 管线的三层。

已实现（Fellegi–Sunter 概率模型 + Dedupe/Splink 工程实践）：
1. **候选生成（blocking）**：按 type 分桶（已有）；对每个新 mention 生成候选对：
   - 名称结构：精确命中 / 去称谓后缀 stem 相等 / 子串
   - **关系证据**：与同一第三方有「同向同类型」关系（上溯关系强 0.5，下溯弱 0.1——
     两个儿子共享父≠同一人）
2. **打分**：名称相似 1.0/0.7（stem）/0.5（子串）· 关系证据每条 0.5（上溯）/0.1（下溯）
3. **阈值分派**：名称 ≥0.5 直接合并；关系证据单独命中（无名称相似）进 LLM 复核
   （每本 ≤10 对，批量一次调用，判定 same/different/uncertain，失败静默不阻塞生成）；
   其余不合并
4. **合并审计**：每次模糊合并记 mergeLog（from/to/score/reason/section）存图谱包
   `mergeLog` 段（splink/dedupe 标配），兼容旧缓存

### 2.2 知识融合（#5）→ 已对齐

实体属性融合：aliases 取并、description 取已有、evidence 取并去重、chapterFreq 累加
（`_mergeEntityEvidence`）。关系融合：mergeKey（source|target|type）去重保留并合并
证据、weight=证据数（`_mergeRelationEvidence`）；复核归一时重复键保留证据更多者
（Knowledge-Vault 风格）。

### 2.3 质量评估（#6）→ 已对齐

scope 硬规则（引用句式降级）、evidence 锚定（quote→原文 span）、矛盾（complex）
节点标记均已有；本次补：**合并置信度/审计日志 mergeLog**（每条模糊合并的分数
入图谱包，可选，兼容旧缓存）。冲突防护：type 分桶防同人异型、端点类型由既有
实体决定。

### 2.4 关系后验校验（#3 关联）→ 已确认

「无 evidence 的关系被丢弃」为强制行为（`_evidenceFor` 空则 continue，测试锁定）；
方向校验不做硬规则（无法后验判断谁是长辈，靠 prompt + 证据锚定）。

## 3. 验收

- 万历十五年重新生成：慈圣太后/慈圣皇太后（名称 stem 0.7）本地合并；
  孝定皇太后（共享母子关系 0.5 + LLM 复核）合并；正德皇帝/万历皇帝 不合并；
  潞王-万历 兄弟边保留
- 家族树不再出现「同一人分裂」「跨代错误父子边」
- 反向重复亲属边消解（A→B / B→A 同 kin 保留强方向）——修复模型方向颠倒导致的
  complex 误标（万历皇帝曾被错标并深藏）
- 主角 scope 保护（证据 ≥5 且零引用句式 → setting）+ 「根据X」不再误判引用句式——
  修复 张居正 被误标 reference 而从家族树消失
- 全量测试 + analyze 通过（本次：379 用例 + 0 error）

## 4. 出处链接

- Hogan et al. 2021: https://arxiv.org/abs/2003.02320
- Ji et al. 2022: https://researchportal.helsinki.fi/en/publications/a-survey-on-knowledge-graphs-representation-acquisition-and-appli
- Fellegi & Sunter 1969: https://zbmath.org/0186.53903
- Christen, Data Matching 2012: https://www.springer.com/cda/content/document/cda_downloaddocument/9783642311635-t1.pdf
- Dedupe: https://github.com/dedupeio/dedupe ；Splink: https://moj-analytical-services.github.io/splink/
- Dong et al., Knowledge Vault, KDD 2014: https://dl.acm.org/doi/10.1145/2623330.2623623
- Zaveri et al. 2016: https://dblp.org/rec/journals/semweb/ZaveriRMPLA16.html
- Lee et al., EMNLP 2017: https://arxiv.org/abs/1707.07045
- Lample et al., NAACL 2016: https://arxiv.org/abs/1603.01360
- LLM-IE 综述: https://browse.arxiv.org/abs/2312.17617
- IncDE: https://ar5iv.labs.arxiv.org/html/2405.04453
