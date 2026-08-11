# 图书结构索引

| | |
|--|--|
| **状态** | 迁移中；新索引与旧正文标记兼容并行 |
| **适用** | Foliate reflow 图书；漫画页图不进入本索引 |
| **相关** | [book-reader.md](./book-reader.md)、[ai.md](./ai.md)、[ai-mind-map.md](./ai-mind-map.md)、[ai-graph.md](./ai-graph.md) |

## 1. 结论

图书结构事实与 AI 正文载荷必须分开：

- `BookStructureIndex` 是一份完整、可定位、无正文的阅读器事实，保留 EPUB navigation、全部 spine 文档标题、DOM heading、层级、顺序、`href/fragment/CFI` 和正文字符数。
- `BookCorpus` 根据冻结范围按需读取正文；给模型的 `[§]` 标记只是一种正文传输格式，不再作为作品/章节识别的权威输入。
- `BookPublicationClassifier` 只判断普通单本、单本分部/分卷、多作品合订或证据不足，不重新发现章节。
- `BookScopeResolver` 把当前 Locator、用户选择和内容排除规则转换为冻结范围，供对话、思维导图、大纲与知识图谱共同消费。

## 2. 结构数据源

Foliate 在同一次惰性结构扫描中完整遍历 spine，只读取结构信息，不把正文传回 Dart：

```text
EPUB nav / landmarks ─┐
                      ├─ BookStructureIndex
全部 spine DOM heading ┤
spine href / CFI ──────┘
```

索引同时记录出版物标题，App 条目标题/原文件名可作为 OPF 标题缺失集合信息时的补充证据，但都不能单独成为结论。每个 spine 记录 `sectionIndex / href / documentTitle / bodyCharCount`；每个 heading 记录 `title / level / order / fragment / cfi`；每个 navigation 节点记录 `parentId / depth / order / href / fragment / resolvedSectionIndex / directChildCount`。

扫描不得按字符预算、正文长度或前 N 章截断。结构结果按打开的出版物实例缓存；正文仍按任务范围与模型上下文能力独立读取。

## 3. 对齐与分类

原始 nav 与 DOM heading 都保留来源。标题、物理 section 和 fragment/CFI 能对齐时合并为同一规范节点；无法对齐的 heading 作为补充章节存在，不能覆盖或删除原 nav。

分类前先为顶层结构节点确定角色：`work`（独立作品）、`volume`（单本分部/分卷）、`chapter`（普通章节）或 `supplement`（封面、目录、简介、推荐、前后记等外围内容）。角色规则由共享结构层提供，运行时与本地审计不得各维护一套近似规则。

分类采用保守先验，但不得把这些先验写成互相遮蔽的串行早退。解析器先并行生成 `single / volume / top-level work tree / grouped work / flat directory` 等完整范围候选，再由确定性的全局求解器比较整套方案：

- 默认 `singleWork`。
- 多个“第 X 部/卷/Book/Volume”顶层范围属于 `segmentedSingleWork`。
- `multiWorkOmnibus` 必须有至少两个可定位范围，并由“全集/套装/部曲”等出版物级元数据、连续多组“上/中/下”拆册或同等强证据佐证；单凭顶层节点拥有子章节不能证明它是多作品合集。
- “作品（上）/作品（中）/作品（下）”先合并为一部作品；不得把物理拆册数量展示成作品数量。
- 章/节/篇标题、破折号连续副标题、前后记与附录不能作为多作品证据。
- 证据冲突时保持 `uncertain`；普通全书任务仍按单本出版物处理，只有作品级任务才请求用户确认。

每套候选必须携带策略名、结构证据、拒绝原因、分数和完整范围。锚点缺失、范围交叉、为凑数量而猜测合并属于硬拒绝，不能被软分数抵消。App 书名可编辑，OPF 标题与原文件名也可能由发布者随意填写，其中的“共 N 册/1–8 全集”只能提供低权重提示：数量吻合可以小幅加分，冲突不能否决由 EPUB 锚点证明完整的方案。软分数只比较已经满足硬约束的方案，参考章节序号重置、子树完整性、重复目录形态、正文覆盖、结构一致性与出版物级合集证据。得分相近但范围不同的方案不得自动决策，应返回 `uncertain` 并保留候选供对话确认。

类型判定与范围构造必须分开：`segmentedSingleWork.works` 只能由 `volume` 节点建立；`multiWorkOmnibus.works` 只能由 `work` 节点建立。其他节点可以提供下一范围或尾部外围材料的边界，但不得成为独立生成单元。不得根据书名声明数量删除、拼接或平均分配结构节点。

目录层级不可靠时仍按结构证据恢复：标题等同于出版物总集名称的节点视为容器；“第 X 季/辑/系列”等中间分组递归展开后再取作品；完全扁平的 NCX 可利用重复的“作品标题 → 目录/目次 → 正文”边界提取作品起点。分组、树形和扁平方案分别完成范围构造后再竞争，不以书名数量决定某一种方案是否有资格参与。章节占多数只能证明普通单本，不能覆盖更强的可定位作品结构。

用户确认按 `contentHash + indexVersion + structureFingerprint` 保存为 `BookStructureOverride`。本阶段先实现索引、分类与范围消费；持久化覆盖在索引稳定后接入，不把临时启发式写入数据库。

求解器先以影子报告接入真实 EPUB 审计：报告旧/新结论、入选策略、候选得分和硬拒绝原因，不输出正文。迁移验收要求现有高置信样本零回退；只有经过真实书籍基线验证的高置信结果才接管运行时，中低置信结果继续走用户确认。

## 4. 冻结范围

```text
FrozenBookScope
  label
  startAnchor / endAnchor
  sectionIndices
  structureNodeIds
  estimatedChars
```

- 当前章由当前 `BookLocator` 查询索引得到，不使用 `_tocTitles[sectionIndex]` 猜测。
- 普通全书覆盖全部正文节点，再叠加本次 `ContentPolicy`。
- 分卷或作品范围由结构节点的起止锚点产生；范围先冻结，随后翻页不得改变任务输入。
- 内容规则只决定前言、版权、附录等是否进入本次模型调用，不得反向改变出版物分类。

## 5. 迁移边界

1. 新增索引协议与惰性扫描；旧 `getBookPlainText` 继续负责正文。
2. `AiBookStructureSession` 优先消费 `BookStructureIndex`，索引不可用时才回退旧 `[§]` 识别。
3. 当前章、全书和可物理定位的作品范围迁移到索引；同 spine 细粒度范围在锚点正文读取接入前保持不确定，不伪装成可精确裁剪。
4. 思维导图首先迁移；对话、大纲和知识图谱随后复用同一 Session，不各建识别器。
5. 真实 EPUB 审计覆盖普通单本、分卷单本、多作品合订、超长书、无 nav、同 spine 多标题与页图 EPUB。

## 6. 性能与隐私

- 结构扫描只返回标题、锚点和字符计数；不上传、不持久化正文。
- 单次扫描顺序释放每个 `section.createDocument()` 结果，避免同时保留整本 DOM。
- 结构缓存只属于当前阅读实例；索引协议升级通过 `indexVersion` 失效。
- 测试真实书籍时只输出文件名、结构统计、分类和异常，不把正文或标题明细写入仓库测试夹具。

## 7. 验收

- 章节标题与副标题共享 spine/导航目标的普通单本不得显示作品选择。
- 哈利波特、沙丘等顶层作品各自拥有章节树的合集应识别为多作品。
- 普通技术书的每章即使拥有大量小节，也不得因为“顶层节点有子树”而误判为合集。
- 单本分部/分卷应识别为一部作品的多个自然范围。
- 同一索引存在树形、分组和扁平目录等多套候选时，求解结果不得依赖候选生成顺序；交换候选顺序必须得到同一结论。
- 书名册数与可定位方案冲突时记录诊断但不否决方案；不得通过删除、拼接或平均分配节点凑数。
- 索引节点数量不受 AI 正文字符预算影响；每个节点具有可用 section 锚点，DOM heading 尽可能具有 CFI。
- 索引失败时有明确 fallback 日志，不影响阅读；任何 AI 功能不得因结构扫描失败而无法使用普通全书范围。
