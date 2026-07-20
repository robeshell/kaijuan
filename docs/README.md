# KaikaNext 文档索引

仓库实现 **两个品牌阅读 App**（comic / book）共享技术底座。  
权威与扩展方法以本页为准。

## 读哪份

| 你要… | 打开 |
|--------|------|
| 双产品功能、阶段、非目标 | [PRODUCT.md](./PRODUCT.md) |
| 共享视觉 + 分品牌 | [DESIGN_FOUNDATION.md](./DESIGN_FOUNDATION.md) |
| monorepo / flavor / 数据隔离 | [ENGINEERING.md](./ENGINEERING.md) |
| 某屏交互 | [specs/](./specs/) |
| 给 Open Design | [opendesign/HANDOFF.md](./opendesign/HANDOFF.md) |
| 代码约定 | [../AGENTS.md](../AGENTS.md) |
| 会话交接（易过期） | [dev-handoff.md](./dev-handoff.md) |

## 目录树

```text
docs/
  README.md
  PRODUCT.md                 ← 产品权威（双 App）
  DESIGN_FOUNDATION.md       ← 视觉权威
  ENGINEERING.md             ← 工程骨架与迁移
  dev-handoff.md
  specs/
    _TEMPLATE.md
    library.md / shelf.md / search.md / lists.md / collections.md / reader-chrome.md
  opendesign/
    HANDOFF.md / CONTEXT.md / DESIGN.md / BRIEFS.md
```

## 权威层级

1. **PRODUCT.md** — 两个产品做什么  
2. **DESIGN_FOUNDATION.md** — 长什么样  
3. **ENGINEERING.md** — 仓库怎么拆、怎么打两个包  
4. **specs/** — 单屏交互  
5. **AGENTS.md** — 实现约束  
6. **opendesign/** — 出图；不发明 PRODUCT 没有的能力  
7. **dev-handoff.md** — 仅续聊  

## 已定原则（摘要）

- **两个 App、两套品牌**（名字/图标/默认设定/导入白名单/数据隔离）。  
- **一个仓库**，共享 core；不是两个互不理的复制项目。  
- 单 App 内 **不再** 用「漫画 \| 图书」主分段。  
- 用户要两类内容 → 装两个 App。  

## 如何扩展

### 加功能

1. 改 PRODUCT §4 表（标明 comic / book / 共享）。  
2. 开或改 specs。  
3. 实现挂对应 app 或 core（见 ENGINEERING）。  

### 加品牌差异（色、空态、格式）

1. PRODUCT / DESIGN 说明默认差异。  
2. `BrandConfig`（ENGINEERING）加字段。  
3. 出图用 opendesign 分品牌 brief。  

### 加工程包

1. 改 ENGINEERING 目标树。  
2. 再改代码骨架。  

## specs 一览

| Spec | 说明 |
|------|------|
| library / shelf / search | 书库 / 书架 / 搜索 |
| lists | **书单**（长清单） |
| collections | **合集**（拼贴盒；实现中） |
| reader-chrome | 共享 chrome 语言 |
| book-reader | **待写**（book 引擎） |
| settings / mobile / overlay | **待写** |

整理三概念权威表见 [PRODUCT.md §4.4a](./PRODUCT.md)。
