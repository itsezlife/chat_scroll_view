import Cocoa
import FlutterMacOS

/// The macOS side of rich_clipboard: one pasteboard item with the plain text
/// and the HTML, so each reader takes the richest type it knows.
public class RichClipboardPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "rich_clipboard",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(RichClipboardPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let pasteboard = NSPasteboard.general
    switch call.method {
    case "write":
      guard let arguments = call.arguments as? [String: Any],
        let plain = arguments["plain"] as? String,
        let html = arguments["html"] as? String
      else {
        result(FlutterError(code: "bad-arguments", message: "write takes plain and html", details: nil))
        return
      }
      let item = NSPasteboardItem()
      item.setString(plain, forType: .string)
      item.setString(html, forType: .html)
      pasteboard.clearContents()
      pasteboard.writeObjects([item])
      result(nil)
    case "read":
      let plain = pasteboard.string(forType: .string)
      let html = pasteboard.string(forType: .html)
      if plain == nil && html == nil {
        result(nil)
        return
      }
      // A type the clipboard does not hold is left out.
      var held: [String: String] = [:]
      held["plain"] = plain
      held["html"] = html
      result(held)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
