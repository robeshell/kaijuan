# Kaika design system (shared tokens; dual-brand apps)

> UI generation contract. Product authority: [../PRODUCT.md](../PRODUCT.md) (two apps).  
> Visual: [../DESIGN_FOUNDATION.md](../DESIGN_FOUNDATION.md). Index: [../README.md](../README.md).  
> Two store apps: **comic** and **book**. Do not design a single app with type segments.

## Overview

Quiet sunlit-study readers. **Two branded apps** share spacing, glass chrome language, and cover-first library patterns. Each app has its own name, icon, accent, default reading theme, and import whitelist.

- **comic:** page-image immersion, default content bg #1C1C1E  
- **book:** long-form reflow (when built), paper-like defaults  

Light shell is acceptance baseline. Not a social store, not dual-tab manga|books inside one binary.

## Colors (shared defaults; brand may override accent)

- canvas: #F7F7F8  
- surface: #FFFFFF  
- text-primary: #1C1C1E  
- text-secondary: #1C1C1E @ 60%  
- hairline: #1C1C1E @ 8%  
- accent-ember (comic example): #EA580C  
- reading-paper: #FAFAF8  
- reading-sepia: #F5F0E6  
- reading-dark: #1C1C1E  
- reading-black: #000000  

## Typography

System sans. Simplified Chinese UI. Calm hierarchy.

## Layout

- Spacing: 4 / 8 / 12 / 16 / 24 / 32  
- Per app: 书架 / 书库 / 设置 only — no 漫画|图书 segment  
- Reader edge-to-edge; chrome overlays  

## Elevation & Shapes

Soft paper shadows; glass blur ≤ 20; radii 8 / 12 / 16 / 20.

## Components

### Navigation
Rail/tabs: 书架 · 书库 · 设置. Selected uses brand accent.

### Shelf
Continue-reading hero + recent. Optional 我的书架. Empty → this app's library.

### Library
One grid for **this app's** items only. Single 导入. Search field (near). No format-type dual IA.

### Reader chrome
Glass top/bottom; comic modes vs book type controls by app.

### Settings
Appearance for **this** brand only.

## Do's and Don'ts

### Do
Unified cards; covers supply color; Chinese labels; state which brand you are mocking.

### Don't
Single app 漫画|图书 tabs; shared-library UX across brands; cloud/social; neon glass.
