# 开卷 App 图标

开卷已经收口为一个 App、一个品牌图标。可编辑母版是
`brands/icons/kaijuan_master-v2.svg`；平台生成链路继续读取 1024×1024 PNG。

## 母版

| 文件 | 用途 |
|------|------|
| `kaijuan_master-v2.svg` | 可编辑矢量母版 |
| `comic/master_1024.png` | 正式单 App 的平台生成源 |
| `book/master_1024.png` | 旧 book scheme 的同图镜像 |

要求：

- **1024 × 1024**，PNG，sRGB  
- 填满画布（系统会加圆角 / mask，**不要**自己做 iOS 圆角）  
- 两个兼容 PNG 必须完全相同，避免旧 scheme 显示另一套产品身份
- Android 目前用整图作 `ic_launcher`

## 生成到工程

```sh
# 从 SVG 导出并覆盖两个兼容 PNG 后：
python3 tool/generate_brand_icons.py
```

会写入：

- **`android/app/src/main/res/mipmap-*/ic_launcher.png`**（单 App 真正安装用的图标）
- `android/app/src/comic|book/res/mipmap-*`（遗留目录，一并同步）
- `ios` / `macos` `AppIcon-comic|book` + 默认 `AppIcon.appiconset`
- `windows/runner/resources/app_icon.ico`
- `brands/icons/Kaijuan.icon/Assets/foreground.png`
- 启动页资源（`tool/generate_launch_assets.py`）

## 当前母版（2026-07）

v2 沿用开听的品牌语言：珊瑚红到橙色的对角渐变背景，搭配乳白色、
严格左右对称的抽象打开书页。图形为单一复合轮廓，无细线与内部装饰。

颜色：`#F14F4B → #F76334`，标记：`#FFF7E8`。

## 验收

```sh
flutter build macos --debug
# 可选：旧 scheme 应显示与正式 App 相同的图标
flutter build macos --debug --flavor comic -t lib/main_comic.dart
flutter build macos --debug --flavor book -t lib/main_book.dart
```
