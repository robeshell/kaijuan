# 书架设计规范

| | |
|--|--|
| **PRODUCT** | [§4.5](../PRODUCT.md) · [§4.4a 整理三概念](../PRODUCT.md) |
| **视觉** | [DESIGN_FOUNDATION.md](../DESIGN_FOUNDATION.md) |
| **相关** | [library.md](./library.md)、[lists.md](./lists.md)、[collections.md](./collections.md) |

## 目标

本 App 内「接下来读什么」：继续阅读、最近、**我的书架**（钉选）。  
数据仅来自 **本 App 库**（与另一品牌 App 隔离）。

## 信息架构

1. **继续阅读** — `lastOpenedAt` 降序；首卡 + 最近横向条。  
2. **我的书架** — 仅 **单本** 钉选横滑（`reading_items.onShelf`）。  
3. **合集** 在 **书库** 展示，不在书架横滑。  
4. **不**在书架根上堆书单长列表（书单在书库二级）。

## 我的书架 vs 书单 vs 合集

| | 我的书架 | 书单 | 合集 |
|--|----------|------|------|
| 数量 | 全局一个钉选池 | 多个清单 | 多个盒子 |
| 形态 | 横滑封面 | 长列表 | 拼贴大卡 |
| 字段/表 | `onShelf` | `reading_lists*` | `collections*`（待） |

## 进度与交互

- 展示 `progress_fraction`；不解析 locator。  
- 点按单本 → 本 App 阅读器。  
- 移出书架：封面按钮 / 长按菜单（不删书）。  
- 空态引导 **本 App 书库**。

## 视觉

封面主角；进度用品牌强调色细条。Token 见 DESIGN_FOUNDATION。
