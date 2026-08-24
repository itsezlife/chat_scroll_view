import Cocoa
import FlutterMacOS

public class EmojiDataPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "emoji_data",
      binaryMessenger: registrar.messenger
    )
    let instance = EmojiDataPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSupportedEmojis":
      guard
        let args = call.arguments as? [String: Any],
        let source = args["source"] as? [String]
      else {
        result(FlutterError(code: "bad_args", message: "Missing source list", details: nil))
        return
      }
      result(source.map { _ in true })
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
