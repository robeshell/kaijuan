# kaijuan

**开卷：本地阅读 App，一套代码、双引擎（漫画 + 图书）。**

| | |
|--|--|
| 显示名 | 开卷 |
| Bundle / applicationId | `com.kaijuan.reader` |
| Dart 包名 | `kaijuan` |
| 入口 | `lib/main.dart` |
| 格式 | CBZ / ZIP / EPUB（按内容自动路由） |
| 状态 | 漫画页图闭环 + 图书 reflow |

## 文档

- [docs/README.md](docs/README.md) — 文档索引  
- [docs/PRODUCT.md](docs/PRODUCT.md) — 产品功能  
- [docs/ENGINEERING.md](docs/ENGINEERING.md) — 工程结构  

## 运行

```sh
flutter pub get
flutter run -d macos
# 或
flutter run -d <device>
```

详见 [docs/ENGINEERING.md](docs/ENGINEERING.md) §5。
