import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatCopyOrigin, ChatTextCopy;
import 'package:content_model/content_model.dart' as model;
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/services.dart' show TextRange;
import 'package:flutter_md/flutter_md.dart';

/// What the chat puts on the clipboard for each thing a user copies, as rich
/// text, so a paste into the composer brings back what was copied (ADR 032).
abstract final class ChatCopy {
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
    ChatTextCopy(origin: ChatCopyOrigin.codeTap) => code(
      copy.plainText,
      language: copy.codeLanguage,
    ),
    _ => model.RichText.plain(copy.plainText),
  };

  /// Tapped [code]: a block of code (it names a [language] or spans lines)
  /// as a code block, a snippet as inline code.
  static model.RichText code(String code, {String? language}) {
    if (code.isEmpty) return model.RichText.empty;
    final block = language != null || code.contains('\n');
    return model.RichText(code, [
      Entity(
        0,
        code.length,
        block
            ? EntityKind.codeBlock(language: _language(language))
            : EntityKind.code,
      ),
    ]);
  }

  // A language a code block can carry, or none.
  static String? _language(String? name) =>
      name != null && RegExp(r'^[A-Za-z0-9+#._-]+$').hasMatch(name)
      ? name
      : null;

  /// The text a text selection covers, with what the selected spans say:
  /// their styles, links, and custom emoji selected whole. Messages are a
  /// blank line apart and blocks a line apart, as the plain copy is; a quote
  /// is quoted and a fenced block is a code block in its language.
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
      case MD$Code(:final text, :final language):
        final start = out.length;
        out.text(_slice(text, range));
        out.entity(start, EntityKind.codeBlock(language: _language(language)));
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
      final whole = cut == from && end == to;
      final isEmoji = style.contains(MD$Style.image);
      if (isEmoji) {
        // A custom emoji is one thing: only a whole one is itself. What is
        // copied is its alt text (the span's text), also when it is not.
        final key = url is String ? ContentKey.tryParse(url) : null;
        if (key != null && whole) {
          out.entity(start, EntityKind.inlineContent(key));
        }
        // The emoji still takes the styles around it. Skipping them here
        // (as this once did, with a `continue`) cut a spoiler in two around
        // its emoji, which then pasted unhidden.
      }
      if (style.contains(MD$Style.mention)) {
        // The engine marks mentions with a style bit of their own and gives
        // them no URL. Like an emoji, a mention is whole or it is its text:
        // half of a name does not point at the user.
        if (whole) _mention(out, start, span.extra);
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
      // Code and a link cannot hold the emoji's atom (a link's `url` is the
      // emoji's key here), so an emoji takes neither.
      if (isEmoji) continue;
      if (style.contains(MD$Style.monospace)) {
        out.entity(start, EntityKind.code);
      }
      if (style.contains(MD$Style.link) && url is String) {
        out.entity(start, EntityKind.link(url));
      }
    }
  }

  // The entity a mention-class span's `extra` names: `mention:id`,
  // `username:name` or `hashtag:tag`.
  static void _mention(
    _RichTextBuilder out,
    int start,
    Map<String, Object?>? extra,
  ) {
    final name = extra?['name'];
    final kind = switch (extra?['scheme']) {
      'mention' when extra?['id'] is String => EntityKind.mention(
        extra!['id']! as String,
      ),
      'username' when name is String => EntityKind.username(name),
      'hashtag' when name is String => EntityKind.hashtag(name),
      _ => null,
    };
    if (kind != null) out.entity(start, kind);
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

  // An entity from [start] to what has been written since. A text style that
  // continues the previous one (the same style on the next span) extends it:
  // left as two, each would give up the whitespace at its edges and the
  // style would lose the space between the spans (`||b ` + emoji + ` c||`
  // would hide `b`, the emoji and `c`, but not the spaces).
  void entity(int start, EntityKind kind) {
    if (_text.length <= start) return;
    if (kind.isTextStyle) {
      final at = _entities.lastIndexWhere((e) => e.kind == kind);
      if (at >= 0 && _entities[at].end == start) {
        final joined = _entities[at];
        _entities[at] = Entity(
          joined.offset,
          _text.length - joined.offset,
          kind,
        );
        return;
      }
    }
    _entities.add(Entity(start, _text.length - start, kind));
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
