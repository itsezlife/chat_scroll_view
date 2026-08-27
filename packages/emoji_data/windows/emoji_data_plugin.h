#ifndef FLUTTER_PLUGIN_EMOJI_DATA_PLUGIN_H_
#define FLUTTER_PLUGIN_EMOJI_DATA_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace emoji_data {

class EmojiDataPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  EmojiDataPlugin();

  virtual ~EmojiDataPlugin();

  EmojiDataPlugin(const EmojiDataPlugin&) = delete;
  EmojiDataPlugin& operator=(const EmojiDataPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace emoji_data

#endif  // FLUTTER_PLUGIN_EMOJI_DATA_PLUGIN_H_
