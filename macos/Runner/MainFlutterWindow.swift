import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Keep desktop layout (side rail). Matches Flutter `AppShell.desktopMinSize`.
  private let minContentSize = NSSize(width: 1024, height: 700)
  private let defaultContentSize = NSSize(width: 1280, height: 800)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Match the Flutter splash canvas so the first native frame is not black.
    flutterViewController.backgroundColor = NSColor.white
    self.contentViewController = flutterViewController
    self.backgroundColor = NSColor(
      srgbRed: 1,
      green: 1,
      blue: 1,
      alpha: 1)

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
      name: "com.kaika.reader/clipboard",
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

    super.awakeFromNib()
  }
}
