# 阅读器 Chrome 设计规范

| | |
|--|--|
| **PRODUCT** | [§4.6](../PRODUCT.md) |
| **视觉** | [DESIGN_FOUNDATION.md](../DESIGN_FOUNDATION.md) |

## 目标

- **comic App**：页图引擎 chrome（模式 / 方向 / 页进度）。  
- **book App**：reflow chrome（目录 / 字号等，另见 book-reader spec）。  
- **可共享**：玻璃顶底栏、显隐节奏、错误态语言；皮肤跟 **品牌 + 阅读主题**。

## 原则

内容即界面；chrome 默认可隐藏；引擎分叉、壳组件尽量复用。

## 阅读主题默认

| 产品 | 默认内容背景 |
|------|----------------|
| comic | 深灰 `#1C1C1E` |
| book | 纸白等（book spec） |

## 布局与材质

- 顶栏 h56、底栏进度+引擎控件、中央单击显隐。  
- glassFill + 克制模糊；跟随阅读主题深浅。  
- 交互节奏同前（200ms、拖动松手 seek、桌面键位）。  
- **桌面**：阅读器全窗覆盖壳层标题栏时，顶 chrome 须 `platformTitleBarHeight` 下沉；macOS 额外左侧让开红绿灯（~78）。
