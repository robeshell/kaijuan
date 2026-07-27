# Kaijuan patches on flutter_inappwebview_ios 1.2.0-beta.3

Base: Apache-2.0 package from pub.dev `flutter_inappwebview_ios` 1.2.0-beta.3.

## Why

iOS 18.2+ adds system edit-menu items such as **Copy Link with Highlight**
and **Writing Tools**. `InAppWebViewSettings.disableContextMenu = true` already
makes `canPerformAction` return false for classic items, but those new items
are injected by `super.buildMenu(with:)` and still appear.

Readium fixed the same issue by **not calling `super.buildMenu`** and setting
`writingToolsBehavior = .none` (readium/swift-toolkit#509 / #532).

## Changes

1. `InAppWebView.buildMenu`: when `settings.disableContextMenu == true`, return
   without `super.buildMenu(with:)`.
2. `InAppWebView.preWKWebViewConfiguration`: on iOS 18+, set
   `configuration.writingToolsBehavior = .none`.

Search for `Kaijuan:` in `InAppWebView.swift` for the patch sites.
