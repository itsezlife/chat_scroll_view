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
      name: "chat_scroll_view_example/selection_cap_haptic",
      binaryMessenger: engineBridge.pluginRegistry.registrar(
        forPlugin: "SelectionCapHaptic"
      )!.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "playError" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let generator = UINotificationFeedbackGenerator()
      generator.prepare()
      generator.notificationOccurred(.error)
      result(nil)
    }
  }
}
