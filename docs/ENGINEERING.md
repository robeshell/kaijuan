# 工程结构：单 App 双引擎

产品决策见 [PRODUCT.md](./PRODUCT.md)。

**目标**：一个 git 仓库，打出一个 **Kaika** 本地阅读 App；内部同时包含漫画页图引擎与图书 reflow 引擎。

当前仓库已切换到 **单 App 入口**；Android 已移除 product flavor，Apple 端旧 scheme 继续逐步收口。

---

## 1. 目标形态（推荐）

```text
KaikaNext/                          # 仓库名
  docs/                             # 产品与设计
  lib/                              # 单 App 代码
    main.dart                       # 唯一入口
    main_comic.dart / main_book.dart # 兼容重定向到 main
    brand/brand_config.dart         # 单 App 配置
    library/import/                 # 格式判定、内容寻址、元数据、DB 提交
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
  applicationId: com.kaika.reader
  accent presets + default accent
  default reading theme
  import extension whitelist: cbz, zip, epub
  databaseName: app_library        # 沿用已有数据
  storageNamespace: ''             # support root
```

入口：

```text
lib/main.dart → runApp(App(brand: BrandConfig.app))
```

---

## 2. 过渡形态（当前）

- `lib/main.dart` 是唯一入口。
- `lib/main_comic.dart` / `lib/main_book.dart` 重定向到 `bootstrap()`，仅兼容旧 `-t` 入口；Android 不再接受 `--flavor comic/book`。
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

禁止：core 依赖某个品牌文案；image 引擎包 import book 引擎（仅 import service / router 可桥接）。

### 图书排版实现

- EPUB 正文采用 Anx Reader 维护的 MIT `foliate-js` 内核，经 `flutter_inappwebview` 承载；保留其 Paginator 的章节按需挂载、手势方向锁定、跟手滚动、200–300ms 吸附动画和 ResizeObserver 重排，不再维护 Kaika 自有分页器。
- 禁止在 Dart UI isolate 上用 `TextPainter` 预分页整章、邻章或整本。系统 WebView 的 HTML/CSS columns 负责 reflow，Dart 只维护 locator、偏好和 chrome。
- EPUB 与 `foliate-js` 静态资源由只绑定 `127.0.0.1` 的 **App 级共享** loopback server 流式提供；端口尽量复用并持久化，稳定 WebView origin 以便二次打开命中静态资源缓存。各阅读/导入 session 只挂载自己的 `/books/<id>.epub`，关闭时卸挂，不销毁共享 listener。前端按 Anx Reader 的 `fetch → File → zip.js BlobReader` 链路打开，禁止 Dart `readAsBytes` 后展开成 JavaScript 整数数组。
- WebView 实例在普通尺寸变化时保持存活，由 foliate Paginator 的 ResizeObserver 以当前 anchor/CFI 重排。尺寸/生命周期切换开始时先冻结最后一个稳定 CFI，并忽略离屏或零尺寸阶段的 relocation。部分 Android 折叠屏切换物理显示器时系统会主动终止 WebView renderer；adapter 必须移除失效 WebView，并在 resumed 后用冻结的 CFI 重建，不能继续调用已死亡的 renderer。
- 首次打开只能由 `View.init(lastLocation)` 发起一次定位；空 CFI 不得额外并发调用 `renderer.next()`，否则 Android WebView 会同时创建两个章节 iframe，形成 ResizeObserver/分页重排竞争。
- 引入或修改的 BSD / MIT / Apache 源码与依赖必须保留许可证声明；应用业务层继续自有，开源 renderer 通过 adapter 接入 controller。

完整的 Anx 导入、打开、阅读和 App 分层对照见 [research/foliate-architecture.md](./research/foliate-architecture.md)。核心取舍是复用 Foliate 的格式/rendition 语义，不复制 Anx 的 UI、DAO 直连或全局 service 组织。

### 图书全链路边界

| 边界 | 职责 | 禁止 |
|---|---|---|
| `EpubImportRouter` | 有界抽样，判定 book/comic | 整本 `readAsBytes()`、写 DB、弹 UI |
| `BookImportService` | hash、内容落盘、metadata、事务提交 | 构建阅读 WebView、持有 screen context |
| `BookReaderController` | locator、书签、偏好、chrome、持久化 | 解析 EPUB、操作 DOM、直写 renderer 状态 |
| `FoliateJsBookEngineAdapter` | controller 与 typed Foliate event 的适配 | 直连 drift、承载书库业务 |
| `BookLoopbackServer` | App 级 loopback、固定 origin、白名单资源与按 id 挂载书籍 | 接受客户端绝对路径、离开阅读器即杀 listener |
| `BookRenditionSession` | 单书 mount、WebView generation lease、阶段耗时 | UI 状态、书签和偏好、独占销毁共享 server |
| `foliate-js` | EPUB 解析、TOC、CFI、reflow、输入 | 认识 Kaika 数据表和导航层 |

导入与阅读统一使用 Foliate：导入阶段按 Anx Reader 的不可见 WebView 思路，通过 metadata-only 页面直接调用同一份 `foliate-js` EPUB package parser，读取 metadata、封面、spine 与有界正文样本，但不创建 `foliate-view` / Paginator；阅读阶段再由可见 rendition 打开。`epub_pro` 与旧 `BookEpub` 适配层删除，避免两套 EPUB 解析结果和兼容性边界不一致。导入 probe 必须有超时、错误回传和无条件 dispose，且不得进入阅读 controller。book/comic 判定必须基于 spine 抽样语义：只有绝大多数抽样章节同时“低文字且含页图”才路由漫画；封面或零散插图不得把正文 EPUB 判成漫画。

### 导入提交协议

```text
source
  → 单次流式复制到 .import-staging，同时计算 SHA-256
  → 在 staging 文件上完成 kind/metadata/page list/cover
  → 内容与封面按 hash 原子 rename 到 library/covers
  → AppDatabase upsert
  → 任一步失败：删除 staging，并补偿删除本事务新建的 target
```

- staging、`library` 与 `covers` 必须位于同一个 support root，确保 rename 不跨文件系统。
- rollback 只能删除当前事务实际创建的 target；同 hash 的既有文件不得删除。
- 正式目录在解析完成前不可见半成品。文件提交后若 DB 写入失败，执行补偿回滚。
- debug timing 分为 `foliate-probe`、`book`、`comic` 三条管线；至少标记 validated、content-staged、metadata/page-list、cover-staged、files-committed、database-committed 或 rolled-back。
- 导入与打开 timing 同时写入进程内 `PipelineDiagnostics`；设置 → 关于可复制导出，不只依赖 debug console。
- 启动时对 `.import-staging/*.partial` 做年龄门限清扫（默认 24h），只删确认过期且非活跃事务的残留。

---

## 4. 数据沿用

| 项 | 策略 |
|----|------|
| DB 文件名 | `app_library`（沿用已有） |
| 内容文件目录 | `…/library` + `…/covers`（support root） |
| 偏好 JSON | `comic_reading.json` / `book_reading.json` / `theme.json` |
| 旧 `book_library` | 不自动合并；需要可重导 EPUB |

---

## 5. 构建与运行

### 5.1 日常开发

```sh
flutter pub get
flutter run -d macos
flutter run -d <android-device>

# 旧脚本兼容（brand 参数被忽略）
tool/run_brand.sh comic
tool/run_brand.sh book macos

# 等价
flutter run -t lib/main.dart
```

macOS 日常开发不再强制 `--flavor comic`。若 Xcode scheme 仍绑定 flavor，可先用 `comic` scheme（显示名已改为 Kaika）；`book` scheme 标 deprecated。

### 5.2 验证

```sh
dart run build_runner build --delete-conflicting-outputs   # drift 生成（改表结构后必跑）
flutter analyze
flutter test
flutter build apk --debug
```

CI（`.github/workflows/ci.yml`）在 `main` push / PR 上跑 analyze + test，并缓存 drift 生成。

### 5.3 原生 flavor 收口

- Android：**无 productFlavor**；普通 `flutter run` / `assembleDebug` 直接构建；namespace 与 applicationId 均为 `com.kaika.reader`，应用名 Kaika。
- iOS/macOS：保留 `comic` scheme；`book` scheme 标 deprecated；App 显示名 Kaika。
- 图标：`brands/icons/comic/master_1024.png` 继续作为 Kaika 图标源；`book` 目录可归档。

后续清理：删除 Apple 端 `book` scheme/xcconfig/icon set，以及 Android 已失效的旧 flavor 图标目录。

### 5.4 图标

```sh
python3 tool/generate_brand_icons.py
```

当前源图：`brands/icons/comic/master_1024.png`（Kaika 图标）。

### 5.5 发布打包

**不要**直接 `flutter build … --release` 发版。版本以 `pubspec.yaml` 为唯一来源：`MAJOR.MINOR.PATCH` 对用户可见；`+build` 为内部 build number。

```sh
# 预览下一版本（不改文件）
dart run tool/release.dart --dry-run

# bump patch 一次，构建所选平台，产物写入 dist/
dart run tool/release.dart android
dart run tool/release.dart android macos
dart run tool/release.dart windows

# 不 bump，用当前版本重打
dart run tool/release.dart android --no-bump

# 已有 drift 生成物时可跳过 codegen
dart run tool/release.dart android --no-bump --skip-codegen
```

| 平台 | 产物（`dist/`） | 宿主要求 |
|------|-----------------|----------|
| android | `kaika-x.y.z-android.apk`、`.aab` | 任意 |
| ios | `kaika-x.y.z-ios-unsigned.zip` | macOS |
| macos | `kaika-x.y.z-macos.zip`（`Kaika.app`） | macOS |
| windows | `kaika-x.y.z-windows.zip`；可选 `.msix`、`-setup.exe` | Windows |

Windows 安装包细节见 [`packaging/windows/README.md`](../packaging/windows/README.md)。MSIX 依赖 `msix` dev 包与 `msix_config`（`pubspec.yaml`）；Setup.exe 需 [Inno Setup 6](https://jrsoftware.org/isinfo.php)。

**GitHub Release**：推送 `vMAJOR.MINOR.PATCH` tag 触发 `.github/workflows/release.yml`，为 Android / iOS / macOS / Windows 打 unsigned 包并上传 Release（不含 MSIX / Inno，那些仅本地 `release.dart windows` 产出）。

**签名（本地/商店，未接入 CI）**

| 平台 | 模板 / 位置 |
|------|-------------|
| Android | `android/key.properties.example` → 复制为 `key.properties` + upload keystore；当前 `build.gradle.kts` release 仍用 debug 签名 |
| Apple | Xcode 开发/分发证书；CI 产物为 `--no-codesign` |
| Windows MSIX | `msix_config` 测试证书 sideload；商店需 Partner Center 身份 |

bump 失败时 `release.dart` 会回滚 `pubspec.yaml`。

---

## 6. 迁移步骤（已完成）

1. **文档** — PRODUCT / ENGINEERING 改为单 App ✅
2. **BrandConfig + 单 main** ✅
3. **偏好 / DB 沿用已有布局** ✅
4. **双 import service + EpubImportRouter** ✅
5. **LibraryController 类型筛选 + 混排** ✅
6. **UI 打开路径 / 设置 / 文案** ✅
7. **Apple 原生 scheme 收口** — P2 可选

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
| `readers/book/*` | 图书 reflow：导入探测与阅读渲染统一使用 Anx Reader foliate-js + 系统 WebView |

**图书引擎**：业务管线、locator 和输入适配保留 Kaika controller 边界；排版、分页和触摸交互复用 Anx Reader 的 foliate-js + 平台 WebView。

**图书平台能力**：`BookReaderCapabilities` 是模式入口的单一判定；iOS / iPadOS / Android 开放滚动与翻页，macOS / Windows（以及非目标 Linux 桌面）仅开放翻页。controller 必须再次约束模式，不能只依赖设置 UI 隐藏。

**阅读偏好入口**：漫画与图书偏好继续由各自 preferences 持久化，但只允许在对应阅读器内修改；App「设置」页不承载阅读模式、方向、字号、版心或阅读背景。

**图书 CSS 管线**：foliate-js 在 WebView 中按 EPUB 原始路径加载章节 CSS、图片与嵌入字体；Kaika 通过 Anx style bridge 注入阅读基线（微信读书式黑体栈、宽版心侧边距、上下 meta 留白、`textIndent=2`、主题正文/链接/标题色、规格化标题倍率）。页眉章节 / 页脚全书页码由 Flutter `BookPageMetaOverlay` 叠在 Foliate 边距带上。正文字体三源：`book` / 系统 CSS 栈 / 用户字体（`support/fonts` + loopback `/fonts/<id>` → `fontPath`）。空 `fontPath` 不写 `@font-face`。旧 `FlutterHtmlBookEngineAdapter` / Dart paginator / Dart pageMap 已删除，仓库只保留一条阅读渲染链。

---

## 8. 非目标（工程）

- 强制上 Firebase 多项目
- 两 App 共用 App Group（已合并为一个 App）
- 一次 PR 完成 monorepo 全拆

细节实现以迭代 PR 为准；**结构争议以本文 + PRODUCT 为准**。
