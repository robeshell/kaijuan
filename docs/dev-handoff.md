# Dev Handoff

> 更新时间：2026-07-22。本文是当前工作树交接，不是产品权威。功能看 [PRODUCT.md](./PRODUCT.md)，工程边界看 [ENGINEERING.md](./ENGINEERING.md)，Anx/Foliate 调研看 [research/foliate-architecture.md](./research/foliate-architecture.md)。

## 0. 当前结论

KaikaNext 图书 reflow 主链已切到 Anx Reader 的 `foliate-js + flutter_inappwebview`。选区两段式菜单 + 划线/高亮/笔记已可用（写改存 note；目录抽屉「目录|书签|笔记」）；规范见 [book-reader.md](./specs/book-reader.md)。默认下一功能刀仍为 ③ 书内搜索。

## 1. 本轮已完成的改造

### App 与产品入口

- 单 App、单入口 `lib/main.dart`、单数据库 `app_library`、漫画/图书双引擎按 `ReadingItem.kind` 路由。
- Android product flavor 已移除，普通 `flutter run` / `assembleDebug` 可构建；applicationId/namespace 收口到 `com.kaika.reader`。
- App 设置页中的阅读设置已移除；漫画和图书设置只保留在各自阅读器内。
- 桌面图书阅读器只开放翻页模式，移动端保留翻页/滚动；能力判断集中在 `BookReaderCapabilities`，controller 也做二次约束。
- 书库窄屏批量选择栏改为菜单，修掉 Android `RenderFlex overflow` 黄黑条。

### 图书阅读主链

- 引入 Anx Reader 基线 commit `107f4fa74db0e7247c846c49d6211df3edf9887c` 的 Foliate 资源，保留许可证和来源说明：`assets/book/`。
- 新链路：`BookReaderScreen → BookReaderController → FoliateJsBookEngineAdapter → BookRenditionSession → foliate-js`。
- `BookRenditionSession` 只绑定 `127.0.0.1`，以固定 `/book.epub` 和白名单 `/foliate-js/*` 路由提供书籍/资源；带 WebView generation lease，旧 renderer 的迟到回调无效。
- typed bridge 已覆盖 metadata、publication/TOC、relocation、viewport click；位置以 CFI 为主并经 controller 持久化。
- 折叠屏/尺寸变化开始时冻结稳定 CFI；普通 resize 保活 WebView，renderer process gone 时再重建。
- 修过一个 Android 新书打开卡死：空 CFI 时 Anx `book.js` 原先并发执行 `renderer.next()` 和 `view.init()` 的 fallback `next()`，会竞争创建两个 iframe。现在首次定位只由 `view.init()` 发起，并增加 `FoliateReader init-start/init-ready` 日志。
- 滚动模式跨章卡顿：`paginator.js` 在接近 spine 边界时预加载相邻节，且新节 iframe 加载完成后再替换旧节；滚动模式跨节不再额外 `wait(100)`。Anx 上游同样注释掉了自动 `#handleScrollBoundaries` 换节，跨节仍靠节末手势 + `nextPage`/`prevPage`。
- 删除旧 Dart 渲染链：`BookEpub`、`epub_pro`、`flutter_html` adapter、HTML preprocess/CSS 子集、TextPainter paginator、paged/scroll view 及对应测试。

### 导入与存储

- book/comic 导入统一采用 `.import-staging`：流式复制同时 SHA-256，解析完成后原子提交内容/封面，再写 DB；失败会补偿回滚。
- `BookImportService`、`ComicImportService` 和 `EpubImportRouter` 都有阶段 timing。
- 新增 metadata-only Foliate 页面 `metadata-probe.html` / `src/metadata-probe.js`，设计目标是不创建 `foliate-view/Paginator`，只读取 metadata、cover、spine 和最多 12 个章节样本。
- book/comic 预期规则已经改成：只有至少 80% 抽样 spine 都是“低文字且含图片”的章节才判漫画；封面和零散插图不能让正文 EPUB 变成漫画。
- 该规则的纯 Dart 单测已覆盖，但真实 Android probe 目前在生成 snapshot 之前失败，见下一节。

### 书签与 UI

- 漫画/图书共用书签存储契约，阅读器内已有添加、删除、列表与跳转 UI。
- 图书 chrome、设置面板、主题与 locator/controller 已按 Foliate rendition 调整。

## 2. 已修复 P0：正文 EPUB 被识别为漫画

### 原真机复现（修复前）

设备：V2545A，Android 16，Android WebView/Chrome 150。

文件：`以日为鉴 衰退时代生存指南 ... .epub`，约 2.96 MB。关键日志：

```text
FoliateMetadataProbe fetch-ready 2955622
FoliateMetadataProbe failed TypeError:
Cannot read properties of null (reading 'allowScript')

book sections=0 sampled=0 imageOnly=0 totalText=0 avgText=0
images=19
EpubImportRouter → comic
```

`favicon.ico` 的 404 不是根因，可以忽略。

### 已定位根因

1. `FoliateJsImportProbe` 构造的 URL 目前只有 `url` 参数：

   ```dart
   session.probeUri.replace(
     queryParameters: {'url': jsonEncode(session.bookUri.toString())},
   )
   ```

2. `metadata-probe.js` 直接执行 `new EPUB(zip.loader).init()`。
3. `EPUB.init()` 内部创建 `Loader`；Anx fork 的 `epub.js` 中 `Loader` 仍隐式读取阅读页全局 URL 参数：

   ```js
   this.allowScript = JSON.parse(urlParams.get('style')).allowScript
   ```

4. metadata probe URL 没有 `style`，所以 `JSON.parse(null)` 得到 `null`，读取 `null.allowScript` 抛错。
5. `EpubImportRouter._detectKind()` 捕获 probe error 后仍继续 `ComicArchive.listPagesDetailed()`。普通正文 EPUB 有封面/插图（本例 19 张），`sectionCount=0 + imageCount>0` 最终回退为 comic。

因此错误不在 80% 判定阈值，而在 **metadata-only 页面没有满足 Anx EPUB loader 的启动契约，且 router 把“probe 失败”错误降级成了“漫画证据”**。

### 修复（2026-07-22）

1. `FoliateJsImportProbe.buildProbeUri()` 为 metadata 页传入 `style={"allowScript":false}`，与阅读页 Loader 契约一致。
2. `epub.js` Loader 在缺少 `style` 参数时默认 `allowScript=false`，不再对 `null.allowScript` 抛错。
3. `EpubImportRouter.classifyMetrics()` 删除 `sectionCount==0 && imageCount>0 → comic` 回退；probe 失败改为 `ImportException`，只有 spine 抽样 ≥80% 页图才路由 comic。

真机回归命令见 §7；可用 `tool/verify_foliate_probe.dart` 在设备上验证指定 EPUB 的 probe + router。

## 3. 下一位开发者建议按这个顺序处理

1. ~~先修 metadata probe 启动契约~~ ✅
2. ~~给 router 加失败保护~~ ✅
3. ~~增加真实 metadata 页面集成验证~~ ✅（`test/foliate_import_probe_test.dart` + `tool/verify_foliate_probe.dart`）
4. ~~Android 重测上述文件（`以日为鉴` EPUB）~~ ✅（已人工验证 → book）
5. ~~comic → book 同 hash 重导~~ ✅
6. ~~导入后打开回归（翻页 / 恢复 / 折叠）~~ ✅
7. ~~工程卫生：可导出 timing + 启动清扫超时 `.partial`~~ ✅
8. ~~书内链接（Foliate）+ 外链系统打开~~ ✅；选区/标注仍按需
9. 修改 `assets/book/foliate-js/src/book.js` 后执行：

   ```sh
   cd assets/book/foliate-js
   npm run build
   ```

   以同步 `dist/bundle.js` 兼容构建。metadata-only 页面目前直接加载 ES module `src/metadata-probe.js`。

## 4. 关键文件导航

| 领域 | 文件 |
|---|---|
| probe 生命周期 | `lib/readers/book/foliate_import_probe.dart` |
| probe 页面 | `assets/book/foliate-js/metadata-probe.html` |
| probe 解析/抽样 | `assets/book/foliate-js/src/metadata-probe.js` |
| 隐式 allowScript 来源 | `assets/book/foliate-js/src/epub.js`，`Loader` constructor |
| kind 路由 | `lib/library/import/epub_import_router.dart` |
| snapshot bridge | `lib/readers/book/foliate_js_bridge.dart` |
| book 导入 | `lib/library/import/book_import_service.dart` |
| comic EPUB 页图扫描 | `lib/library/import/comic_archive.dart` |
| 原子 staging | `lib/library/import/import_staging.dart` |
| 阅读 adapter | `lib/readers/book/foliate_js_engine_adapter.dart` |
| loopback/session | `lib/readers/book/book_rendition_session.dart` |
| Foliate 阅读入口 | `assets/book/foliate-js/src/book.js` |
| 架构研究 | `docs/research/foliate-architecture.md` |

## 5. 当前验证基线

在发现上述真机 probe 阻塞前，最近一次本地结果：

```text
flutter analyze                 No issues found
flutter test                    100 tests passed
flutter build apk --debug       success
```

这些测试没有覆盖 Android HeadlessInAppWebView 中 metadata 页对 `epub.js Loader` 的真实初始化，所以不能证明导入链可用。Webpack 构建成功，有 3 条既有 top-level-await target warning。

## 6. 工作树注意事项

- 工作树包含本轮全部改造和用户原有改动，规模很大，尚未提交；**不要 reset、checkout 或批量回滚**。
- `assets/`、`third_party/`、多个 Foliate/Dart 新文件目前是 untracked，交接时必须纳入范围。
- Apple Podfile/lock、Xcode workspace、平台 plugin registrant 等也是本轮 WebView 接入产生的改动，不要只提交 `lib/`。
- 旧 Dart 阅读器文件和旧测试的大量删除是有意清理，不要恢复两套渲染链。
- 当前 debug APK：`build/app/outputs/flutter-apk/app-debug.apk`，但包含上述导入阻塞，仅用于继续调试。

## 7. 回归命令

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter run -d <android-device>
flutter run -d macos
git diff --check
```

真机优先验证完整链路：导入正文 EPUB → 确认 kind=book → 打开 → 首次翻页 → 退出重开 → 折叠/展开 → 再翻页。
