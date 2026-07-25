# 开卷

本地阅读 App：一套安装包，双引擎——漫画（页图）与图书（reflow）。

Flutter · 当前版本 **0.1.1** · 包名 `com.kaijuan.reader`

| | |
|---|---|
| 仓库 | [github.com/robeshell/kaijuan](https://github.com/robeshell/kaijuan) |
| 入口 | `lib/main.dart` |
| 格式 | CBZ / ZIP / EPUB（按内容自动路由到漫画或图书引擎） |
| 设计规范 | [`kai-brand-design`](https://github.com/robeshell/kai-brand-design)（品牌层 + `products/kaijuan/`） |

## 平台

| 平台 | 状态 |
|------|------|
| Android | 支持 |
| iOS / iPadOS | 支持 |
| macOS | 支持 |
| Windows | 支持 |
| Linux | 非目标 |

## 功能

- **导入** — CBZ / ZIP / EPUB；内容哈希去重；EPUB 自动识别页图或正文
- **书库** — 漫画与图书混排；类型筛选；搜索 / 排序 / 多选管理
- **整理** — 我的书架 · 书单 · 合集
- **漫画阅读** — 四模式、方向、主题、双页、缩放、缩略图跳页
- **图书阅读** — reflow、目录 / 书签 / 笔记、排版、划线、听书（TTS）
- **设置** — 主题与强调色；阅读偏好在对应阅读器内调整

产品权威清单见 [docs/PRODUCT.md](docs/PRODUCT.md)。

## 开发

```sh
flutter pub get
flutter run -d macos   # 或 <device-id>
```

```sh
flutter analyze
flutter test
```

工程边界与验证细节见 [docs/ENGINEERING.md](docs/ENGINEERING.md)。

## 发布

不要直接 `flutter build … --release` 出货。版本以 `pubspec.yaml` 为准：

```sh
dart run tool/release.dart --dry-run
dart run tool/release.dart android
dart run tool/release.dart android macos
dart run tool/release.dart windows
dart run tool/release.dart android --no-bump
```

推送 `vMAJOR.MINOR.PATCH` tag 可触发 GitHub Release 工作流。Windows MSIX / Inno 仅本地 `release.dart windows` 产出，说明见 [`packaging/windows/README.md`](packaging/windows/README.md)。

## 文档

| 文档 | 说明 |
|------|------|
| [docs/README.md](docs/README.md) | 文档索引 |
| [docs/PRODUCT.md](docs/PRODUCT.md) | 产品功能（权威） |
| [docs/ENGINEERING.md](docs/ENGINEERING.md) | 工程结构 |
| [docs/DESIGN_FOUNDATION.md](docs/DESIGN_FOUNDATION.md) | 视觉原则 |
| [DESIGN.md](DESIGN.md) | 产品设计入口（指向品牌规范） |
| [docs/specs/](docs/specs/) | 分屏交互 |
| [AGENTS.md](AGENTS.md) | 代码约定 |

## 许可

仓库尚未放置开源许可证文件；在另行声明前保留所有权利。
