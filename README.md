# KaikaNext

本地双品牌阅读器工程：**漫画 App** + **图书 App**，一套代码、两套打包。

| | comic | book |
|--|-------|------|
| 显示名（暂定） | Kaika Comic | Kaika Book |
| Bundle / applicationId | `com.kaika.comic` | `com.kaika.book` |
| 入口 | `lib/main_comic.dart` | `lib/main_book.dart` |
| 状态 | 导入 CBZ + 阅读闭环 | 壳已通，引擎待做 |

## 文档

- [docs/README.md](docs/README.md) — 文档索引  
- [docs/PRODUCT.md](docs/PRODUCT.md) — 产品功能  
- [docs/ENGINEERING.md](docs/ENGINEERING.md) — flavor / 工程结构  

## 运行

```sh
flutter pub get
flutter analyze && flutter test

# 漫画（默认产品）
tool/run_brand.sh comic
# 或
flutter run --flavor comic -t lib/main_comic.dart

# 图书壳
tool/run_brand.sh book macos
```

macOS 冒烟打包：

```sh
flutter build macos --debug --flavor comic -t lib/main_comic.dart
flutter build macos --debug --flavor book -t lib/main_book.dart
```

Android 需本机 JDK；`productFlavors` 已配置 comic / book。

## 分品牌图标

把 **1024×1024 PNG** 放到：

- `brands/icons/comic/master_1024.png`
- `brands/icons/book/master_1024.png`

然后：

```sh
python3 tool/generate_brand_icons.py
```

细节见 [brands/icons/README.md](brands/icons/README.md)。当前为可区分的占位图（橙 C / 灰 B）。

## 约定

见根目录 [AGENTS.md](AGENTS.md)。
