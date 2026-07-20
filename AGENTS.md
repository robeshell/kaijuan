# KaikaNext 开发约定

Flutter 仓库：**一个本地阅读 App**，内建漫画页图引擎 + 图书 reflow 引擎。  
原 Swift 工程在 `../kaika`，**不迁移旧数据**。

## 项目身份

- 路径：`/Users/wangwenyu/Documents/Code/KaikaNext`
- 当前可运行：`lib/main.dart` 单一入口
- 目标：一个安装包、一套数据、两个阅读引擎（见 `docs/ENGINEERING.md`）
- 平台：iOS / iPadOS / macOS / Windows / Android
- 参照：`../MusicPlayerNext` 分层范式

## 文档

**[docs/README.md](docs/README.md)** 索引。

| 权威 | 文件 |
|------|------|
| 产品功能 | `docs/PRODUCT.md` |
| 视觉 | `docs/DESIGN_FOUNDATION.md` |
| 工程骨架 | `docs/ENGINEERING.md` |
| 交互 | `docs/specs/*` |

## 优先级

1. 用户当前明确要求  
2. 不破坏 comic 已可用的导入 / 阅读链路  
3. 表现层不直连 drift；经 controller  
4. **先更新 PRODUCT / ENGINEERING / specs，再写 UI 与拆包**

## 分层

```text
lib/
  main.dart                    — 唯一入口；main_comic/main_book 为兼容重定向
  brand/brand_config.dart      — 单 App 配置（BrandConfig.app）
  app/                         — App widget、theme/comic/book preferences
  core/ domain/                — 主题 token、ReaderKind/Format/locator
  library/
    import/                    — ComicImportService / BookImportService / EpubImportRouter
    persistence/               — AppDatabase（app_library，沿用 comic 数据）
  readers/comic/               — 页图 session
  readers/book/                — reflow EPUB（纯文本 spike）
  presentation/
    controllers/               — LibraryController / BookReaderController 等
    screens/ widgets/          — UI 与桌面 chrome
```

## 已定架构决策

- **单 App 双引擎**；条目 `kind`（comic/book）决定路由到哪个阅读器。  
- **数据沿用** comic 的 `app_library` + support root（已有 comic 数据不丢失）。  
- **EPUB 自动探测**：正文 → 图书引擎；页图 → 漫画引擎（`EpubImportRouter`）。  
- **ReaderLocator 不透明 JSON**（comic 页 / book 节+节内进度）。  
- **漫画页序** `ComicPageOrder.version` + 导入 pageCount。  
- **内容寻址导入**（同 hash 只存一份文件）。  
- **表现层只认 controller**；ComicSession / BookEpub 按 kind 分流。  
- 类型名不带应用名（`App*`）；包名暂留 `com.kaika.comic`。

## 进度摘要

- **已有（comic）**：导入 CBZ/ZIP/页图 EPUB；书库管理；合集/书单；四模式阅读；进度与书架；偏好；桌面壳。  
- **已有（book spike）**：reflow EPUB 导入（`kind=book`）；`BookReaderScreen` 分节滚动/目录/字号/主题；`BookLocator` 进度恢复。  
- **已有（合并）**：单入口/单库混排；类型筛选（全部/漫画/图书）；EPUB 自动探测；两组阅读默认并排。  
- **整理三概念**：**我的书架** · **书单** · **合集**（书库最前）。  
- **下一刀**：book reflow 版式加深（HTML/CSS）；书签 UI；合集/书单体验打磨。

全表以 **PRODUCT.md** 为准。

## 验证

```sh
flutter analyze
flutter test
flutter run -d macos
# 详见 docs/ENGINEERING.md §5
```

## 与旧 kaika

可参考 identity / 渲染文档；不照搬 Swift 目录、不迁 SwiftData。
