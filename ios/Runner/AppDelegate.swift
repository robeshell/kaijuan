import Flutter
import SwiftUI
import Translation
import UIKit

@available(iOS 18.0, *)
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

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var translationHost: UIViewController?

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

    let languageChannel = FlutterMethodChannel(
      name: "com.kaijuan.reader/language",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
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
  }

  private func openDictionary(text: String, result: @escaping FlutterResult) {
    guard let presenter = topViewController() else {
      result(false)
      return
    }
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) else {
      result(false)
      return
    }
    presenter.present(
      UIReferenceLibraryViewController(term: term),
      animated: true)
    result(true)
  }

  private func openTranslation(text: String, result: @escaping FlutterResult) {
    guard #available(iOS 18.0, *) else {
      result(false)
      return
    }

    let source = containsCjk(text) ? "zh-Hans" : "en"
    let target = containsCjk(text) ? "en" : "zh-Hans"
    var completed = false
    let finish: (String?) -> Void = { [weak self] translated in
      guard let self, !completed else { return }
      completed = true
      self.removeTranslationHost()
      guard
        let translated,
        let presenter = self.topViewController()
      else {
        result(false)
        return
      }
      let alert = UIAlertController(
        title: "翻译",
        message: translated,
        preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "完成", style: .default))
      presenter.present(alert, animated: true)
      result(true)
    }

    guard let presenter = topViewController() else {
      result(false)
      return
    }
    let host = UIHostingController(
      rootView: BookTranslationTaskView(
        text: text,
        source: Locale.Language(identifier: source),
        target: Locale.Language(identifier: target),
        onFinished: finish))
    addTranslationHost(host, to: presenter)
  }

  private func containsCjk(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      (0x4E00...0x9FFF).contains(Int(scalar.value))
    }
  }

  private func addTranslationHost(
    _ host: UIViewController,
    to presenter: UIViewController
  ) {
    host.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    host.view.alpha = 0
    presenter.addChild(host)
    presenter.view.addSubview(host.view)
    host.didMove(toParent: presenter)
    translationHost = host
  }

  private func removeTranslationHost() {
    guard let host = translationHost else { return }
    host.willMove(toParent: nil)
    host.view.removeFromSuperview()
    host.removeFromParent()
    translationHost = nil
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap {
      $0 as? UIWindowScene
    }
    let window = scenes
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
      ?? scenes.flatMap(\.windows).first
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    if let navigation = controller as? UINavigationController {
      return navigation.visibleViewController ?? navigation
    }
    if let tab = controller as? UITabBarController {
      return tab.selectedViewController ?? tab
    }
    return controller
  }
}
