import 'package:content_model/content_model.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// The conversion between [RichText] and the HTML the clipboard carries.
///
/// HTML is the rich form a copy puts next to the plain text (ADR 032): what a
/// paste into the app reads back, and what other apps (browsers, editors,
/// mail) read as formatted text.
///
/// ## Writing
///
/// [encode] is lossless for every entity: decoding what it wrote gives the
/// same value.
///
/// | Entity | HTML |
/// | --- | --- |
/// | bold, italic, underline, strike | `<b>`, `<i>`, `<u>`, `<s>` |
/// | spoiler | `<tg-spoiler>` (the reference desktop client's element) |
/// | code | `<code>` |
/// | quote | `<blockquote>` |
/// | link | `<a href>` |
/// | mention | `<span data-mention-id>` over its text |
/// | inline content | `<span data-content-key>` over its alternative text |
///
/// Mentions and inline content have no HTML element, so other apps read
/// their text; the attributes are for this app. Every line break is a
/// `<br>`, quotes' included: a block's implied break cannot say an empty line
/// at the end of the text, so the decoder takes no breaks from blocks in this
/// HTML (another app may show an empty line after a quote). The whole is a
/// `<span>`
/// marked `data-rich-text` with `white-space: pre-wrap`, so other apps keep
/// spaces and tabs, and [decode] knows the HTML is its own.
///
/// ## Reading
///
/// [decode] reads its own HTML exactly, and other apps' HTML as far as
/// entities can say it:
///
/// - **Elements:** `b strong h1-h6`, `i em`, `u ins`, `s strike del`, `code tt
///   kbd samp pre`, `blockquote details`, `a href`, the reference clients'
///   `spoiler`, `tg-spoiler`, `class="tg-spoiler"` and
///   `<animated-emoji data-document-id>` (inline content of a document key).
/// - **CSS:** `font-weight`, `font-style` and `text-decoration`, which also
///   switch a style off (a whole copy from a document editor sits in a `<b>`
///   that is not bold).
/// - **Lines:** `br` breaks a line, block elements (paragraphs, list items,
///   headings, quotes) start and end one, whitespace collapses as a browser
///   collapses it, except in `pre` and `white-space: pre*`.
/// - **Links:** kept only with a scheme a user can follow (`http`, `https`,
///   `mailto`, `tel`, `tg`, `ftp`); others keep their text.
/// - **Whole-text styles:** a style that covers all of another app's text is
///   dropped, as the reference desktop client drops it: pasting a bold
///   paragraph from a web page should not make the message bold.
///
/// [decode] never throws: what cannot be read keeps its text, and entities
/// that cannot coexist are dropped, styles first.
abstract final class RichTextHtml {
  /// The attribute that marks HTML [encode] wrote.
  static const String ownMarker = 'data-rich-text';

  /// The attribute that carries a mention's id.
  static const String mentionAttribute = 'data-mention-id';

  /// The attribute that carries inline content's [ContentKey.encoded].
  static const String contentKeyAttribute = 'data-content-key';

  /// [text] as HTML; see [RichTextHtml].
  static String encode(RichText text) => _Encoder(text).run();

  /// The rich text [source] describes; see [RichTextHtml].
  static RichText decode(String source) {
    final dom.Document document;
    try {
      document = html.parse(source);
    } on Object {
      return RichText.plain(source);
    }
    return _Decoder(document).run();
  }
}

// --- Writing ---------------------------------------------------------------

final class _Encoder {
  _Encoder(this._text);

  final RichText _text;
  final _out = StringBuffer();

  // The entities whose elements are open, outermost first.
  final _open = <Entity>[];

  String run() {
    _out.write(
      '<span ${RichTextHtml.ownMarker}="1" style="white-space:pre-wrap">',
    );
    final plain = _text.plain;
    final cuts = <int>{
      0,
      plain.length,
      for (final entity in _text.entities) ...[entity.offset, entity.end],
    }.toList()..sort();
    for (var i = 0; i + 1 < cuts.length; i++) {
      final start = cuts[i];
      final end = cuts[i + 1];
      _openOnly(_activeAt(start));
      for (var at = start; at < end; at++) {
        final unit = plain.codeUnitAt(at);
        if (unit == 0x0A) {
          _out.write('<br>');
        } else {
          _out.write(_escape(String.fromCharCode(unit)));
        }
      }
    }
    _openOnly(const []);
    _out.write('</span>');
    return _out.toString();
  }

  // The entities that cover [at], in the order their elements nest: a quote
  // outermost, then the one that started first, a longer one before a
  // shorter one; over one range, a link outside styles, styles outside code,
  // code outside an atom, because the decoder reads nothing inside code
  // or an atom.
  List<Entity> _activeAt(int at) =>
      [
        for (final entity in _text.entities)
          if (entity.offset <= at && at < entity.end) entity,
      ]..sort((a, b) {
        final quote = _depthOf(a).compareTo(_depthOf(b));
        if (quote != 0 && (_depthOf(a) == 0 || _depthOf(b) == 0)) return quote;
        final start = a.offset.compareTo(b.offset);
        if (start != 0) return start;
        final end = b.end.compareTo(a.end);
        if (end != 0) return end;
        return quote;
      });

  // How deep an element sits among elements over one range.
  static int _depthOf(Entity entity) => switch (entity.kind) {
    EntityKind$Style(style: EntityStyle.quote) => 0,
    EntityKind$Link() => 1,
    EntityKind$Style(style: EntityStyle.code) => 3,
    EntityKind$Style() => 2,
    EntityKind$Mention() || EntityKind$InlineContent() => 4,
  };

  // Closes open elements down to the longest prefix [wanted] shares with
  // them, then opens the rest of [wanted].
  void _openOnly(List<Entity> wanted) {
    var shared = 0;
    while (shared < _open.length &&
        shared < wanted.length &&
        identical(_open[shared], wanted[shared])) {
      shared++;
    }
    while (_open.length > shared) {
      _out.write('</${_tagOf(_open.removeLast())}>');
    }
    for (final entity in wanted.skip(shared)) {
      _out.write(_openTagOf(entity));
      _open.add(entity);
    }
  }

  static String _tagOf(Entity entity) => switch (entity.kind) {
    EntityKind$Style(:final style) => switch (style) {
      EntityStyle.bold => 'b',
      EntityStyle.italic => 'i',
      EntityStyle.underline => 'u',
      EntityStyle.strike => 's',
      EntityStyle.spoiler => 'tg-spoiler',
      EntityStyle.code => 'code',
      EntityStyle.quote => 'blockquote',
    },
    EntityKind$Link() => 'a',
    EntityKind$Mention() || EntityKind$InlineContent() => 'span',
  };

  static String _openTagOf(Entity entity) => switch (entity.kind) {
    EntityKind$Link(:final url) => '<a href="${_escapeAttribute(url)}">',
    EntityKind$Mention(:final id) =>
      '<span ${RichTextHtml.mentionAttribute}="${_escapeAttribute(id)}">',
    EntityKind$InlineContent(:final key) =>
      '<span ${RichTextHtml.contentKeyAttribute}="${_escapeAttribute(key.encoded)}">',
    EntityKind$Style() => '<${_tagOf(entity)}>',
  };

  static String _escape(String char) => switch (char) {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    _ => char,
  };

  static String _escapeAttribute(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

// --- Reading ---------------------------------------------------------------

/// The formatting a text node inherits from its ancestors.
final class _Context {
  const _Context({
    this.styles = const {},
    this.link,
    this.preserveSpace = false,
    this.inAtom = false,
    this.inCode = false,
  });

  final Set<EntityStyle> styles;
  final String? link;
  final bool preserveSpace;

  // Inside a mention or inline content: nothing starts or ends inside one.
  final bool inAtom;

  // Inside code: code holds no other entity.
  final bool inCode;

  _Context copyWith({
    Set<EntityStyle>? styles,
    String? link,
    bool? preserveSpace,
    bool? inAtom,
    bool? inCode,
  }) => _Context(
    styles: styles ?? this.styles,
    link: link ?? this.link,
    preserveSpace: preserveSpace ?? this.preserveSpace,
    inAtom: inAtom ?? this.inAtom,
    inCode: inCode ?? this.inCode,
  );
}

final class _Decoder {
  _Decoder(this._document)
    : _own = _document.querySelector('[${RichTextHtml.ownMarker}]') != null;

  final dom.Document _document;

  // HTML [RichTextHtml.encode] wrote: kept exactly.
  final bool _own;

  final _text = StringBuffer();
  final _entities = <Entity>[];

  // A block ended or began: a line break goes in before the next text, if
  // any text follows and the last line is not already ended.
  bool _pendingBreak = false;

  static const _blocks = {
    'address', 'article', 'aside', 'blockquote', 'details', 'dd', 'div', //
    'dl', 'dt', 'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1',
    'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol',
    'p', 'pre', 'section', 'summary', 'table', 'tr', 'ul',
  };
  static const _skipped = {
    'head', 'script', 'style', 'template', 'noscript', 'title', 'img', //
  };
  static const _schemes = {'http', 'https', 'mailto', 'tel', 'tg', 'ftp'};

  RichText run() {
    final body = _document.body;
    if (body != null) _walkChildren(body, const _Context());
    _trimTrailingSpace();
    final plain = _text.toString();
    final runs = _joinedRuns();
    final entities = _own ? runs : _withoutWholeTextStyles(plain, runs);
    return _build(plain, entities);
  }

  // Text runs of one style or link that touch, as one entity. The value
  // trims a style to non-whitespace before it joins touching ones, so runs
  // split at a space (`<b>one <i>two</i></b>`) would otherwise stay apart.
  // Atoms and quotes are an element's whole range already.
  List<Entity> _joinedRuns() {
    final joined = <Entity>[];
    final open = <EntityKind, int>{};
    final sorted = [..._entities]..sort((a, b) => a.offset.compareTo(b.offset));
    for (final entity in sorted) {
      final kind = entity.kind;
      if (kind.isAtomic || kind == EntityKind.quote) {
        joined.add(entity);
        continue;
      }
      if (open[kind] case final index?
          when joined[index].end == entity.offset) {
        final previous = joined[index];
        joined[index] = Entity(
          previous.offset,
          entity.end - previous.offset,
          kind,
        );
        continue;
      }
      open[kind] = joined.length;
      joined.add(entity);
    }
    return joined;
  }

  void _walkChildren(dom.Node node, _Context context) {
    for (final child in node.nodes) {
      switch (child) {
        case dom.Text(:final data):
          _appendText(data, context);
        case dom.Element():
          _walkElement(child, context);
        case _:
          break;
      }
    }
  }

  void _walkElement(dom.Element element, _Context context) {
    final tag = element.localName ?? '';
    if (_skipped.contains(tag)) return;
    if (tag == 'br') {
      _breakLine();
      return;
    }
    // Our own HTML spells out every line break.
    final block = !_own && _blocks.contains(tag);
    if (block) _pendingBreak = _text.isNotEmpty;

    // An atom keeps its element's range: two equal custom emoji side by side
    // stay two.
    if (context.inAtom ? null : _atomOf(element) case final kind?) {
      final start = _flushedLength();
      _walkChildren(element, context.copyWith(inAtom: true));
      if (_text.length > start) {
        _entities.add(Entity(start, _text.length - start, kind));
      }
      if (block) _pendingBreak = true;
      return;
    }

    final quote = !context.inAtom && (tag == 'blockquote' || tag == 'details');
    final start = quote ? _flushedLength() : 0;
    _walkChildren(element, _contextOf(element, tag, context));
    if (quote && _text.length > start) {
      _entities.add(Entity(start, _text.length - start, EntityKind.quote));
    }
    if (block) _pendingBreak = true;
  }

  // The text length once a pending line break is written: where the next
  // text starts.
  int _flushedLength() {
    _flushBreak();
    return _text.length;
  }

  EntityKind? _atomOf(dom.Element element) {
    final attributes = element.attributes;
    if (attributes[RichTextHtml.contentKeyAttribute] case final encoded?) {
      if (ContentKey.tryParse(encoded) case final key?) {
        return EntityKind.inlineContent(key);
      }
    }
    if (attributes[RichTextHtml.mentionAttribute] case final id?
        when id.isNotEmpty) {
      return EntityKind.mention(id);
    }
    if (element.localName == 'animated-emoji') {
      if (attributes['data-document-id'] case final id? when id.isNotEmpty) {
        return EntityKind.inlineContent(ContentKey.document(id));
      }
    }
    return null;
  }

  _Context _contextOf(dom.Element element, String tag, _Context context) {
    if (context.inAtom) return context;
    final css = _declarations(element.attributes['style']);
    final whiteSpace = css['white-space'];
    final preserveSpace =
        tag == 'pre' ||
        (whiteSpace != null && whiteSpace.startsWith('pre')) ||
        context.preserveSpace;
    if (context.inCode) return context.copyWith(preserveSpace: preserveSpace);
    if (const {'code', 'tt', 'kbd', 'samp', 'pre'}.contains(tag)) {
      return context.copyWith(
        styles: {...context.styles, EntityStyle.code},
        preserveSpace: preserveSpace,
        inCode: true,
      );
    }
    final styles = {...context.styles};
    switch (tag) {
      case 'b' || 'strong' || 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        styles.add(EntityStyle.bold);
      case 'i' || 'em':
        styles.add(EntityStyle.italic);
      case 'u' || 'ins':
        styles.add(EntityStyle.underline);
      case 's' || 'strike' || 'del':
        styles.add(EntityStyle.strike);
      case 'spoiler' || 'tg-spoiler':
        styles.add(EntityStyle.spoiler);
    }
    if ((element.attributes['class'] ?? '').split(' ').contains('tg-spoiler') ||
        element.attributes['data-entity-type'] == 'MessageEntitySpoiler') {
      styles.add(EntityStyle.spoiler);
    }
    _applyCss(css, styles);
    return context.copyWith(
      styles: styles,
      link: tag == 'a' ? _linkOf(element) ?? context.link : context.link,
      preserveSpace: preserveSpace,
    );
  }

  static void _applyCss(Map<String, String> css, Set<EntityStyle> styles) {
    void set(EntityStyle style, {required bool on}) =>
        on ? styles.add(style) : styles.remove(style);
    if (css['font-weight'] case final weight?) {
      final numeric = int.tryParse(weight);
      set(
        EntityStyle.bold,
        on: weight == 'bold' || weight == 'bolder' || (numeric ?? 0) >= 600,
      );
    }
    if (css['font-style'] case final style?) {
      set(EntityStyle.italic, on: style == 'italic' || style == 'oblique');
    }
    final decoration = css['text-decoration-line'] ?? css['text-decoration'];
    if (decoration != null) {
      set(EntityStyle.underline, on: decoration.contains('underline'));
      set(EntityStyle.strike, on: decoration.contains('line-through'));
    }
  }

  static Map<String, String> _declarations(String? style) => {
    if (style != null)
      for (final declaration in style.split(';'))
        if (declaration.indexOf(':') case final colon when colon > 0)
          declaration.substring(0, colon).trim().toLowerCase(): declaration
              .substring(colon + 1)
              .trim()
              .toLowerCase(),
  };

  static String? _linkOf(dom.Element element) {
    final href = element.attributes['href']?.trim();
    if (href == null) return null;
    final colon = href.indexOf(':');
    if (colon <= 0) return null;
    return _schemes.contains(href.substring(0, colon).toLowerCase())
        ? href
        : null;
  }

  void _breakLine() {
    _flushBreak();
    _trimTrailingSpace();
    _text.write('\n');
  }

  // A block ends a line that is still open, and never adds an empty one.
  void _flushBreak() {
    if (!_pendingBreak) return;
    _pendingBreak = false;
    final text = _text.toString();
    if (text.isEmpty || text.endsWith('\n')) return;
    _trimTrailingSpace();
    _text.write('\n');
  }

  // Collapsed whitespace does not end a line (not in our own HTML, which
  // keeps every space).
  void _trimTrailingSpace() {
    if (_own) return;
    final text = _text.toString();
    final trimmed = text.replaceFirst(RegExp(r' +$'), '');
    if (trimmed.length == text.length) return;
    _text
      ..clear()
      ..write(trimmed);
    _clipEntitiesTo(trimmed.length);
  }

  void _clipEntitiesTo(int length) {
    for (var i = _entities.length - 1; i >= 0; i--) {
      final entity = _entities[i];
      if (entity.end <= length) continue;
      if (entity.offset >= length) {
        _entities.removeAt(i);
      } else {
        _entities[i] = Entity(
          entity.offset,
          length - entity.offset,
          entity.kind,
        );
      }
    }
  }

  void _appendText(String data, _Context context) {
    var text = data;
    if (!_own && !context.preserveSpace) {
      text = text.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');
      final current = _text.toString();
      final lineStart =
          current.isEmpty || current.endsWith('\n') || _pendingBreak;
      if (lineStart || current.endsWith(' ')) text = text.trimLeft();
      text = text.replaceAll(' ', ' ');
    }
    if (text.isEmpty) return;
    _flushBreak();
    final start = _text.length;
    _text.write(text);
    final end = _text.length;
    // Inside an atom the context is the atom's own: styles around it cover
    // it whole, and nothing inside it adds any.
    for (final style in context.styles) {
      _entities.add(Entity(start, end - start, EntityKind.style(style)));
    }
    if (context.link case final url?) {
      _entities.add(Entity(start, end - start, EntityKind.link(url)));
    }
  }

  // Another app's whole-text style says nothing about the part pasted: the
  // page was bold, not the words.
  List<Entity> _withoutWholeTextStyles(String plain, List<Entity> runs) {
    final trimmed = plain.trim();
    if (trimmed.isEmpty) return runs;
    final first = plain.indexOf(trimmed);
    final last = first + trimmed.length;
    final whole = <EntityKind>{};
    for (final kind in {for (final entity in runs) entity.kind}) {
      // Code, spoilers and quotes mean something even over all of it.
      if (kind is! EntityKind$Style ||
          !const {
            EntityStyle.bold,
            EntityStyle.italic,
            EntityStyle.underline,
            EntityStyle.strike,
          }.contains(kind.style)) {
        continue;
      }
      final covered = List.filled(plain.length, false);
      for (final entity in runs) {
        if (entity.kind != kind) continue;
        covered.fillRange(entity.offset, entity.end, true);
      }
      var all = true;
      for (var i = first; i < last; i++) {
        if (!covered[i] &&
            plain.codeUnitAt(i) != 0x20 &&
            plain.codeUnitAt(i) != 0x0A) {
          all = false;
          break;
        }
      }
      if (all) whole.add(kind);
    }
    return [
      for (final entity in runs)
        if (!whole.contains(entity.kind)) entity,
    ];
  }

  // The rich text, dropping entities until they fit: first the styles, then
  // links, then everything.
  static RichText _build(String plain, List<Entity> entities) {
    for (final keep in <bool Function(Entity)>[
      (_) => true,
      (entity) =>
          entity.kind is! EntityKind$Style || entity.kind == EntityKind.quote,
      (entity) => entity.kind.isAtomic,
    ]) {
      try {
        return RichText(plain, [
          for (final entity in entities)
            if (keep(entity)) entity,
        ]);
        // RichText reports entities that cannot coexist as an ArgumentError
        // and offers no way to ask first.
        // ignore: avoid_catching_errors
      } on ArgumentError {
        continue;
      }
    }
    return RichText.plain(plain);
  }
}
