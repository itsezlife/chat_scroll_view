import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatCopyOrigin, ChatTextCopy;
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:content_model/content_model.dart' as model;
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/services.dart' show TextRange;
import 'package:flutter_md/flutter_md.dart';

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

  /// What the viewport copies, as rich text: a text selection with what its
  /// spans say ([selection]), a tapped code block as code ([code]).
  static model.RichText of(ChatTextCopy copy) => switch (copy) {
    ChatTextCopy(:final content?) => selection(content),
    ChatTextCopy(origin: ChatCopyOrigin.codeTap) => code(copy.plainText),
    _ => model.RichText.plain(copy.plainText),
  };

  /// [code] as code, as a code block's Copy gives it.
  static model.RichText code(String code) => code.isEmpty
      ? model.RichText.empty
      : model.RichText(code, [Entity(0, code.length, EntityKind.code)]);

  /// The text a text selection covers, with what the selected spans say:
  /// their styles, links, and custom emoji selected whole. Messages are a
  /// blank line apart and blocks a line apart, as the plain copy is; a quote
  /// is quoted and a code block is code.
  ///
  /// A custom emoji cut through by the selection keeps only the text it
  /// covers, and what entities cannot hold together falls back to the text.
  static model.RichText selection(MarkdownSelectedContent content) {
    final out = _RichTextBuilder();
    for (final document in content.documents) {
      if (!out.isEmpty) out.text('\n\n');
      var first = true;
      for (final selected in document.blocks) {
        if (!first) out.text('\n');
        first = false;
        _block(out, selected.block, selected.renderedRange);
      }
    }
    return out.build();
  }

  static void _block(_RichTextBuilder out, MD$Block block, TextRange range) {
    switch (block) {
      case MD$Paragraph(:final spans) || MD$Heading(:final spans):
        _spans(out, spans, range);
      case MD$Quote(:final spans, :final blocks):
        final start = out.length;
        if (blocks.isEmpty) {
          _spans(out, spans, range);
        } else {
          out.text(_slice(markdownBlockRenderedText(block), range));
        }
        out.entity(start, EntityKind.quote);
      case MD$Code(:final text):
        final start = out.length;
        out.text(_slice(text, range));
        out.entity(start, EntityKind.code);
      case _:
        out.text(_slice(markdownBlockRenderedText(block), range));
    }
  }

  // The selected part of each span, with the entities its style and target
  // say. Spans follow each other in the block's rendered text.
  static void _spans(
    _RichTextBuilder out,
    List<MD$Span> spans,
    TextRange range,
  ) {
    var at = 0;
    for (final span in spans) {
      final from = at;
      final to = at += span.text.length;
      final cut = math.max(range.start, from);
      final end = math.min(range.end, to);
      if (cut >= end) continue;
      final start = out.length;
      out.text(span.text.substring(cut - from, end - from));
      final style = span.style;
      final url = span.extra?['url'];
      if (style.contains(MD$Style.image)) {
        // A custom emoji is one thing: only a whole one is itself.
        final key = url is String ? ContentKey.tryParse(url) : null;
        if (key != null && cut == from && end == to) {
          out.entity(start, EntityKind.inlineContent(key));
        }
        continue;
      }
      if (style.contains(MD$Style.bold)) out.entity(start, EntityKind.bold);
      if (style.contains(MD$Style.italic)) out.entity(start, EntityKind.italic);
      if (style.contains(MD$Style.underline)) {
        out.entity(start, EntityKind.underline);
      }
      if (style.contains(MD$Style.strikethrough)) {
        out.entity(start, EntityKind.strike);
      }
      if (style.contains(MD$Style.spoiler)) {
        out.entity(start, EntityKind.spoiler);
      }
      if (style.contains(MD$Style.monospace)) {
        out.entity(start, EntityKind.code);
      }
      if (style.contains(MD$Style.link) && url is String) {
        out.entity(start, EntityKind.link(url));
      }
    }
  }

  static String _slice(String text, TextRange range) => text.substring(
    range.start.clamp(0, text.length),
    range.end.clamp(range.start.clamp(0, text.length), text.length),
  );
}

/// Text and entities appended in order, built into a rich text.
final class _RichTextBuilder {
  final _text = StringBuffer();
  final _entities = <Entity>[];

  int get length => _text.length;

  bool get isEmpty => _text.isEmpty;

  void text(String text) => _text.write(text);

  // An entity from [start] to what has been written since.
  void entity(int start, EntityKind kind) {
    if (_text.length > start) {
      _entities.add(Entity(start, _text.length - start, kind));
    }
  }

  // The text with its entities; entities that cannot coexist are dropped,
  // the styles first.
  model.RichText build() {
    final plain = _text.toString();
    for (final keep in <bool Function(Entity)>[
      (_) => true,
      (entity) =>
          entity.kind is! EntityKind$Style || entity.kind == EntityKind.quote,
    ]) {
      try {
        return model.RichText(plain, [
          for (final entity in _entities)
            if (keep(entity)) entity,
        ]);
        // RichText reports entities that cannot coexist as an ArgumentError
        // and offers no way to ask first.
        // ignore: avoid_catching_errors
      } on ArgumentError {
        continue;
      }
    }
    return model.RichText.plain(plain);
  }
}
