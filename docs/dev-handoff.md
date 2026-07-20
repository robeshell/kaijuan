# Dev Handoff

非权威。功能 → [PRODUCT.md](./PRODUCT.md)；工程 → [ENGINEERING.md](./ENGINEERING.md)；索引 → [README.md](./README.md)。

## 已定

- **双 App 双品牌**（comic / book），单仓库共享 core。  
- 文档已改；工程骨架：`lib/brand/` + `main_comic.dart` / `main_book.dart`。

## 建议下一刀

1. 用最终设计覆盖 `brands/icons/*/master_1024.png` 后跑 `python3 tool/generate_brand_icons.py`  
2. PRODUCT 阶段 1（comic）：删除、搜索、上架…  
3. book 引擎仍靠后  

## 验证

```sh
flutter analyze && flutter test
tool/run_brand.sh comic
# macOS flavor 冒烟：
# flutter build macos --debug --flavor comic -t lib/main_comic.dart
# flutter build macos --debug --flavor book -t lib/main_book.dart
```
