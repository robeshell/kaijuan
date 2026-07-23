import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.kaijuan.reader/clipboard",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
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
      if let image = UIImage(data: data.data) {
        UIPasteboard.general.image = image
        result(true)
      } else {
        result(
          FlutterError(code: "copy_failed", message: "invalid png", details: nil))
      }
    }
  }
}
