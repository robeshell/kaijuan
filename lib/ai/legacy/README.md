# lib/ai/legacy/

**Not production paths.** Held for unit tests and technical-article archaeology.

| Module | Was | Now |
|--------|-----|-----|
| `ai_book_mind_map_workflow.dart` | Production mind-map Product Workflow | Session path uses `runMindMapSession` |
| `ai_book_outline_service.dart` | Structured batch outline | Chat shortcut only |

Do not wire these into production Domain adapters or Workspace assembly.
