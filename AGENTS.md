# KaikaNext 开发约定

Flutter 仓库：**两个品牌阅读 App**（comic / book）共享底座。  
原 Swift 工程在 `../kaika`，**不迁移旧数据**。

## 项目身份

- 路径：`/Users/wangwenyu/Documents/Code/KaikaNext`
- 当前可运行：以 **comic** 闭环为主（`lib/main.dart`）
- 目标：一套仓库打出两个商店 App（见 `docs/ENGINEERING.md`）
- 平台：iOS / iPadOS / macOS / Windows / Android
- 参照：`../MusicPlayerNext` 分层范式

## 文档

**[docs/README.md](docs/README.md)** 索引。

| 权威 | 文件 |
|------|------|
| 双产品功能 | `docs/PRODUCT.md` |
| 视觉 | `docs/DESIGN_FOUNDATION.md` |
| 工程骨架 / 迁移 | `docs/ENGINEERING.md` |
| 交互 | `docs/specs/*` |

## 优先级

1. 用户当前明确要求  
2. 不破坏 comic 已可用的导入 / 阅读链路  
3. 表现层不直连 drift；经 controller  
4. **先更新 PRODUCT / ENGINEERING / specs，再写 UI 与拆包**

## 分层（现状 → 目标）

**现状（单 app 模块，漫画可用）：**

```text
lib/
  app/ brand/          — BrandConfig（骨架）
  main.dart            — 默认 comic
  main_comic.dart / main_book.dart
  core/ domain/ library/ readers/comic/ presentation/
```

**目标：** `apps/comic`、`apps/book` + `packages/kaika_core` 等，见 ENGINEERING。

## 已定架构决策

- **双 App 双品牌**，数据默认隔离；非单 App 混库主路径。  
- **ReaderLocator 不透明 JSON**。  
- **漫画页序** `ComicPageOrder.version` + 导入 pageCount。  
- **内容寻址导入**（每 App 自己的 library 目录）。  
- **表现层只认 controller**；ComicSession 复用。  
- 类型名不带应用名（`App*`）；包名可按 flavor 分。

## 进度摘要

- **已有（comic）**：导入 CBZ/ZIP/页图 EPUB；书库搜索/排序/筛选/删除/上架/详情重命名/书单；四模式阅读；进度与书架；偏好；桌面壳。  
- **文档**：双 App 产品 + ENGINEERING；EPUB 页图归 comic、reflow 归 book。  
- **骨架**：`BrandConfig` + flavor + 双 main。  
- **整理三概念**：**我的书架**钉选 · **书单**长列表 · **合集**拼贴盒（**书库**最前混排，见 `docs/specs/collections.md`）。  
- **下一刀**：book reflow spike；书签 UI；合集/书单体验打磨。

全表以 **PRODUCT.md** 为准。

## 验证

```sh
flutter analyze
flutter test
tool/run_brand.sh comic          # 或 book
# flutter build macos --flavor comic -t lib/main_comic.dart
# 详见 docs/ENGINEERING.md §5
```

## 与旧 kaika

可参考 identity / 渲染文档；不照搬 Swift 目录、不迁 SwiftData。
