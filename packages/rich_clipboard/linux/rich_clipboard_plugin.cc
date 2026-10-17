#include "include/rich_clipboard/rich_clipboard_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

// The Linux side of rich_clipboard: the clipboard offers the HTML and the
// plain text under their targets, so each reader takes the richest it knows.

#define RICH_CLIPBOARD_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), rich_clipboard_plugin_get_type(), \
                              RichClipboardPlugin))

struct _RichClipboardPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(RichClipboardPlugin, rich_clipboard_plugin, g_object_get_type())

static const char kHtmlTarget[] = "text/html";

// --- Writing ---

// What the clipboard serves while this app owns it.
typedef struct {
  gchar* plain;
  gchar* html;
} Offer;

enum { kInfoHtml = 1, kInfoText = 2 };

static void offer_get(GtkClipboard* clipboard, GtkSelectionData* selection,
                      guint info, gpointer data) {
  Offer* offer = static_cast<Offer*>(data);
  if (info == kInfoHtml) {
    gtk_selection_data_set(selection, gtk_selection_data_get_target(selection),
                           8, reinterpret_cast<const guchar*>(offer->html),
                           strlen(offer->html));
  } else {
    gtk_selection_data_set_text(selection, offer->plain, -1);
  }
}

static void offer_clear(GtkClipboard* clipboard, gpointer data) {
  Offer* offer = static_cast<Offer*>(data);
  g_free(offer->plain);
  g_free(offer->html);
  g_free(offer);
}

static FlMethodResponse* write_clipboard(FlValue* args) {
  FlValue* plain = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                       ? fl_value_lookup_string(args, "plain")
                       : nullptr;
  FlValue* html = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                      ? fl_value_lookup_string(args, "html")
                      : nullptr;
  if (plain == nullptr || html == nullptr ||
      fl_value_get_type(plain) != FL_VALUE_TYPE_STRING ||
      fl_value_get_type(html) != FL_VALUE_TYPE_STRING) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-arguments", "write takes plain and html", nullptr));
  }

  GtkTargetList* list = gtk_target_list_new(nullptr, 0);
  gtk_target_list_add(list, gdk_atom_intern_static_string(kHtmlTarget), 0,
                      kInfoHtml);
  gtk_target_list_add_text_targets(list, kInfoText);
  gint count = 0;
  GtkTargetEntry* targets = gtk_target_table_new_from_list(list, &count);
  gtk_target_list_unref(list);

  Offer* offer = g_new0(Offer, 1);
  offer->plain = g_strdup(fl_value_get_string(plain));
  offer->html = g_strdup(fl_value_get_string(html));
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gboolean set = gtk_clipboard_set_with_data(clipboard, targets, count,
                                             offer_get, offer_clear, offer);
  gtk_target_table_free(targets, count);
  if (!set) {
    offer_clear(clipboard, offer);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "unavailable", "the clipboard could not be written", nullptr));
  }
  // A clipboard manager may keep the text after the app exits.
  gtk_clipboard_set_can_store(clipboard, nullptr, 0);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

// --- Reading ---

// A read in flight: the HTML is asked for first, then the text, and the call
// is answered when both are in.
typedef struct {
  FlMethodCall* call;
  gchar* html;
} Read;

// Clipboard HTML from some apps (Firefox) is UTF-16 with a byte order mark.
static gchar* html_text(GtkSelectionData* selection) {
  gint length = 0;
  const guchar* data = gtk_selection_data_get_data_with_length(selection, &length);
  if (data == nullptr || length <= 0) return nullptr;
  if (length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
    return g_utf16_to_utf8(reinterpret_cast<const gunichar2*>(data + 2),
                           (length - 2) / 2, nullptr, nullptr, nullptr);
  }
  return g_strndup(reinterpret_cast<const gchar*>(data), length);
}

static void text_received(GtkClipboard* clipboard, const gchar* text,
                          gpointer data) {
  Read* read = static_cast<Read*>(data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (text == nullptr && read->html == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    // A type the clipboard does not hold is left out.
    g_autoptr(FlValue) held = fl_value_new_map();
    if (text != nullptr) {
      fl_value_set_string_take(held, "plain", fl_value_new_string(text));
    }
    if (read->html != nullptr) {
      fl_value_set_string_take(held, "html", fl_value_new_string(read->html));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(held));
  }
  fl_method_call_respond(read->call, response, nullptr);
  g_object_unref(read->call);
  g_free(read->html);
  g_free(read);
}

static void html_received(GtkClipboard* clipboard, GtkSelectionData* selection,
                          gpointer data) {
  Read* read = static_cast<Read*>(data);
  read->html = selection != nullptr ? html_text(selection) : nullptr;
  gtk_clipboard_request_text(clipboard, text_received, read);
}

static void read_clipboard(FlMethodCall* method_call) {
  Read* read = g_new0(Read, 1);
  read->call = FL_METHOD_CALL(g_object_ref(method_call));
  gtk_clipboard_request_contents(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD),
                                 gdk_atom_intern_static_string(kHtmlTarget),
                                 html_received, read);
}

// --- Plugin ---

static void rich_clipboard_plugin_handle_method_call(
    RichClipboardPlugin* self, FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, "read") == 0) {
    read_clipboard(method_call);
    return;
  }
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "write") == 0) {
    response = write_clipboard(fl_method_call_get_args(method_call));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void rich_clipboard_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(rich_clipboard_plugin_parent_class)->dispose(object);
}

static void rich_clipboard_plugin_class_init(RichClipboardPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = rich_clipboard_plugin_dispose;
}

static void rich_clipboard_plugin_init(RichClipboardPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  RichClipboardPlugin* plugin = RICH_CLIPBOARD_PLUGIN(user_data);
  rich_clipboard_plugin_handle_method_call(plugin, method_call);
}

void rich_clipboard_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  RichClipboardPlugin* plugin = RICH_CLIPBOARD_PLUGIN(
      g_object_new(rich_clipboard_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "rich_clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
