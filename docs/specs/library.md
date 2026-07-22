# 书库设计规范

| | |
|--|--|
| **PRODUCT** | [§4.2](../PRODUCT.md) · [§4.4a 整理三概念](../PRODUCT.md) |
| **视觉** | [DESIGN_FOUNDATION.md](../DESIGN_FOUNDATION.md) |
| **相关** | [search.md](./search.md)、[lists.md](./lists.md)、[collections.md](./collections.md) |

## 目标

**Kaika** App 内已导入条目的浏览与管理：漫画（页图）与图书（reflow）混排，通过「类型」筛选。

## 范围

- **做**：网格/列表、导入、打开（按 `kind` 路由）、搜索/排序/筛选（含类型）、详情、多选、**书单**二级、**合集**。  
- **不做**：跳转到另一 App；按品牌身份切库。

## 信息架构

```text
书库
  · 主区：单本（网格 / 列表）+ 合集卡混排（合集排最前）
  · 过滤器：类型（全部 / 漫画 / 图书）/ 状态 / 上架 / 格式 / 搜索 / 排序
  · 二级入口：
      - 书单 → 长清单管理（lists.md）
      - 合集 → 拼贴盒管理（collections.md）
```

- 导入扩展名：CBZ / ZIP / EPUB。  
- Android SAF 不可靠识别 EPUB MIME；Android 文件选择器允许浏览全部文件，返回应用后再按扩展名严格接收 CBZ / ZIP / EPUB。其他平台继续在选择器阶段过滤扩展名。
- EPUB 按内容自动路由：正文 → book；spine 抽样中绝大多数章节为低文字页图 → comic（`EpubImportRouter`）；普通封面和零散插图不参与漫画判定。
- **书单**与**合集**入口文案、图标必须区分（列表 vs 拼贴盒）。

## 打开路由

```text
点单本 → 按 item.kind 进入对应引擎
  kind=book  → BookReaderScreen
  kind=comic → ComicReaderScreen

点合集卡 → 合集内容页 → 再点成员 → 引擎
点书单 → 书单内容列表 → 再点成员 → 引擎
```

## 卡片 / 空态 / 视觉

- **单本卡**：封面 + 两行标题；可选进度 / 格式角标。  
- **合集卡**：单本卡同尺寸外框 + 内部小封面拼贴；见 collections.md。  
- 空态文案：「导入 CBZ、ZIP 或 EPUB」，主按钮「导入」。  
- 窄屏顶部不得复用桌面单行工具栏：书单 / 合集 / 布局 / 多选 / 导入保留为图标操作，搜索与排序下沉到下一行，禁止横向溢出。
- Token 与间距见 DESIGN_FOUNDATION。

## 多选

- 批量：删除、上架/移出书架、加入书单、加入合集。  
- 不在多选里混淆「创建书单」与「创建合集」的主按钮文案。
