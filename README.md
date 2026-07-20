# KaikaNext

**Kaika：本地阅读 App，一套代码、双引擎（漫画 + 图书）。**

| | |
|--|--|
| 显示名 | Kaika |
| Bundle / applicationId | `com.kaika.reader` |
| 入口 | `lib/main.dart` |
| 格式 | CBZ / ZIP / EPUB（按内容自动路由） |
| 状态 | 漫画页图闭环 + 图书 reflow spike |

## 文档

- [docs/README.md](docs/README.md) — 文档索引  
- [docs/PRODUCT.md](docs/PRODUCT.md) — 产品功能  
- [docs/ENGINEERING.md](docs/ENGINEERING.md) — 工程结构  

## 运行

```sh
flutter pub get
flutter analyze && flutter test

# 开发运行
flutter run -d macos

# 旧双品牌脚本（保留兼容）
tool/run_brand.sh
```

macOS 冒烟打包：

```sh
flutter build macos --debug
```

## 校验

```sh
flutter analyze   # No issues
flutter test      # 46/46 passing
```

## 图标

把 **1024×1024 PNG** 放到 `brands/icons/comic/master_1024.png`，然后：

```sh
python3 tool/generate_brand_icons.py
```

细节见 [brands/icons/README.md](brands/icons/README.md)。

## 约定

见根目录 [AGENTS.md](AGENTS.md)。
