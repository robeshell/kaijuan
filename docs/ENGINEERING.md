# 工程结构：双 App 一套底座

产品决策见 [PRODUCT.md](./PRODUCT.md)。  
**目标**：一个 git 仓库，打出 **两个品牌 App**；代码共享 core，壳与引擎可分。

当前仓库仍是 **单 app 可运行（漫画闭环）**。本文描述 **目标骨架** 与迁移步骤；落地时按阶段改，避免一次拆爆。

---

## 1. 目标形态（推荐）

```text
KaikaNext/                          # 仓库名可仍叫 KaikaNext
  docs/                             # 产品与设计（已有）
  packages/
    kaika_core/                     # 共享：domain、db 范式、import 基础、theme tokens、通用 widgets
    kaika_comic_reader/             # 漫画引擎 + comic 专用 UI
    kaika_book_reader/              # 图书 reflow 引擎（后建）
  apps/
    comic/                          # 漫画品牌壳：main、图标、flavor 配置、BrandConfig
    book/                           # 图书品牌壳
  melos.yaml / pubspec workspace    # 可选，阶段 1b+
```

### 品牌配置（每 App 一份）

```text
BrandConfig
  id: comic | book
  displayName
  applicationId / bundleId
  accent presets + default accent
  default reading theme
  import extension whitelist
  supportDirectoryName / databaseName   # 数据隔离
  feature flags
```

入口：

```text
apps/comic/lib/main.dart → runApp(App(brand: BrandConfig.comic))
apps/book/lib/main.dart  → runApp(App(brand: BrandConfig.book))
```

---

## 2. 过渡形态（阶段 1b，改动小）

在 **尚未拆 packages** 时可用：

```text
lib/
  main.dart                 # 开发默认 → comic（保持现状）
  main_comic.dart           # 显式 comic 入口
  main_book.dart            # book 占位壳（可先 NotImplemented / 空书库）
  brand/
    app_brand.dart          # enum + BrandConfig
  ...现有 library / readers / presentation
```

Android / iOS / macOS：**product flavors / schemes**  
- `comic` → `main_comic.dart`  
- `book` → `main_book.dart`  

数据：

```text
getApplicationSupportDirectory()
  /comic_app/...    # 或不同 drift name: comic_library
  /book_app/...
```

**原则**：book 未就绪时，book 入口可以编译，但导入/打开给出「即将支持」，不要链半残引擎冒充完成。

---

## 3. 共享与边界

| 放入 core | 留在 comic app/engine | 留在 book app/engine |
|-----------|------------------------|----------------------|
| ReaderKind/Format、locator 约定 | ComicSession、四模式 | Reflow 引擎、目录 |
| AppDatabase 表结构模式 | 页图缓存 | 分页/排版 |
| 进度 / 书签 API 形状 | 漫画 chrome 附加控件 | 字号面板 |
| 间距圆角色板 | 品牌资源（图标） | 品牌资源 |
| 书架/书库通用 widgets（无文案写死品类） | | |

禁止：core 依赖某个品牌文案；comic 包 import book 引擎。

---

## 4. 数据隔离

| 项 | 策略 |
|----|------|
| DB 文件名 | `comic_library` / `book_library`（示例） |
| 内容文件目录 | `…/comic/library` vs `…/book/library` |
| 偏好 JSON | `comic_theme.json` / `book_theme.json` 等 |
| 备份迁移跨 App | **不做**（产品非目标） |

---

## 5. 构建与运行

### 5.1 当前（已配 flavor）

| 品牌 | applicationId / bundle | Dart 入口 |
|------|------------------------|-----------|
| comic | `com.kaika.comic` | `lib/main_comic.dart` |
| book | `com.kaika.book` | `lib/main_book.dart` |

```sh
# 推荐
tool/run_brand.sh comic
tool/run_brand.sh book macos

# 等价
flutter run --flavor comic -t lib/main_comic.dart
flutter run --flavor book -t lib/main_book.dart -d macos

# 打包
flutter build macos --flavor comic -t lib/main_comic.dart
flutter build macos --flavor book -t lib/main_book.dart
flutter build apk --flavor comic -t lib/main_comic.dart
flutter build apk --flavor book -t lib/main_book.dart
flutter build ios --flavor comic -t lib/main_comic.dart   # 需签名
```

- **Android**：`productFlavors` comic/book（需本机 JDK 才能 gradle）。  
- **iOS / macOS**：`Debug|Release|Profile-{comic,book}` + scheme `comic` / `book`（由 `tool/apply_xcode_flavors.py` 生成，可重跑）。  
- **默认** `flutter run` / `lib/main.dart` → 仍走 comic 逻辑；带 `--flavor` 时请始终同时传 `-t`。

### 5.3 分品牌图标

| 你交的图 | 生成命令 |
|----------|----------|
| `brands/icons/comic/master_1024.png` | `python3 tool/generate_brand_icons.py` |
| `brands/icons/book/master_1024.png` | 同上 |

说明与尺寸：`brands/icons/README.md`。  
Android 用 `src/comic|book/res/mipmap-*`；Apple 用 `AppIcon-comic` / `AppIcon-book` asset catalog（flavor 配置已指向）。

### 5.2 monorepo 期（未拆）

```sh
# 将来
flutter run -t apps/comic/lib/main.dart
flutter run -t apps/book/lib/main.dart
```

CI：两个 artifact、两套签名配置。

---

## 6. 迁移步骤（建议）

1. **文档** — PRODUCT / ENGINEERING 双 App ✅  
2. **BrandConfig + 双 main** ✅  
3. **偏好 / DB 按 brand 隔离** ✅（comic 沿用根目录 + `app_library`）  
4. **原生 flavor / 双 bundle** ✅（Android + iOS/macOS 配置；图标仍共用占位）  
5. **分品牌图标** — 槽位 + 生成脚本已就绪；设计 master 见 `brands/icons/README.md`  
6. **抽出 packages/kaika_core** — 有 book 代码压力时再拆  
7. **book 引擎 spike → 可导入 EPUB**  

---

## 7. 与当前代码映射

| 现在 | 将来 |
|------|------|
| `lib/main.dart` | comic 默认入口 |
| `readers/comic/*` | `kaika_comic_reader` 或保留 path |
| `ComicReadingPreferences` | 每 brand 一份 / 泛化 ReadingPreferences |
| `watchComics()` | comic app 内 `watchLibrary()`；book 侧 watch books |
| 单一 `AppShell` | 共享 Shell，BrandConfig 注入标题与空态 |

---

## 8. 非目标（工程）

- 强制上 Firebase 多项目（除非以后要推送）  
- 两 App 共用 App Group 同步进度（产品未要求）  
- 一次 PR 完成 monorepo 全拆  

细节实现以迭代 PR 为准；**结构争议以本文 + PRODUCT 为准**。
