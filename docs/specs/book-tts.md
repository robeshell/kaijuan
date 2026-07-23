# 图书听书（TTS）方案

| | |
|--|--|
| **状态** | **方案**（未实现） |
| **日期** | 2026-07-23 |
| **PRODUCT** | [§4.6](../PRODUCT.md) · [§7](../PRODUCT.md) |
| **相关** | [book-reader.md](./book-reader.md)、[book-reader-next-plan.md](./book-reader-next-plan.md)、[book-reader-tool-strip-plan.md](./book-reader-tool-strip-plan.md) |
| **引擎** | Foliate `tts.js` + 系统 TTS（不接云端 AI） |

> 落地后回写 PRODUCT / book-reader；本页可标「已有」或并入 book-reader。

---

## 1. 结论（先读）

**听书不需要 AI。**

| 层 | 职责 | 是否需要云端 |
|----|------|--------------|
| Foliate `tts.js` | DOM → 句/段 → `{text,cfi}`；高亮跟读；跨章 | 否（本地已有） |
| 系统 TTS | 把 `text` 念出来 | 否（OS 语音） |
| 云端神经音色 / LLM | 更好听 / 情感朗读 | **本方案不做** |

微信读书「AI 男/女声」是增值音色，不是听书主链必要条件。Kaika 为**本地阅读 App**，听书 v1 = **从当前位置连续朗读 + 句高亮跟随 + 语速 + 控制条**。

词典 / 翻译另案；与听书解耦，不共享「AI 底层」。

---

## 2. 目标与非目标

### 做（v1）

- 底栏「听书」接通：从**当前阅读位置**开始连续朗读。
- 句级高亮跟随（复用 Foliate Overlayer）。
- 播放 / 暂停；上一句 / 下一句；语速（系统能力范围内）。
- 跨 spine 节自动续读（Foliate `ttsNext` / `ttsNextSection`）。
- 退出阅读器、关书、dispose 时停止并清高亮。
- 选区菜单「朗读」槽：听书落地后可露出（关菜单 → 从该选区 CFI 起读）；v1 可仍隐藏，只走底栏。

### 不做（v1）

- 云端神经 TTS、账号、在线音色商店。
- LLM 边生成边读。
- EPUB3 Media Overlay（预录音频 + SMIL）——远期可另开，与 TTS 并列。
- 漫画引擎听书。
- 完美复刻微信听书 UI / 后台锁屏歌词级体验（后台播放列为 **中**，见下）。

### 中（可第二刀）

- 后台 / 锁屏继续播（iOS Audio session、Android foreground service）。
- 定时停止、章节播完提醒。
- 音色列表（仅系统已安装 voice）。
- 选区「朗读」槽露出。

---

## 3. 引擎现状（只读结论）

Foliate 已热加载 `src/tts.js`；**不含** `speechSynthesis`。Dart **零接线**；底栏 SnackBar「听书即将推出」。

暴露 API（`book.js`）：

```text
initTts / ttsStop
ttsHere / ttsFromCfi
ttsCurrentDetail / ttsCollectDetails / ttsPrepare
ttsNext / ttsPrev / ttsNextSection / ttsPrevSection
ttsHighlightByCfi
```

分段：块标签 → 句（`.!?。！？`）；本地锚点链接内文本跳过。  
高亮：`initTTS` 注入 Overlayer + `scrollToAnchor`。  
跨章：当前节句尽 → `nextSection` → 重 `initTts` → 下节首句。

---

## 4. 架构

```text
底栏听书 /（可选）选区朗读
        │
        ▼
BookReaderController（播放状态、语速、生命周期）
        │
        ├─ FoliateJs bridge：window.tts* → { text, cfi }
        │
        └─ 系统 TTS（flutter_tts 或平台原生）
              onComplete → ttsNext() → speak(下一句)
```

原则：

- **表现层只认 controller**；不直连 WebView / TTS 插件。
- JS 只产出文本与定位；**发声全在 Dart**。
- 进度仍以 CFI / relocation 为准；听书不另建进度表（跟随阅读位置即可）。

---

## 5. 交互

### 入口

| 入口 | 行为 |
|------|------|
| 底栏「听书」 | 未播 → `ttsHere` + 开始；已播 → 展开迷你控制 / 切换暂停 |
| 选区「朗读」 | **中**：关菜单 → `ttsFromCfi` + 开始 |

### 迷你控制（建议）

- 位置：底栏听书键上方面板，或底部轻量条（不永久改 pageSize）。
- 控件：暂停/继续 · 上一句 · 下一句 · 语速（如 0.8 / 1.0 / 1.25 / 1.5）。
- 再点听书或空白策略：与现有 chrome 显隐一致即可，避免抢翻页。

### 状态机

```text
idle
  ├─ start(here|cfi) ──► playing
playing
  ├─ pause ──► paused
  ├─ next/prev ──► playing（换句）
  ├─ stop / 退出阅读器 ──► idle（ttsStop）
paused
  ├─ resume ──► playing
  └─ stop ──► idle
```

句末：TTS `onComplete` → `ttsNext()`；若返回空且已到书末 → `idle` + 轻提示「已读完」。

---

## 6. 实现落点（落地时）

| 文件 / 层 | 职责 |
|-----------|------|
| `foliate_js_bridge.dart` | `FoliateTtsUtterance { text, cfi }` 解析 |
| `foliate_js_engine_adapter.dart` | `evaluate` 封装 `tts*` |
| `book_reader_controller.dart` | 播放状态、语速偏好、启停与 completion 串联 |
| `BookReadingPreferences` | 持久化语速（可选音色 id） |
| UI | 工具条听书键去占位；迷你控制面板 |
| `pubspec` | `flutter_tts`（或等价）；**不**引入云 TTS SDK |

桌面（macOS / Windows）：系统 TTS 可用则开；若某平台插件弱，可先 **移动端优先**，桌面保留占位并写进验收例外。

---

## 7. 与「AI 底层」的边界

| 能力 | 听书 v1 | 词典/翻译另案 |
|------|---------|----------------|
| 本地系统 API | TTS 发声 | 可优先系统词典 |
| 离线资源 | 系统语音包 | 可选离线词库 |
| 云端 / LLM | **不做** | 若做需单独设计账号与隐私 |

**不**为听书先建通用 AI 层。若未来要云端音色，单独立项改 PRODUCT 非目标后再接可替换的 `TtsVoiceEngine` 接口；v1 接口保持「喂一句 text、回调完成」即可，避免过早抽象。

---

## 8. 刀序与验收

### 刀 T1（MVP）

1. Bridge + controller 闭环：`ttsHere` → speak → complete → `ttsNext`。  
2. 底栏听书：开始 / 暂停 / 停止；句高亮可见。  
3. 退出阅读器必停。  

**验收**：打开 EPUB → 听书 → 连续多句有高亮 → 跨一章不断 → 暂停/继续正常 → 返回书库无残余朗读。

### 刀 T2（体验）

语速持久化；上一句/下一句；迷你控制条打磨；选区「朗读」可选露出。

### 刀 T3（中）

后台播放；系统音色选择。

---

## 9. 风险

| 风险 | 缓解 |
|------|------|
| 中文系统音质一般 | 接受 v1；文案不承诺「AI 音色」 |
| 句切不准（古文/对话） | 沿用 Foliate 规则；个案不专项 |
| 桌面 Platform View 与控制条点击 | 复用 `PointerInterceptor` |
| 翻页/滚动与 TTS 抢焦点 | 播放中限制自动 chrome；用户翻页可 pause 或 `ttsFromCfi` 重定位（产品定一种） |
| `flutter_tts` 与新 Flutter/KGP | 选型时避开会 apply 旧 KGP 的过时插件 |

---

## 10. 文档回写清单（落地后）

- [ ] `PRODUCT.md` §4.6：听书标 **已有**（或分 MVP/完整）  
- [ ] `book-reader.md`：听书占位 → 行为；非目标去掉「TTS」或改为云端 TTS  
- [ ] `book-reader-next-plan.md`：P5 TTS → 已有 / 进行中  
- [ ] 本页状态 → **已有**
