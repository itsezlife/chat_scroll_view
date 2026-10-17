#include "include/rich_clipboard/rich_clipboard_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "rich_clipboard_plugin.h"

void RichClipboardPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  rich_clipboard::RichClipboardPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
