# KaikaNext 开发约定

Flutter 重写版多格式阅读器（原 Swift 项目在同级目录 `../kaika`，**不迁移旧数据**）。

## 项目身份

- 路径：`/Users/wangwenyu/Documents/Code/KaikaNext`
- 包名：`kaika`（pubspec；对用户不可见）
- 平台：iOS / iPadOS / macOS / Windows / Android
- 参照工程：`../MusicPlayerNext`（Reverie）分层与工程范式
- 设计方向：轻玻璃中性风、浅色验收基线；阅读主题与 App chrome 分离

## 优先级

1. 用户当前明确要求
2. 不破坏已能工作的导入 / 阅读链路
3. 表现层不直连 drift；业务经 controller
4. 先写 `docs/specs/` 再写对应 UI

## 分层

```text
lib/
  app/                 — App、ThemePreferences
  core/                — 设计 token（AppSpacing / AppRadii / AppSemantics / AppTheme）
  domain/              — ReaderFormat / ReaderKind / ReaderLocator / ComicPageOrder
  library/
    import/            — ComicArchive、ComicImportService
    persistence/       — AppDatabase (drift)
  readers/comic/       — ComicSession、ComicPageCache、comic_models
  presentation/
    controllers/       — LibraryController、ComicReaderController
    screens/
    widgets/reader/
```

## 已定架构决策（勿轻易推翻）

- **v1 先漫画后图书**；EPUB reflow 先 spike 再定引擎
- **ReaderLocator 不透明 JSON**：DB 永不解析 payload；稳定 identity 在格式内部
- **漫画页序契约**：`ComicPageOrder.version`（当前 1）+ 导入时写入 `pageCount` / `pageOrderVersion`
- **内容寻址导入**：`contentHash` 去重；文件在 app support `library/` + `covers/`
- **表现层只认 controller**：Screen 不直接调 drift / import service
- **阅读 session 开一次 archive**：`ComicSession` 复用，不要每页 reopen zip
- 文件名/类型名**不要带应用名**（已从 `Kaika*` 收口到 `App*`）；包名 `kaika` 可暂留

## 当前进度（2026-07-20）

HEAD 参考：`e06df69`（漫画阅读器 session + 四模式）

已完成：

- Phase 0 骨架：主题 token、三 Tab 壳、drift 三表
- 设计总纲 `docs/DESIGN_FOUNDATION.md` + `docs/specs/reader-chrome.md`
- CBZ/ZIP 导入 + 书库网格
- macOS `user-selected.read-only` entitlement
- LibraryController + IndexedStack
- 漫画阅读器：slide / static / vertical / spread；进度恢复；玻璃 chrome

已知轻债 / 下一步：

1. 书架「继续阅读」接线（`lastOpenedAt` + progress）
2. 阅读偏好持久化（mode / direction / reading theme）
3. 纵向模式滚动位置 ↔ pageIndex 同步
4. 双页模式按 spread 步进
5. 删除 UI / 失败详情；import 集成测试已有

## 验证

```sh
flutter analyze
flutter test
flutter build macos --debug
# 或
flutter run -d macos
```

## 与旧 kaika

- 旧项目 Swift/SwiftUI 阅读器架构文档仍可参考 identity / 渲染决策
- **不要**在 KaikaNext 照搬旧模块目录或迁移 SwiftData
