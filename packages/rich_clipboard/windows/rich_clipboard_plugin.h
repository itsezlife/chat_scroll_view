#ifndef FLUTTER_PLUGIN_RICH_CLIPBOARD_PLUGIN_H_
#define FLUTTER_PLUGIN_RICH_CLIPBOARD_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace rich_clipboard {

// The Windows side of rich_clipboard: the clipboard holds the plain text
// (CF_UNICODETEXT) and the HTML (the registered "HTML Format", CF_HTML), so
// each reader takes the richest it knows.
class RichClipboardPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit RichClipboardPlugin(flutter::PluginRegistrarWindows *registrar);

  virtual ~RichClipboardPlugin();

  RichClipboardPlugin(const RichClipboardPlugin &) = delete;
  RichClipboardPlugin &operator=(const RichClipboardPlugin &) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  // The window the clipboard is opened for: with none, Windows takes the
  // clipboard from no owner and refuses the data written to it.
  HWND Owner() const;

  flutter::PluginRegistrarWindows *registrar_;
};

}  // namespace rich_clipboard

#endif  // FLUTTER_PLUGIN_RICH_CLIPBOARD_PLUGIN_H_
