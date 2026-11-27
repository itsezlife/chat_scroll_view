import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // A chat that blocks capture: the window shows blank in screenshots and
    // recordings while its sharing type is none.
    let system = FlutterMethodChannel(
      name: "chat_scroll_view_example/system",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    system.setMethodCallHandler { [weak self] call, result in
      guard call.method == "secureWindow" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let secure = (call.arguments as? Bool) ?? false
      self?.sharingType = secure ? .none : .readOnly
      result(nil)
    }

    super.awakeFromNib()
  }
}
