import Cocoa
import FlutterMacOS
import SwiftUI
import Translation

@available(macOS 15.0, *)
private struct BookTranslationTaskView: View {
  let text: String
  let source: Locale.Language
  let target: Locale.Language
  let onFinished: (String?) -> Void

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .translationTask(
        TranslationSession.Configuration(source: source, target: target)
      ) { session in
        do {
          let response = try await session.translate(text)
          onFinished(response.targetText)
        } catch {
          onFinished(nil)
        }
      }
  }
}

class MainFlutterWindow: NSWindow {
  /// Brand `layoutMetrics.desktopWindow` — keep side rail (medium min / wide default).
  private let minContentSize = NSSize(width: 1024, height: 700)
  private let defaultContentSize = NSSize(width: 1280, height: 800)
  private var translationHost: NSView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Match the Flutter launch canvas (#F7F9FC brand canvas) so the first
    // native frame is not black or pure white.
    let launchCanvas = NSColor(
      srgbRed: 0xF7 / 255.0,
      green: 0xF9 / 255.0,
      blue: 0xFC / 255.0,
      alpha: 1)
    flutterViewController.backgroundColor = launchCanvas
    self.contentViewController = flutterViewController
    self.backgroundColor = launchCanvas

    // Reverie-style: content draws under the titlebar; traffic lights stay native.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    self.contentMinSize = minContentSize
    self.minSize = self.frameRect(
      forContentRect: NSRect(origin: .zero, size: minContentSize)
    ).size

    var contentSize = defaultContentSize
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      contentSize.width = min(
        contentSize.width,
        max(minContentSize.width, visible.width - 80))
      contentSize.height = min(
        contentSize.height,
        max(minContentSize.height, visible.height - 80))
    }
    self.setContentSize(contentSize)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.kaijuan.reader/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "copyImagePng" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let data = call.arguments as? FlutterStandardTypedData else {
        result(
          FlutterError(code: "bad_args", message: "missing png bytes", details: nil))
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      let ok = pasteboard.setData(data.data, forType: .png)
      result(ok)
    }

    let languageChannel = FlutterMethodChannel(
      name: "com.kaijuan.reader/language",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    languageChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      guard call.method == "openDictionary" || call.method == "openTranslation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let text = arguments["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(false)
        return
      }
      if call.method == "openDictionary" {
        self.openDictionary(text: text, result: result)
      } else {
        self.openTranslation(text: text, result: result)
      }
    }

    // Full-screen readers host a Platform View (WKWebView) that eats mouse
    // events, so isMovableByWindowBackground no longer moves the window.
    // Flutter title-band widgets call startDrag → performDrag.
    let windowChannel = FlutterMethodChannel(
      name: "com.kaijuan.reader/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent {
          self.performDrag(with: event)
        }
        result(nil)
      case "isMaximized":
        result(self.isZoomed)
      case "minimize":
        self.miniaturize(nil)
        result(nil)
      case "maximize":
        if !self.isZoomed { self.zoom(nil) }
        result(nil)
      case "restore":
        if self.isZoomed { self.zoom(nil) }
        result(nil)
      case "close":
        self.close()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func openDictionary(text: String, result: @escaping FlutterResult) {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(string: "dict://\(encoded)")
    else {
      result(false)
      return
    }
    result(NSWorkspace.shared.open(url))
  }

  private func openTranslation(text: String, result: @escaping FlutterResult) {
    guard #available(macOS 15.0, *) else {
      result(false)
      return
    }
    let source = containsCjk(text)
      ? "zh-Hans"
      : "en"
    let target = source == "zh-Hans" ? "en" : "zh-Hans"
    let sourceLanguage = Locale.Language(identifier: source)
    let targetLanguage = Locale.Language(identifier: target)
    let host = NSHostingView(
      rootView: BookTranslationTaskView(
        text: text,
        source: sourceLanguage,
        target: targetLanguage,
        onFinished: { [weak self] translated in
          guard let self else {
            result(false)
            return
          }
          self.translationHost?.removeFromSuperview()
          self.translationHost = nil
          guard let translated else {
            result(false)
            return
          }
          let alert = NSAlert()
          alert.messageText = "翻译"
          alert.informativeText = translated
          alert.addButton(withTitle: "完成")
          alert.beginSheetModal(for: self) { _ in }
          result(true)
        }))
    host.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
    host.alphaValue = 0
    contentView?.addSubview(host)
    translationHost = host
  }

  private func containsCjk(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      (0x4E00...0x9FFF).contains(Int(scalar.value))
    }
  }
}
