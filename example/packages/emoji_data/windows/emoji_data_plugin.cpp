#include "emoji_data_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

namespace emoji_data {

namespace {

std::vector<bool> AllSupported(const std::vector<std::string>& source) {
  return std::vector<bool>(source.size(), true);
}

}  // namespace

void EmojiDataPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "emoji_data",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<EmojiDataPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

EmojiDataPlugin::EmojiDataPlugin() {}

EmojiDataPlugin::~EmojiDataPlugin() {}

void EmojiDataPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getSupportedEmojis") == 0) {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "Missing arguments");
      return;
    }

    auto source_it = args->find(flutter::EncodableValue("source"));
    if (source_it == args->end()) {
      result->Error("bad_args", "Missing source list");
      return;
    }

    const auto* source_list =
        std::get_if<flutter::EncodableList>(&source_it->second);
    if (source_list == nullptr) {
      result->Error("bad_args", "Source is not a list");
      return;
    }

    std::vector<std::string> source;
    source.reserve(source_list->size());
    for (const auto& value : *source_list) {
      if (const auto* glyph = std::get_if<std::string>(&value)) {
        source.push_back(*glyph);
      }
    }

    const auto supported = AllSupported(source);
    flutter::EncodableList encoded;
    encoded.reserve(supported.size());
    for (const bool is_supported : supported) {
      encoded.push_back(flutter::EncodableValue(is_supported));
    }
    result->Success(flutter::EncodableValue(encoded));
    return;
  }

  result->NotImplemented();
}

}  // namespace emoji_data
