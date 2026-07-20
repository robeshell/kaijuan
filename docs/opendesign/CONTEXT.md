# Context for Open Design — dual-brand readers

**Authority:** `docs/PRODUCT.md`, `docs/DESIGN_FOUNDATION.md`, `docs/ENGINEERING.md`.

## Product model

**Two separate apps** (two store listings, two brands), one engineering monorepo:

| Code id | Focus | Default reading |
|---------|--------|-----------------|
| **comic** | Page-image / CBZ | Dark gray content `#1C1C1E` |
| **book** | Reflow / EPUB… | Paper-like (TBD) |

- **Not** one app with 漫画\|图书 tabs.  
- Data isolated per app.  
- Shared: quiet glass chrome language, spacing scale, cover-first cards.  
- Different: name, icon, accent, defaults, import whitelist, empty-state copy.

## Per-app IA (same structure)

书架 · 书库 · 设置 — continue reading, library grid, import, search (near), lists (mid).

## What to mock

Say which brand: **comic** or **book**.

**Comic (ship-ready narrative):** shelf continue-reading, library + import, page reader chrome, settings appearance.  
**Book:** same shell structure, paper reading defaults, no fake full reflow unless asked — placeholder library OK.

Chinese UI. Light shell acceptance. Accent example `#EA580C` (brands may differ). No cloud/social/store.
