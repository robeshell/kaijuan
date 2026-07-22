# Anx Reader 全链路研究与 Kaika 取舍

研究基线：[`Anxcye/anx-reader`](https://github.com/Anxcye/anx-reader) commit `107f4fa74db0e7247c846c49d6211df3edf9887c`，MIT License。Kaika 已在 `assets/anx_reader/` 保留来源说明与许可证。

本文是实现决策记录，不把 Anx Reader 当成 Kaika 的产品规格。我们复用成熟的 EPUB rendition 行为，但不照搬其 UI、数据库或大文件组织。

## 1. Anx 的实际全链路

```text
文件选择
  → 扩展名过滤
  → MD5 与数据库查重
  → 非 EPUB 格式先转换为 EPUB
  → loopback server 暴露临时文件
  → headless WebView 以 importing=true 打开 foliate-js
  → 同一 Reader 解析 metadata / cover
  → 文件与封面复制到应用目录，BookDao 入库
  → ReadingPage / EpubPlayer
  → loopback server 流式返回书籍与 foliate-js
  → URL 传入初始 CFI、样式和阅读规则
  → foliate Reader 打开文件并建立 rendition
  → bridge 上报 TOC / relocated / selection / annotation 等事件
  → CFI + 全书 fraction 写回 Book / DB
```

对应代码入口：

| 环节 | Anx 文件 | 观察 |
|---|---|---|
| 选择与导入 UI | `page/home_page/bookshelf_page.dart`、`service/book.dart` | 批量选择、重复与不支持文件提示完整，但 UI、临时文件、导入和数据库混在同一 service。 |
| 元数据 | `service/book.dart#getBookMetadata` | headless WebView 使用与阅读相同的 foliate-js；`onMetadata` 返回 metadata 和 base64 cover。 |
| 本地服务 | `service/book_player/book_player_server.dart` | 单例 loopback server 同时服务书籍、renderer、字体和背景图。 |
| 打开路由 | `service/book.dart#pushToReadingPage` | 先检查本地文件/同步/权限，再初始化当前阅读状态并进入 ReadingPage。 |
| rendition | `page/book_player/epub_player.dart` | 初始 CFI、样式、WebView bridge、进度保存都集中在一个较大的 StatefulWidget。 |
| Foliate | `assets/foliate-js/src/book.js` | `fetch → Blob → File → Reader.open`；导入模式取元数据，阅读模式上报 load/TOC/relocation。 |
| 数据 | `models/book.dart`、`dao/book.dart`、`providers/book_list.dart` | Book 同时承担领域对象和数据库记录；provider 会直接调用 DAO。 |

## 2. 值得借鉴的设计

1. **一个 canonical rendition**：目录、样式、内部链接、分页、CFI 都以同一 Foliate 解析结果为准，避免 Dart HTML 与 WebView HTML 两套语义漂移。
2. **CFI 是恢复位置的主键**：初始 CFI 在首屏打开时传入，而不是先画第一页再跳；relocation 后直接持久化 CFI。
3. **renderer 负责 reflow**：CSS columns、滚动流、手势吸附、章节挂载和 resize 都留在浏览器侧，Flutter 不预分页。
4. **loopback 输入适配**：WebView 只处理 HTTP URL；Dart 侧用流返回本地文件并限制监听地址为 `127.0.0.1`。
5. **bridge 以事件为边界**：load、relocation、TOC、点击、选择和错误有明确回调面，Flutter 不读取 renderer 内部 DOM 状态来驱动业务。
6. **导入和阅读共享格式能力**：Anx 甚至用 headless Foliate 提取 metadata，显著降低“导入认为能读、打开却读不了”的概率。

## 3. 不照搬的部分

| Anx 做法 | Kaika 取舍 |
|---|---|
| `service/book.dart` 同时做对话框、hash、转换、文件删除、metadata、DAO | 导入 UI 只调 `LibraryController`；编排留在 import service，文件与 DB 操作有各自边界。 |
| `EpubPlayer` 同时管理 WebView、阅读状态、DAO、provider 和大量功能 | `BookReaderScreen → BookReaderController → FoliateJsBookEngineAdapter`；adapter 不直接访问 drift。 |
| provider 直接读写 DAO | 表现层只认 controller；数据库不会暴露给 screen/widget。 |
| Book model 含路径、进度、删除状态和展示字段 | `ReadingItem`、format-owned locator、偏好与 rendition 状态分开。 |
| MD5 去重、按标题和时间生成文件名 | 继续使用 SHA-256 content-addressed storage，同一内容只存一份。 |
| 全局 server / headless WebView 单例 | 阅读 session 自己拥有 server/WebView，dispose 释放；导入探针必须可取消且不能污染当前阅读 session。 |
| loopback URL 携带绝对路径 | Kaika server 暴露固定 `/book.epub`，不接受客户端传入任意文件路径。 |
| 一次扩展 mobi/azw3/fb2/txt/pdf 并统一转换 | 当前只保证 EPUB/CBZ/ZIP；新增格式必须单独定产品与转换策略。 |

## 4. Kaika 目标链路

```text
presentation
  LibraryScreen
    → LibraryController.importFiles()

application / import
  EpubImportRouter                 # 只负责 book/comic 判定
    → file-backed EpubProbe
    → BookImportService | ComicImportService
      → ContentStore               # SHA-256 寻址、原子落盘
      → MetadataProbe              # 标题/封面/section 摘要
      → AppDatabase transaction

reading
  BookReaderScreen
    → BookReaderController         # locator、书签、偏好、chrome
      → FoliateJsBookEngineAdapter # session 生命周期与 typed bridge
        → SessionLoopbackServer    # 固定资源路由、仅 loopback
        → foliate-js rendition     # EPUB、TOC、CFI、reflow、输入
```

这不是“可换引擎”架构。`FoliateJsBookEngineAdapter` 是自研阅读管线的 rendition 层，拆边界是为了控制生命周期、测试和平台差异，而不是为另一套排版引擎预留插槽。

### 必须保持的契约

- 导入成功前：内容文件、封面和 DB 记录要么全部可用，要么可回滚/可重试。
- kind 判定：只读取有界样本，禁止整本 `readAsBytes()` 后再重复解包。
- 打开：一个 screen 只拥有一个 rendition session；新任务和 dispose 使旧异步回调失效。
- ready：renderer 完成 open 且 TOC/spine 已 attach 后才成立。
- 位置：数据库只保存不透明 `BookLocator`；CFI 存在时优先 CFI，section/fraction 是兼容与展示坐标。
- resize/fold：冻结最后稳定 CFI；普通 reflow 保活 WebView，renderer 被系统杀死时才重建。
- persistence：bridge 只上报位置；controller 负责 debounce 和数据库写入。
- 安全：server 只绑定 loopback、路由白名单化、拒绝 `..`，离开阅读器立即关闭。

## 5. 分阶段落地

### 已完成

- 阅读主链切到 Anx 维护的 foliate-js，保留完整上游资源与许可证。
- CFI 首屏恢复、TOC、relocation、样式、翻页/滚动与折叠屏恢复由 Foliate adapter 接回 Kaika controller。
- 删除 Flutter HTML / TextPainter 自有分页器及其 pageMap 状态，避免双渲染链继续漂移。
- EPUB kind 探测改为 file-backed probe，不再整本读入 Dart 内存后重复解析。
- `BookRenditionSession` 独立拥有固定路由 loopback server 和 WebView generation lease；被替换 renderer 的迟到回调不再能修改当前阅读状态。
- publication / TOC / relocation / viewport click 已收口为 typed bridge model；打开链记录 server、WebView、renderer、publication 和首个 relocation 的分段耗时。
- book/comic 导入统一改为 `.import-staging`：复制与 SHA-256 单次流式完成，解析成功后原子提交内容/封面，DB 失败执行补偿回滚；失败测试验证正式目录无半成品。
- `foliate-probe`、book metadata、comic page list、cover、文件提交和 DB 提交均记录分段 timing；导入与阅读使用同一份 Foliate EPUB 语义。

### 下一阶段

1. **P0：修复 metadata-only 页面启动契约。** 当前 `epub.js Loader` 隐式读取 URL 的 `style.allowScript`，而 probe URL 只传 `url`，Android 真机抛出 `Cannot read properties of null (reading 'allowScript')`。详见 [dev-handoff.md](../dev-handoff.md#2-当前-p0-阻塞正文-epub-被识别为漫画)。
2. **P0：禁止 probe 失败后仅凭包内图片回退为 comic。** 正文 EPUB 的封面/插图不是页图 spine 证据；解析失败应成为可诊断错误。
3. 用真实 HeadlessInAppWebView 集成样本验证正文 EPUB、带插图正文 EPUB和 image-only EPUB；现有 fake probe 单测不足以覆盖 JS 启动参数。
4. 用真机 timing 验证修复后的 MetadataProbe 首本/连续导入、失败恢复和跨端表现。
5. 把阅读和导入阶段耗时接入可导出的诊断记录，不只停留在 debug console。
6. 清理超时遗留的 `.import-staging/*.partial`（仅删除确认未被活跃事务持有的旧文件）。
7. 再接内部链接、脚注、选区/标注等 bridge；每项先定义 controller 契约，不直接把 Anx 页面逻辑搬入 screen。

## 6. 验证重点

- 同一 EPUB 的 import/open 结果一致：正文不为空、封面/标题稳定、TOC 可跳。
- 100MB 级 EPUB 导入时 Dart 堆不出现整本 bytes 的双份峰值。
- 连续打开/退出、快速打开两本、折叠屏来回切换不会留下 server、WebView 或迟到回调。
- 字号、方向和 viewport 改变后 CFI 语义位置稳定。
- 失败有阶段化错误（hash/probe/store/open/render），不以无限 loading 代替错误。
