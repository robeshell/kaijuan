# 设计总纲

**视觉与体验原则**权威。功能见 [PRODUCT.md](./PRODUCT.md)；工程见 [ENGINEERING.md](./ENGINEERING.md)；索引见 [README.md](./README.md)。

| 主题 | 文档 |
|------|------|
| 双产品功能 | [PRODUCT.md](./PRODUCT.md) |
| 书库 / 书架 / 搜索 / 书单 / chrome | [specs/](./specs/) |
| Open Design | [opendesign/](./opendesign/)（可按品牌各出一套） |

---

## 产品性格（共享）

**开卷** 走 **安静、干净、书房感**：内容（封面 / 书页）出彩，外壳中性克制。  
差异在 **阅读引擎与默认场景**。

| | 漫画引擎 | 图书引擎 |
|--|----------|----------|
| 默认阅读主题 | 深灰 | 纸白 |
| 气质侧重 | 沉浸翻页、图为王 | 长文阅读、版心舒适 |

共享：**轻玻璃中性壳、token 刻度、封面主角、少元数据堆砌**。

---

## 信息架构（已定）

- **一个安装入口** = 一个 App；库面按「类型：全部/漫画/图书」筛选。  
- App 内：书架 / 书库 / 设置；库面根据 kind 混排。  
- 打开路由：按 `item.kind` 进入对应引擎族。  
- 功能阶段与清单只在 PRODUCT 维护。

---

## 批准的视觉方向（共享底座）

- **浅色模式**为壳验收基线；深色由同一语义 token 支持。  
- 画布中性近白（`#F7F7F8` 为默认示例）；品牌可替换 canvas/surface **仅在品牌配置中**，并保持中性克制。  
- 侧栏 / chrome / 菜单：克制磨砂玻璃；列表卡片用表面填充。  
- 强调色只用于选中 / 进度 / 主操作；同区最多一个主强调。  
- macOS：透明全尺寸标题栏；内容避开交通灯安全区。

## 外观分层

- **皮肤预设**：跟随系统 / 默认 / 纯净 / 深夜（每 App 独立存）。皮肤自带明暗与整套表面色板（canvas / surface / elevated / overlay）+ 玻璃 token + 动效 token；「跟随系统」按平台亮度在默认与深夜之间切换。  
- **强调色**：预设表（默认暖橙 ember）；与皮肤正交组合（皮肤 × 强调色）。  
- **阅读主题**：内容层独立（漫画默认深灰、图书默认纸白），与皮肤无关；阅读器 chrome 的颜色取自阅读主题以保证书页上的可读性。  
业务不写死随意色；**引擎差异通过各自偏好配置注入**，不复制两套无关组件树。

## 核心屏幕原则（每 App）

1. **书架**：继续阅读优先；安静空态。  
2. **书库**：统一网格（本库只有本类）；单一导入。  
3. **设置**：标题 + 锚点 + 表单列；无「另一产品」入口。  
4. **阅读器**：本引擎全屏；chrome 玻璃、默认可隐藏。

## 布局核心原则

**不用色块背景堆叠元素。** 视觉层次通过留白、hairline 分隔线和卡片浮起（阴影）来表达，不在不同信息层级之间插入纯色背景条。同一画布上各区域之间靠空间呼吸，不靠色块切分。

## 间距与形状（共享刻度）

- 间距：4 / 8 / 12 / 16 / 24 / 32  
- 圆角：10 控件 / 14 卡片 / 12 菜单 / 18 面板(sheet) / 20 对话框 / 999 胶囊  
- 分隔 hairline；阴影来自玻璃 token（`appGlass.shadow` × `effects.shadowScale`），不用 Material elevation

## 排版（壳层）

- 字族：系统字体（`.SF Pro Text`，回退 PingFang SC / Microsoft YaHei / Noto Sans CJK SC / Roboto）。  
- 层级靠**字重驱动**（w600 → w700 → w800）+ 颜色（primary → secondary → muted），不靠字号堆叠。  
- 大标题负字距（页标题 26/28 w800、letterSpacing −0.55）。  
- 阅读器正文排版独立（字体栈 / 字号 / 行高属阅读偏好，不受壳层排版影响）。

## Token 架构（三层）

1. **基础 token**：间距 / 圆角 / 强调色预设 / 皮肤色板（`lib/core/theme/tokens.dart`、`skins.dart`）。  
2. **语义 token**：`AppGlassTheme` + `AppSkinEffects` + `ColorScheme`，业务经 `context.appGlass`、`context.appPrimaryText` 等 context getter 读取（`lib/core/theme/context.dart`）。  
3. **组件层**：`AppGlassSurface` 原语 + 共享 kit（`lib/presentation/widgets/app_components.dart`、`app_overlays.dart`、`settings_components.dart`）。  

业务 UI 只引用语义层；玻璃模糊**按面选用**——浮面（对话框 / 菜单 / 底栏）模糊，重复的行 / 卡片不模糊（`blur: false`）。  

## 扩展

- 改共享气质 / 刻度 → 本文 + shared tokens。  
- 改某一品牌默认色 / 图标 → 该品牌配置与出图物料，不必分叉整份总纲。  
- 改功能范围 → PRODUCT。
