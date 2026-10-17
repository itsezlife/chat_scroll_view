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

// A read in flight. With media, the files a file manager copied are asked
// for first, and answer alone: their text is their names, not what was
// copied. Otherwise the HTML, then the text, then (with media) an image; the
// call is answered when all are in.
typedef struct {
  FlMethodCall* call;
  gboolean with_media;
  gchar* html;
  gchar* plain;
  FlValue* media;
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

static void read_answer(Read* read) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gboolean has_media = fl_value_get_length(read->media) > 0;
  if (read->plain == nullptr && read->html == nullptr && !has_media) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    // A type the clipboard does not hold is left out.
    g_autoptr(FlValue) held = fl_value_new_map();
    if (read->plain != nullptr) {
      fl_value_set_string_take(held, "plain", fl_value_new_string(read->plain));
    }
    if (read->html != nullptr) {
      fl_value_set_string_take(held, "html", fl_value_new_string(read->html));
    }
    if (has_media) {
      fl_value_set_string(held, "media", read->media);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(held));
  }
  fl_method_call_respond(read->call, response, nullptr);
  g_object_unref(read->call);
  g_free(read->html);
  g_free(read->plain);
  fl_value_unref(read->media);
  g_free(read);
}

// An image, saved as PNG.
static void image_received(GtkClipboard* clipboard, GdkPixbuf* pixbuf,
                           gpointer data) {
  Read* read = static_cast<Read*>(data);
  gchar* png = nullptr;
  gsize size = 0;
  if (pixbuf != nullptr &&
      gdk_pixbuf_save_to_buffer(pixbuf, &png, &size, "png", nullptr, nullptr)) {
    g_autoptr(FlValue) image = fl_value_new_map();
    fl_value_set_string_take(
        image, "bytes",
        fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(png), size));
    fl_value_set_string_take(image, "mimeType", fl_value_new_string("image/png"));
    fl_value_append(read->media, image);
    g_free(png);
  }
  read_answer(read);
}

static void text_received(GtkClipboard* clipboard, const gchar* text,
                          gpointer data) {
  Read* read = static_cast<Read*>(data);
  read->plain = text != nullptr ? g_strdup(text) : nullptr;
  if (read->with_media) {
    gtk_clipboard_request_image(clipboard, image_received, read);
  } else {
    read_answer(read);
  }
}

static void html_received(GtkClipboard* clipboard, GtkSelectionData* selection,
                          gpointer data) {
  Read* read = static_cast<Read*>(data);
  read->html = selection != nullptr ? html_text(selection) : nullptr;
  gtk_clipboard_request_text(clipboard, text_received, read);
}

static void request_html(GtkClipboard* clipboard, Read* read) {
  gtk_clipboard_request_contents(clipboard,
                                 gdk_atom_intern_static_string(kHtmlTarget),
                                 html_received, read);
}

// Files a file manager copied (its URI list), as paths.
static void uris_received(GtkClipboard* clipboard, gchar** uris,
                          gpointer data) {
  Read* read = static_cast<Read*>(data);
  for (gchar** uri = uris; uri != nullptr && *uri != nullptr; uri++) {
    g_autofree gchar* path = g_filename_from_uri(*uri, nullptr, nullptr);
    if (path == nullptr) continue;
    g_autoptr(FlValue) file = fl_value_new_map();
    fl_value_set_string_take(file, "path", fl_value_new_string(path));
    fl_value_append(read->media, file);
  }
  if (fl_value_get_length(read->media) > 0) {
    read_answer(read);
  } else {
    request_html(clipboard, read);
  }
}

static void read_clipboard(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* media = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                       ? fl_value_lookup_string(args, "media")
                       : nullptr;
  Read* read = g_new0(Read, 1);
  read->call = FL_METHOD_CALL(g_object_ref(method_call));
  read->with_media = media != nullptr &&
                     fl_value_get_type(media) == FL_VALUE_TYPE_BOOL &&
                     fl_value_get_bool(media);
  read->media = fl_value_new_list();
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  if (read->with_media) {
    gtk_clipboard_request_uris(clipboard, uris_received, read);
  } else {
    request_html(clipboard, read);
  }
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
