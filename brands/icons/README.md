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

- `android/app/src/comic|book/res/mipmap-*/ic_launcher.png`  
- `ios/Runner/Assets.xcassets/AppIcon-comic|book.appiconset/`  
- `macos/Runner/Assets.xcassets/AppIcon-comic|book.appiconset/`  
- 默认 `AppIcon.appiconset` ← 同步为 comic（无 flavor 时）

## 当前占位

仓库里已有**临时色块+字母**占位（C / B），仅供区分 flavor，**不是最终品牌**。你的 master 覆盖后重跑脚本即可。

## 验收

```sh
flutter build macos --debug --flavor comic -t lib/main_comic.dart
flutter build macos --debug --flavor book -t lib/main_book.dart
# Dock / Finder 应看到两套不同图标（占位或你的图）
```
