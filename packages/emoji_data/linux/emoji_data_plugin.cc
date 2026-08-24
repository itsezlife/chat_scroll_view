#include "include/emoji_data/emoji_data_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <cstring>

#define EMOJI_DATA_PLUGIN(obj)                                              \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), emoji_data_plugin_get_type(), \
                              EmojiDataPlugin))

struct _EmojiDataPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(EmojiDataPlugin, emoji_data_plugin, g_object_get_type())

static FlMethodResponse* build_supported_response(FlValue* source) {
  if (fl_value_get_type(source) != FL_VALUE_TYPE_LIST) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad_args", "Source is not a list", nullptr));
  }

  const size_t length = fl_value_get_length(source);
  g_autoptr(FlValue) result = fl_value_new_list();
  for (size_t i = 0; i < length; i++) {
    fl_value_append_take(result, fl_value_new_bool(TRUE));
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void emoji_data_plugin_handle_method_call(
    EmojiDataPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getSupportedEmojis") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* source = fl_value_lookup_string(args, "source");
    if (source == nullptr) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad_args", "Missing source list", nullptr));
    } else {
      response = build_supported_response(source);
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void emoji_data_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(emoji_data_plugin_parent_class)->dispose(object);
}

static void emoji_data_plugin_class_init(EmojiDataPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = emoji_data_plugin_dispose;
}

static void emoji_data_plugin_init(EmojiDataPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  EmojiDataPlugin* plugin = EMOJI_DATA_PLUGIN(user_data);
  emoji_data_plugin_handle_method_call(plugin, method_call);
}

void emoji_data_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  EmojiDataPlugin* plugin = EMOJI_DATA_PLUGIN(
      g_object_new(emoji_data_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "emoji_data",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
