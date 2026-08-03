# WebDAV 备份与恢复

## 定位

这是用户自有 WebDAV 空间上的**快照备份**，不是开卷账号云同步，也不是两台设备实时双向合并。每次成功备份都会发布一份不可变快照；恢复时用户选择一份快照并合并到当前书库。

第一版只提供：

- 手动备份；
- 书籍文件的内容寻址和增量上传；
- 进度、书签、划线、笔记、书单和合集的逻辑导出；
- 空库恢复和合并恢复；
- 恢复前预览；
- 失败时不发布半成品快照。

自动备份目前只在 App 前台启动时做一次机会性检查；移动端不承诺退出时执行。备份保留策略和端到端加密是后续迭代点。WebDAV 密码永远不写入备份，第一版仍依赖 HTTPS 和用户服务器自身的存储安全。

## 备份范围

包含：

- `ReadingItems` 的用户可见字段和原始书籍对象；
- `ReadingProgress`；
- `Bookmarks`；
- `BookAnnotations`；
- `ReadingLists` 与成员；
- `Collections` 与成员。

不包含绝对路径、封面缓存、导入临时目录、WebView 缓存、WebDAV 凭据和运行中的听书状态。恢复使用 `contentHash` 建立书籍身份，不能依赖数据库自增 ID 或本机 `filePath`。

## 远端布局

```text
KaijuanBackup/v1/
  objects/<contentHash>/chunks/<index>-<chunkHash>.bin
  objects/<contentHash>/object.json
  snapshots/<deviceId>/<snapshotId>/data.json.gz
  snapshots/<deviceId>/<snapshotId>/manifest.json
  devices/<deviceId>/latest.json
```

书籍以 32 MiB 固定分块上传。分块写入 `.partial` 后通过 WebDAV `MOVE` 发布；`object.json` 发布后才认为书籍对象完整。`data.json.gz` 上传完成后才发布 `manifest.json`；恢复只读取有 manifest 的快照，因此中途断网不会被当成可恢复备份。

## 数据和冲突

- 进度按 `updatedAt` 较新的记录恢复；
- 书签按 `(contentHash, locatorJson)` 去重并取并集；
- 划线按 `(contentHash, cfi)` 去重，合并模式保留本地已有记录；
- 已存在书籍的本地标题不被静默覆盖；
- 新书籍使用备份中的标题和元数据；
- 书单和合集只添加缺失内容，不删除当前设备已有内容。

第一版没有“完全覆盖本地”模式。若未来加入多设备实时同步，需要为书签、划线、成员关系增加稳定同步 ID、更新时间和删除墓碑，不能把快照合并逻辑直接升级成同步逻辑。

## 分层

- `WebDavClient/WebDavSession`：协议请求、流式 PUT、MKCOL、HEAD、MOVE、GET、DELETE；
- `WebDavBackupStore`：远端目录、对象、快照发布和恢复下载；
- `BackupExporter`：在 Drift transaction 中导出逻辑记录，并验证本地内容哈希；
- `BackupService`：编排导出、增量上传、恢复预览和合并；
- `BackupController`：向设置页面暴露状态和进度；
- `BackupSettingsScreen`：只通过 controller 操作，不直接访问 Drift 或 HTTP。

备份与 WebDAV 导入共用连接和安全凭据，但不共用远程导入队列。设置页提供“备份位置”“立即备份”“从备份恢复”，连接管理仍复用 WebDAV 管理页。

## 目录选择

备份设置页的“备份目录”使用独立的 WebDAV 文件夹选择器：

- 只展示远程文件夹，不展示可导入书籍，也不进入导入队列；
- 进入目标文件夹后点击“选择此目录”，保存相对于 WebDAV 连接根目录的路径；
- 目录选择器与 WebDAV 连接管理共用连接和认证，但页面标题、底部操作和状态文案必须明确是“选择备份目录”；
- 备份服务仍会在首次备份时创建缺失的 `objects/`、`snapshots/` 和 `devices/` 子目录。

## 设置页布局

- 页面按“存储位置 / 备份选项 / 备份与恢复”拆成三个独立信息组，不得把连接、目录、设备、开关和操作塞入同一张大卡片；组间距至少为组内行间距的两倍。
- “存储位置”只包含 WebDAV 连接和备份目录两行；整行可操作，使用图标、主值和必要的 URL 副行，不在浅色卡片里再次嵌套大面积描边输入框。“管理连接”放在分组标题右侧，使用无填充的低强调文字操作。
- WebDAV 连接仍使用共享品牌菜单：桌面展开锚定菜单，移动端按平台使用菜单或 Sheet；当前项必须带勾选。不得直接使用 Material 默认 `DropdownButtonFormField` 弹层。
- 桌面连接菜单直接呈现连接项，不重复显示“WebDAV 连接”标题及其分隔线；字段标签和锚点已经提供足够上下文。
- 连接菜单允许用 URL 作为辨识连接所需的状态副行；带 URL 的桌面菜单项使用双行密度（最小高度 56），并在不突破品牌菜单最大宽度的前提下增加横向留白，不得把两行内容压进单行菜单高度。
- “备份选项”只包含设备名称与自动备份；设备名称在卡片行内编辑，不再出现一层输入框套一层卡片的双重轮廓。
- “备份与恢复”先展示最近状态，再展示一个明确的强调色主操作“立即备份”和一个低强调的“从备份恢复”；两个操作不得使用相同视觉重量。进行中和失败状态在原状态行替换，不让布局跳动。
- 备份范围与隐私边界收敛为操作区下方的两行小字，分别说明“包含内容”和“不会上传”，不单独占用大卡片。
