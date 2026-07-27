# 分品牌 App 图标

你做两份设计图时，**各交一张 1024×1024 PNG master** 即可，其余尺寸用脚本生成。

## 你交什么

| 品牌 | 放到 |
|------|------|
| 漫画 | `brands/icons/comic/master_1024.png` |
| 图书 | `brands/icons/book/master_1024.png` |

要求：

- **1024 × 1024**，PNG，sRGB  
- 填满画布（系统会加圆角 / mask，**不要**自己做 iOS 圆角）  
- 可带透明；Android 自适应图标目前用整图作 `ic_launcher`（后续可再拆前景）  
- 两品牌识别要拉开（色 / 符号），壳可同源气质  

可选附加（以后）：

- `master_1024_dark.png` — macOS / 通知用深色变体  
- 前景层 `foreground_1024.png`（Android adaptive）

## 生成到工程

```sh
# 覆盖 master 后：
python3 tool/generate_brand_icons.py
```

会写入：

- **`android/app/src/main/res/mipmap-*/ic_launcher.png`**（单 App 真正安装用的图标，默认 comic）
- `android/app/src/comic|book/res/mipmap-*`（遗留目录，一并同步）
- `ios` / `macos` `AppIcon-comic|book` + 默认 `AppIcon.appiconset`（← comic）
- `windows/runner/resources/app_icon.ico`
- 启动页资源（`tool/generate_launch_assets.py`）

## 当前 master（2026-07）

用户交付的 Icon Composer 稿（打开的书 · 扁平乳白对开页），整理后写入：

| flavor | 底色 | master |
|--------|------|--------|
| comic（默认） | 暖橙 `#EA580C` 系 | `comic/master_1024.png` |
| book | 岩灰 `#475569` 系（同符号换底） | `book/master_1024.png` |

Icon Composer 包：`brands/icons/Kaijuan.icon/`（fill 珊瑚橙，foreground 为 comic master）。

替换 master 后重跑 `python3 tool/generate_brand_icons.py`。

## 验收

```sh
flutter build macos --debug --flavor comic -t lib/main_comic.dart
flutter build macos --debug --flavor book -t lib/main_book.dart
# Dock / Finder 应看到两套不同图标（占位或你的图）
```
