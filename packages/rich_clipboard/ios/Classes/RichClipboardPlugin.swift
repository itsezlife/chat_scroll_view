import Flutter
import UIKit

/// The iOS side of rich_clipboard: one pasteboard item with the plain text
/// and the HTML, so each reader takes the richest type it knows.
public class RichClipboardPlugin: NSObject, FlutterPlugin {
  private static let plainType = "public.utf8-plain-text"
  private static let htmlType = "public.html"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "rich_clipboard",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(RichClipboardPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let pasteboard = UIPasteboard.general
    switch call.method {
    case "write":
      guard let arguments = call.arguments as? [String: Any],
        let plain = arguments["plain"] as? String,
        let html = arguments["html"] as? String
      else {
        result(FlutterError(code: "bad-arguments", message: "write takes plain and html", details: nil))
        return
      }
      pasteboard.items = [[
        RichClipboardPlugin.plainType: plain,
        RichClipboardPlugin.htmlType: html,
      ]]
      result(nil)
    case "read":
      // One access to the items: iOS asks the user to allow a paste per
      // access, so the plain text and the HTML are read together.
      guard let item = pasteboard.items.first else {
        result(nil)
        return
      }
      let html = RichClipboardPlugin.text(of: item[RichClipboardPlugin.htmlType])
      let plain =
        RichClipboardPlugin.text(of: item[RichClipboardPlugin.plainType])
        ?? RichClipboardPlugin.text(of: item["public.plain-text"])
        ?? RichClipboardPlugin.text(of: item["public.text"])
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

  // A pasteboard value as text: other apps hand HTML over as data.
  private static func text(of value: Any?) -> String? {
    switch value {
    case let string as String:
      return string
    case let data as Data:
      return String(data: data, encoding: .utf8)
    default:
      return nil
    }
  }
}
