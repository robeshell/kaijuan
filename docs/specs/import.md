# 导入链路规范

## 目标

导入拆成两层：

1. **导入方式（ImportMethod）**：文件从哪里来、用户怎样把它交给 App。
2. **导入格式（ReaderFormat）**：交给 App 的内容是什么、由哪个阅读引擎处理。

两层不能互相编码。任何导入方式都只能产生 `ImportCandidate`，之后统一进入 staging、hash、格式路由、封面/页序解析和数据库提交。

```text
导入方式
  → ImportCandidate（名称 / MIME / 字节流）
  → .import-staging 流式复制 + SHA-256
  → 格式识别 / EPUB kind 探测
  → comic import 或 book import
  → library / covers 原子提交
  → app_library upsert
```

## 导入方式

| 方式 | 说明 | 状态 |
|------|------|------|
| 本地文件 | 系统文件选择器选择一个或多个文件 | 已有 |
| 目录扫描 / 自动扫描 | 自动递归扫描 App Documents 与系统 Downloads 目录；先展示候选清单，用户确认后再导入；显式目录也可复用同一能力 | 首批 |
| 拖拽 | 桌面把文件拖入书库 | 后续 |
| 系统分享 | iOS / Android 分享到开卷，落成一个候选文件 | 后续 |
| WiFi 传书 | App 临时开启局域网上传入口 | MVP 已有；见 [wifi-transfer.md](./wifi-transfer.md) |
| WebDAV / 云端存储 | 用户配置的远程文件源；选择后下载并导入 | 首批 |
| OPDS / 在线书库 | 用户配置的远程目录源；浏览、搜索后下载并导入 | 首批 |

方式层的实现约束：

- 方式适配器不判断 `kind`，不直接调用 `ComicImportService` 或 `BookImportService`。
- 本地文件和目录扫描都只负责提供 `File` / 字节流与显示名称。
- 自动扫描是 best-effort：扫描中显示进行状态；没有目录、没有匹配文件时返回空结果，完成后显示 `0` 本，不作为失败。
- 自动扫描只负责发现候选文件；发现后必须进入可多选的确认页，用户点击“开始导入”后才进入 `ImportPipeline`，不能扫描完成即批量导入。
- 系统目录访问按平台能力处理：macOS 沙盒下载目录无权访问时打开目录授权；Android 通过 SAF 多选公共 Download 中的文件，不申请全盘存储权限；iOS 通过 Files 多选可访问文件，不假设存在可静默扫描的公共 Downloads 路径。
- 远程来源必须先下载到同一 staging 协议，不能把网络响应直接写进正式 `library`。
- 批量导入逐文件隔离失败；一个候选失败不能回滚同一批已成功提交的其他候选。
- 图书没有可提取的内嵌封面时，导入阶段生成带渐变底色和截断书名的确定性默认封面并写入 `coverPath`；漫画继续使用首张图片作为封面。
- 远程来源不内置第三方内容，也不由 App 托管或分发内容；用户自行配置地址并对来源负责。

## 导入格式

| 格式 | 目标引擎 | 处理方式 | 状态 |
|------|----------|----------|------|
| CBZ / ZIP | 漫画页图 | 直接列图、提取首图、保存原文件 | 已有 |
| EPUB 页图 | 漫画页图 | Dart ZIP/OPF spine 抽样后自动路由 | 已有 |
| EPUB 正文 | 图书 reflow | Foliate metadata probe + 原文件阅读 | 已有 |
| FB2 | 图书 reflow | Foliate `makeFB2` | 首批 |
| MOBI | 图书 reflow | Foliate `MOBI` | 首批 |
| AZW3 / KF8 | 图书 reflow | Foliate `MOBI` 内容探测 | 首批 |
| PDF | 图书固定版式 | Foliate `makePDF`，保留为 book | 首批 |
| TXT | 图书 reflow | 转换为规范 EPUB 后导入 | 首批 |
| Markdown | 图书 reflow | 受限 Markdown 转换为规范 EPUB | 首批 |

格式层的处理原则：

- `ReaderFormat` 是唯一格式枚举；筛选、导入白名单、数据库字段都使用它的 storage value。
- `kind` 是阅读引擎路由，不是导入方式的属性。普通图书格式直接进入 book；EPUB 需要额外做正文/页图探测。
- 文件扩展名只用于候选初判；格式服务仍必须检查文件是否存在、是否可解析和是否有可阅读内容。
- 原始格式保存在数据库 `format` 字段；TXT / Markdown 的正式阅读文件是确定性生成的 EPUB，使用生成内容 hash，源文件名只作为标题 fallback。

## 首批验收

- 本地单文件、多文件批量、目录递归扫描都走同一个 `ImportPipeline`。
- 同一个文件从本地文件或目录扫描进入时，content hash 去重行为一致。
- CBZ / ZIP / EPUB 既有链路回归通过。
- FB2 / MOBI / AZW3 / PDF 能通过同一 BookImportService 进入 `kind=book`，保存对应 `format`。
- TXT / Markdown 能转换为 EPUB 后进入同一 book 流程，HTML 特殊字符会被转义。
- 任一解析失败只留下失败项，不留下 `.partial`、半成品正式文件或错误 DB 行。
