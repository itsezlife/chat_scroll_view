import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:content_model/content_model.dart' as model;
import 'package:content_model/content_model.dart' hide RichText;

/// What the chat puts on the clipboard for each thing a user copies, as rich
/// text, so a paste into the composer brings back what was copied (ADR 032).
abstract final class ChatCopy {
  /// The messages whose markdown bodies are [bodies], in order, a blank line
  /// apart, as the reference mobile client joins a copy of several.
  static model.RichText messages(Iterable<String> bodies) {
    var joined = model.RichText.empty;
    for (final body in bodies) {
      if (body.isEmpty) continue;
      final text = ChatBodyMarkdown.decode(body);
      if (!joined.isEmpty) {
        joined = joined.insert(
          joined.length,
          const model.RichText.plain('\n\n'),
        );
      }
      joined = joined.insert(joined.length, text);
    }
    return joined;
  }

  /// Inline content [key] over [alternativeText], the text other apps
  /// paste; a unicode emoji is its own text.
  static model.RichText content(ContentKey key, String alternativeText) =>
      switch (key) {
        ContentKey$Unicode() => model.RichText.plain(alternativeText),
        _ => model.RichText(alternativeText, [
          Entity(0, alternativeText.length, EntityKind.inlineContent(key)),
        ]),
      };

  /// [code] as code, as a code block's Copy gives it.
  static model.RichText code(String code) => code.isEmpty
      ? model.RichText.empty
      : model.RichText(code, [Entity(0, code.length, EntityKind.code)]);
}
