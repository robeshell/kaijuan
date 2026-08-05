# kaijuan 开发约定

Flutter 仓库：**一个本地阅读 App（开卷）**，内建漫画页图引擎 + 图书 reflow 引擎。  
原 Swift 工程在 `../kaika`，**不迁移旧数据**。

## 项目身份

- 路径：`/Users/wangwenyu/Documents/Code/kaijuan`
- 当前可运行：`lib/main.dart` 单一入口
- 目标：一个安装包、一套数据、两个阅读引擎（见 `docs/ENGINEERING.md`）
- 包名：`com.kaijuan.reader`
- Dart 包名：`kaijuan`
- 平台：iOS / iPadOS / macOS / Windows / Android
- 参照：`../kaiting` 分层范式

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
2. 不破坏已有的导入 / 阅读链路  
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
    persistence/               — AppDatabase（app_library，沿用已有数据）
  readers/comic/               — 页图 session
  readers/book/                — reflow EPUB（纯文本 spike）
  presentation/
    controllers/               — LibraryController / BookReaderController 等
    screens/ widgets/          — UI 与桌面 chrome
```

## 已定架构决策

- **单 App 双引擎**；条目 `kind`（comic/book）决定路由到哪个阅读器。  
- **数据沿用** 已有 `app_library` + support root（已有数据不丢失）。  
- **EPUB 自动探测**：Dart ZIP/OPF spine 抽样（`EpubKindProbe`）— 正文 → 图书；页图 → 漫画；页图路径不经 WebView。  
- **ReaderLocator 不透明 JSON**（comic 页 / book 节+节内进度）。  
- **漫画页序** `ComicPageOrder.version` + 导入 pageCount。  
- **内容寻址导入**（同 hash 只存一份文件）。  
- **表现层只认 controller**；ComicSession / Foliate book 引擎按 kind 分流。  
- 类型名不带应用名（`App*`）；包名 `com.kaijuan.reader`。

## 进度摘要

全表以 **`docs/PRODUCT.md`** 为准（已按当前基线重写）。摘要：

- **已有**：单入口双引擎；本地/扫描/WiFi/WebDAV/OPDS 导入；多格式 book+comic；整理三概念；漫画四模式；图书 Foliate 主链；阅读统计；WebDAV 备份；**AI M0–M3**（BYOK + 选区 AI 词典/翻译 + 本书对话 + 大纲；对话随 WebDAV 快照备份，Key 不进备份）。  
- **下一程（产品）**：AI M4+（整本译 → 知识图谱 → Obsidian 导出），见 PRODUCT §6 / `docs/specs/ai.md`。  

- **结构债（工程）**：Book god-controller；readers→presentation 依赖；仿真翻页搁置。

## 验证

```sh
flutter analyze
flutter test
flutter run -d macos
# 详见 docs/ENGINEERING.md §5
```

## 与旧 kaika

可参考 identity / 渲染文档；不照搬 Swift 目录、不迁 SwiftData。
