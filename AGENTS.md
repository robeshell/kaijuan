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
  app/ brand/          — BrandConfig、阅读偏好
  main.dart            — 默认 comic
  main_comic.dart / main_book.dart
  core/ domain/
  library/import/      — ComicImportService / BookImportService
  readers/comic/       — 页图 session
  readers/book/        — reflow EPUB（纯文本 spike）
  presentation/
```

**目标：** `apps/comic`、`apps/book` + `packages/kaika_core` 等，见 ENGINEERING。

## 已定架构决策

- **双 App 双品牌**，数据默认隔离；非单 App 混库主路径。  
- **ReaderLocator 不透明 JSON**（comic 页 / book 节+节内进度）。  
- **漫画页序** `ComicPageOrder.version` + 导入 pageCount。  
- **内容寻址导入**（每 App 自己的 library 目录）。  
- **表现层只认 controller**；ComicSession / BookEpub 按品牌分流。  
- 类型名不带应用名（`App*`）；包名可按 flavor 分。

## 进度摘要

- **已有（comic）**：导入 CBZ/ZIP/页图 EPUB；书库管理；合集/书单；四模式阅读；进度与书架；偏好；桌面壳。  
- **已有（book spike）**：reflow EPUB 导入（`kind=book`）；`BookReaderScreen` 分节滚动/目录/字号/主题；`BookLocator` 进度恢复；设置阅读默认。  
- **文档**：双 App 产品 + ENGINEERING；`specs/book-reader.md`。  
- **整理三概念**：**我的书架** · **书单** · **合集**（书库最前）。  
- **下一刀**：book reflow 版式加深（HTML/CSS）；书签 UI；合集/书单体验打磨。

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
