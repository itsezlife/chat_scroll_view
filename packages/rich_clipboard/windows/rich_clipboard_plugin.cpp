#include "rich_clipboard_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <variant>

namespace rich_clipboard {

namespace {

UINT HtmlFormat() {
  static const UINT format = ::RegisterClipboardFormatW(L"HTML Format");
  return format;
}

std::wstring Utf16(const std::string &utf8) {
  if (utf8.empty()) return std::wstring();
  const int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                           static_cast<int>(utf8.size()),
                                           nullptr, 0);
  std::wstring wide(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), length);
  return wide;
}

std::string Utf8(const wchar_t *wide) {
  const int length =
      ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (length <= 1) return std::string();
  std::string utf8(length - 1, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8.data(), length, nullptr,
                        nullptr);
  return utf8;
}

// CF_HTML: a header of byte offsets into the UTF-8 that follows, which marks
// the whole document and the fragment that was copied.
std::string ToCfHtml(const std::string &fragment) {
  static const char kHeader[] =
      "Version:0.9\r\nStartHTML:%010d\r\nEndHTML:%010d\r\n"
      "StartFragment:%010d\r\nEndFragment:%010d\r\n";
  static const std::string kBefore = "<html><body>\r\n<!--StartFragment-->";
  static const std::string kAfter = "<!--EndFragment-->\r\n</body></html>";
  const int header = std::snprintf(nullptr, 0, kHeader, 0, 0, 0, 0);
  const int start_html = header;
  const int start_fragment = start_html + static_cast<int>(kBefore.size());
  const int end_fragment = start_fragment + static_cast<int>(fragment.size());
  const int end_html = end_fragment + static_cast<int>(kAfter.size());
  std::string out(header, '\0');
  std::snprintf(out.data(), header + 1, kHeader, start_html, end_html,
                start_fragment, end_fragment);
  return out + kBefore + fragment + kAfter;
}

// The document a CF_HTML block holds, without its header.
std::string FromCfHtml(const std::string &cf_html) {
  auto offset = [&](const char *name) -> long {
    const size_t at = cf_html.find(name);
    if (at == std::string::npos) return -1;
    return std::strtol(cf_html.c_str() + at + std::strlen(name), nullptr, 10);
  };
  const long start = offset("StartHTML:");
  const long end = offset("EndHTML:");
  if (start >= 0 && end > start &&
      static_cast<size_t>(end) <= cf_html.size()) {
    return cf_html.substr(start, end - start);
  }
  // Some writers leave the offsets at -1: the document starts at its first
  // tag.
  const size_t tag = cf_html.find('<');
  return tag == std::string::npos ? std::string() : cf_html.substr(tag);
}

// Another app may hold the clipboard open for a moment.
bool OpenClipboardFor(HWND owner) {
  for (int attempt = 0; attempt < 5; attempt++) {
    if (::OpenClipboard(owner)) return true;
    ::Sleep(5);
  }
  return false;
}

bool Put(UINT format, const void *bytes, size_t size) {
  HGLOBAL memory = ::GlobalAlloc(GMEM_MOVEABLE, size);
  if (memory == nullptr) return false;
  void *target = ::GlobalLock(memory);
  if (target == nullptr) {
    ::GlobalFree(memory);
    return false;
  }
  std::memcpy(target, bytes, size);
  ::GlobalUnlock(memory);
  if (::SetClipboardData(format, memory) == nullptr) {
    ::GlobalFree(memory);
    return false;
  }
  return true;
}

std::optional<std::string> HeldHtml() {
  if (!::IsClipboardFormatAvailable(HtmlFormat())) return std::nullopt;
  HANDLE handle = ::GetClipboardData(HtmlFormat());
  if (handle == nullptr) return std::nullopt;
  const char *bytes = static_cast<const char *>(::GlobalLock(handle));
  if (bytes == nullptr) return std::nullopt;
  const std::string cf_html(bytes, ::strnlen(bytes, ::GlobalSize(handle)));
  ::GlobalUnlock(handle);
  return FromCfHtml(cf_html);
}

std::optional<std::string> HeldText() {
  if (!::IsClipboardFormatAvailable(CF_UNICODETEXT)) return std::nullopt;
  HANDLE handle = ::GetClipboardData(CF_UNICODETEXT);
  if (handle == nullptr) return std::nullopt;
  const wchar_t *wide = static_cast<const wchar_t *>(::GlobalLock(handle));
  if (wide == nullptr) return std::nullopt;
  std::string text = Utf8(wide);
  ::GlobalUnlock(handle);
  return text;
}

}  // namespace

// static
void RichClipboardPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "rich_clipboard",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<RichClipboardPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

RichClipboardPlugin::RichClipboardPlugin(
    flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {}

RichClipboardPlugin::~RichClipboardPlugin() {}

HWND RichClipboardPlugin::Owner() const {
  flutter::FlutterView *view = registrar_->GetView();
  return view == nullptr ? nullptr
                         : ::GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void RichClipboardPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string &method = method_call.method_name();
  if (method == "write") {
    const auto *arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    const std::string *plain = nullptr;
    const std::string *html = nullptr;
    if (arguments != nullptr) {
      auto plain_entry = arguments->find(flutter::EncodableValue("plain"));
      auto html_entry = arguments->find(flutter::EncodableValue("html"));
      if (plain_entry != arguments->end()) {
        plain = std::get_if<std::string>(&plain_entry->second);
      }
      if (html_entry != arguments->end()) {
        html = std::get_if<std::string>(&html_entry->second);
      }
    }
    if (plain == nullptr || html == nullptr) {
      result->Error("bad-arguments", "write takes plain and html");
      return;
    }
    if (!OpenClipboardFor(Owner())) {
      result->Error("unavailable", "the clipboard could not be opened");
      return;
    }
    ::EmptyClipboard();
    const std::wstring wide = Utf16(*plain);
    const std::string cf_html = ToCfHtml(*html);
    const bool written =
        Put(CF_UNICODETEXT, wide.c_str(), (wide.size() + 1) * sizeof(wchar_t)) &&
        Put(HtmlFormat(), cf_html.c_str(), cf_html.size() + 1);
    ::CloseClipboard();
    if (!written) {
      result->Error("unavailable", "the clipboard could not be written");
      return;
    }
    result->Success();
  } else if (method == "read") {
    if (!OpenClipboardFor(Owner())) {
      result->Error("unavailable", "the clipboard could not be opened");
      return;
    }
    const std::optional<std::string> html = HeldHtml();
    const std::optional<std::string> plain = HeldText();
    ::CloseClipboard();
    if (!html && !plain) {
      result->Success();
      return;
    }
    // A type the clipboard does not hold is left out.
    flutter::EncodableMap held;
    if (plain) {
      held[flutter::EncodableValue("plain")] = flutter::EncodableValue(*plain);
    }
    if (html) {
      held[flutter::EncodableValue("html")] = flutter::EncodableValue(*html);
    }
    result->Success(flutter::EncodableValue(held));
  } else {
    result->NotImplemented();
  }
}

}  // namespace rich_clipboard
