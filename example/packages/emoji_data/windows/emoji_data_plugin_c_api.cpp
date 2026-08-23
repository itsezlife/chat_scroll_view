#include "include/emoji_data/emoji_data_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "emoji_data_plugin.h"

void EmojiDataPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  emoji_data::EmojiDataPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
