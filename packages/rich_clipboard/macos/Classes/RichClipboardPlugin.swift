import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

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
      let withMedia = (call.arguments as? [String: Any])?["media"] as? Bool ?? false
      let files = withMedia ? RichClipboardPlugin.files(on: pasteboard) : []
      // A file manager's copy carries the files' names as text, which is not
      // what was copied.
      let plain = files.isEmpty ? pasteboard.string(forType: .string) : nil
      let html = files.isEmpty ? pasteboard.string(forType: .html) : nil
      let media = !withMedia ? [] : files.isEmpty ? RichClipboardPlugin.image(on: pasteboard) : files
      // A type the clipboard does not hold is left out.
      var held: [String: Any] = [:]
      held["plain"] = plain
      held["html"] = html
      if !media.isEmpty {
        held["media"] = media
      }
      result(held.isEmpty ? nil : held)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // Files a file manager copied, as paths.
  private static func files(on pasteboard: NSPasteboard) -> [[String: Any]] {
    let urls =
      pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
      ) as? [URL] ?? []
    return urls.map { url in
      var file: [String: Any] = ["path": url.path]
      if let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
        file["mimeType"] = mime
      }
      return file
    }
  }

  // The image data, in the first form the pasteboard has. Asked for only
  // when there are no files: a Finder copy also carries the file's icon as
  // an image, which is not what was copied.
  private static func image(on pasteboard: NSPasteboard) -> [[String: Any]] {
    let gif = NSPasteboard.PasteboardType("com.compuserve.gif")
    let jpeg = NSPasteboard.PasteboardType("public.jpeg")
    if let data = pasteboard.data(forType: gif) {
      return [["bytes": FlutterStandardTypedData(bytes: data), "mimeType": "image/gif"]]
    }
    if let data = pasteboard.data(forType: .png) {
      return [["bytes": FlutterStandardTypedData(bytes: data), "mimeType": "image/png"]]
    }
    if let data = pasteboard.data(forType: jpeg) {
      return [["bytes": FlutterStandardTypedData(bytes: data), "mimeType": "image/jpeg"]]
    }
    if let tiff = pasteboard.data(forType: .tiff),
      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    {
      return [["bytes": FlutterStandardTypedData(bytes: png), "mimeType": "image/png"]]
    }
    return []
  }
}
