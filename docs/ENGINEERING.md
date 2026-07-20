# 工程结构：单 App 双引擎

产品决策见 [PRODUCT.md](./PRODUCT.md)。

**目标**：一个 git 仓库，打出一个 **Kaika** 本地阅读 App；内部同时包含漫画页图引擎与图书 reflow 引擎。

当前仓库已切换到 **单 App 入口**；原 comic/book 双 flavor 正在最小化收口。

---

## 1. 目标形态（推荐）

```text
KaikaNext/                          # 仓库名
  docs/                             # 产品与设计
  lib/                              # 单 App 代码
    main.dart                       # 唯一入口
    main_comic.dart / main_book.dart # 兼容重定向到 main
    brand/brand_config.dart         # 单 App 配置
    library/import/                 # ComicImportService + BookImportService + EpubImportRouter
    readers/comic/                  # 页图引擎
    readers/book/                   # reflow 引擎
    presentation/                   # UI / controllers
  android/ ios/ macos/ windows/ linux/
  tool/                             # 构建与辅助脚本
```

### 品牌配置

```text
BrandConfig
  displayName: Kaika
  applicationId: com.kaika.comic   # 暂留兼容
  accent presets + default accent
  default reading theme
  import extension whitelist: cbz, zip, epub
  databaseName: app_library        # 沿用 comic 数据
  storageNamespace: ''             # support root
```

入口：

```text
lib/main.dart → runApp(App(brand: BrandConfig.app))
```

---

## 2. 过渡形态（当前）

- `lib/main.dart` 是唯一入口。
- `lib/main_comic.dart` / `lib/main_book.dart` 重定向到 `bootstrap()`，保证旧 `--flavor` / `-t` 调用仍能编译运行同一 App。
- `BrandConfig.app` 单例；`AppBrand` enum 已移除。
- 数据沿用 `app_library` + support root，**不**迁移旧 `book_library`。

---

## 3. 共享与边界

| 放入 core/lib | 漫画引擎 | 图书引擎 |
|---|---|---|
| ReaderKind/Format、locator 约定 | ComicSession、四模式 | Reflow 引擎、目录 |
| AppDatabase 表结构 | 页图缓存 | 分页/排版 |
| 进度 / 书签 API 形状 | 漫画 chrome 附加控件 | 字号面板 |
| 间距圆角色板 | | |
| 书架/书库通用 widgets | | |
| EpubImportRouter | | |

禁止：core 依赖某个品牌文案；comic 包 import book 引擎（仅 import service / router 可桥接）。

---

## 4. 数据沿用

| 项 | 策略 |
|----|------|
| DB 文件名 | `app_library`（沿用 comic） |
| 内容文件目录 | `…/library` + `…/covers`（support root） |
| 偏好 JSON | `comic_reading.json` / `book_reading.json` / `theme.json` |
| 旧 `book_library` | 不自动合并；需要可重导 EPUB |

---

## 5. 构建与运行

### 5.1 当前（单入口）

```sh
# 推荐
flutter run -d macos

# 旧脚本兼容（brand 参数被忽略）
tool/run_brand.sh comic
tool/run_brand.sh book macos

# 等价
flutter run -t lib/main.dart
```

macOS 日常开发不再强制 `--flavor comic`。若 Xcode scheme 仍绑定 flavor，可先用 `comic` scheme（显示名已改为 Kaika）；`book` scheme 标 deprecated。

### 5.2 原生 flavor 最小收口（P2）

- Android：保留 `comic` productFlavor；`book` flavor 标 deprecated 或后续移除；applicationId 统一 `com.kaika.comic`；应用名 Kaika。
- iOS/macOS：保留 `comic` scheme；`book` scheme 标 deprecated；App 显示名 Kaika。
- 图标：`brands/icons/comic/master_1024.png` 继续作为 Kaika 图标源；`book` 目录可归档。

完整收口（第二刀）：删除 `book` flavor/scheme/xcconfig/icon set。

### 5.3 图标

```sh
python3 tool/generate_brand_icons.py
```

当前源图：`brands/icons/comic/master_1024.png`（Kaika 图标）。

---

## 6. 迁移步骤（已完成）

1. **文档** — PRODUCT / ENGINEERING 改为单 App ✅
2. **BrandConfig + 单 main** ✅
3. **偏好 / DB 沿用 comic 布局** ✅
4. **双 import service + EpubImportRouter** ✅
5. **LibraryController 类型筛选 + 混排** ✅
6. **UI 打开路径 / 设置 / 文案** ✅
7. **原生 flavor 最小收口** — P2 可选

---

## 7. 与当前代码映射

| 现在 | 说明 |
|------|------|
| `lib/main.dart` | 唯一入口 |
| `BrandConfig.app` | 单 App 配置 |
| `EpubImportRouter` | EPUB 自动探测与路由 |
| `LibraryController` | 双 service + `LibraryKindFilter` |
| `AppDatabase.watchLibraryEntries([kind])` | 可选 kind 查询 |
| `readers/comic/*` | 漫画页图引擎 |
| `readers/book/*` | 图书 reflow 引擎 |

---

## 8. 非目标（工程）

- 强制上 Firebase 多项目
- 两 App 共用 App Group（已合并为一个 App）
- 一次 PR 完成 monorepo 全拆

细节实现以迭代 PR 为准；**结构争议以本文 + PRODUCT 为准**。
