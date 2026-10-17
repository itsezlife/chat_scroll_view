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
      let withMedia = (call.arguments as? [String: Any])?["media"] as? Bool ?? false
      // One access to the items: iOS asks the user to allow a paste per
      // access, so the text and the media are read together.
      let items = pasteboard.items
      guard let item = items.first else {
        result(nil)
        return
      }
      let html = RichClipboardPlugin.text(of: item[RichClipboardPlugin.htmlType])
      let plain =
        RichClipboardPlugin.text(of: item[RichClipboardPlugin.plainType])
        ?? RichClipboardPlugin.text(of: item["public.plain-text"])
        ?? RichClipboardPlugin.text(of: item["public.text"])
      // Images are saved to files away from the main thread, rather than
      // sent whole through the channel.
      DispatchQueue.global(qos: .userInitiated).async {
        let media = withMedia ? items.compactMap(RichClipboardPlugin.image(in:)) : []
        // A type the clipboard does not hold is left out.
        var held: [String: Any] = [:]
        held["plain"] = plain
        held["html"] = html
        if !media.isEmpty {
          held["media"] = media
        }
        DispatchQueue.main.async {
          result(held.isEmpty ? nil : held)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // The image an item holds, in the first form it has, saved to a file:
  // its path and type.
  private static let imageTypes: [(String, String, String)] = [
    ("com.compuserve.gif", "image/gif", "gif"),
    ("public.png", "image/png", "png"),
    ("public.jpeg", "image/jpeg", "jpg"),
    ("public.heic", "image/heic", "heic"),
    ("org.webmproject.webp", "image/webp", "webp"),
  ]

  private static func image(in item: [String: Any]) -> [String: Any]? {
    for (type, mime, fileExtension) in imageTypes {
      switch item[type] {
      case let data as Data:
        guard let path = saved(data, fileExtension: fileExtension) else { continue }
        return ["path": path, "mimeType": mime]
      case let image as UIImage:
        guard let png = image.pngData(), let path = saved(png, fileExtension: "png") else {
          continue
        }
        return ["path": path, "mimeType": "image/png"]
      default:
        continue
      }
    }
    return nil
  }

  // [data] in a folder of its own in the temporary directory, which the
  // system clears; the host reads the file from there.
  private static func saved(_ data: Data, fileExtension: String) -> String? {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("rich_clipboard", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = folder.appendingPathComponent("pasted.\(fileExtension)")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: file)
      return file.path
    } catch {
      return nil
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
