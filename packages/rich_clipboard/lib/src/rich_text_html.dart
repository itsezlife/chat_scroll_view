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
/// | code block | `<pre>`, `<pre lang>` with a language |
/// | quote | `<blockquote>` |
/// | link | `<a href>` |
/// | username, hashtag | `<a href="username:name">`, `<a href="hashtag:tag">` |
/// | list item | `<li>` in a `<ul>` or `<ol>`, nested a level per depth |
/// | mention | `<span data-mention-id>` over its text |
/// | inline content | `<span data-content-key>` over its alternative text |
///
/// Mentions and inline content have no HTML element, so other apps read
/// their text; the attributes are for this app. A username or hashtag is a
/// link to a scheme no other app follows. The line break between two
/// consecutive items is the `</li><li>` itself, not a `<br>`: a `<br>` inside
/// a list shows as an empty line in other apps. Lists are the one place a block
/// gives the decoder a line break in this app's own HTML. Every line break is a
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
///   kbd samp`, `blockquote details`, `a href`, `ul ol li` as list items (an
///   item is the text of one `li` up to a list nested in it, and its depth is
///   how many lists enclose it, at most three), `pre` as a code block (its
///   language from `lang`, `language`, `lng`, `data-language` or a
///   `language-` class of its `code`, as code sites write it), the reference
///   clients'
///   `spoiler`, `tg-spoiler`, `class="tg-spoiler"` and
///   `<animated-emoji data-document-id>` (inline content of a document key).
/// - **CSS:** `font-weight`, `font-style` and `text-decoration`, which also
///   switch a style off (a whole copy from a document editor sits in a `<b>`
///   that is not bold).
/// - **Lines:** `br` breaks a line, block elements (paragraphs, list items,
///   headings, quotes) start and end one, whitespace collapses as a browser
///   collapses it, except in `pre` and `white-space: pre*`.
/// - **Links:** another app's kept only with a scheme a user can follow
///   (`http`, `https`, `mailto`, `tel`, `tg`, `ftp`), this app's own with any
///   scheme or none; none with a scheme that runs code or carries a document
///   (`javascript`, `vbscript`, `data`, `file`, `blob`). The rest keep their
///   text.
/// - **Trust:** mention ids, content keys, usernames and hashtags are read
///   from this app's own HTML only, since a page could put them over any
///   text; another app's `username:` or `hashtag:` link keeps its text. Any page can mark
///   its HTML as this app's own, so a host checks a pasted mention's id
///   before sending it.
/// - **Whole-text styles:** a style that covers all of another app's text is
///   dropped, as the reference desktop client drops it: pasting a bold
///   paragraph from a web page should not make the message bold.
///
/// [decode] never throws: what cannot be read keeps its text, and entities
/// that cannot coexist are dropped, styles first, then code blocks and lists.
/// A list item that shares a line with a quote or a code block is dropped as
/// the value drops it.
abstract final class RichTextHtml {
  /// The attribute that marks HTML [encode] wrote.
  static const String ownMarker = 'data-rich-text';

  /// The attribute that carries a mention's id.
  static const String mentionAttribute = 'data-mention-id';

  /// The attribute that carries inline content's [ContentKey.encoded].
  static const String contentKeyAttribute = 'data-content-key';

  /// The scheme of the link a username is written as.
  static const String usernameScheme = 'username:';

  /// The scheme of the link a hashtag is written as.
  static const String hashtagScheme = 'hashtag:';

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

  final _lists = _OpenLists();

  String run() {
    _out.write(
      '<span ${RichTextHtml.ownMarker}="1" style="white-space:pre-wrap">',
    );
    final plain = _text.plain;
    final items = [
      for (final entity in _text.entities)
        if (entity.kind is EntityKind$List) entity,
    ];
    final itemAt = {for (final item in items) item.offset: item};
    // The line break between two consecutive items is the end of one `li` and
    // the start of the next, not a `br`.
    final separators = <int>{
      for (var i = 0; i + 1 < items.length; i++)
        if (items[i + 1].offset == items[i].end + 1) items[i].end,
    };
    final cuts = <int>{
      0,
      plain.length,
      for (final entity in _text.entities) ...[entity.offset, entity.end],
    }.toList()..sort();
    // The entities in the order they start; the ones covering the current
    // run are kept as the runs advance. Items are elements of the lists, not
    // of the runs.
    final starting = [
      for (final entity in _text.entities)
        if (entity.kind is! EntityKind$List) entity,
    ]..sort((a, b) => a.offset.compareTo(b.offset));
    final active = <Entity>[];
    var next = 0;
    for (var i = 0; i + 1 < cuts.length; i++) {
      final start = cuts[i];
      active.removeWhere((entity) => entity.end <= start);
      while (next < starting.length && starting[next].offset <= start) {
        if (starting[next].end > start) active.add(starting[next]);
        next++;
      }
      final isSeparator = separators.contains(start);
      // An item adjacent to the one before it continues the lists; any other
      // run ends them.
      if (_lists.isOpen &&
          start >= _lists.end &&
          !isSeparator &&
          !itemAt.containsKey(start)) {
        _openOnly(const []);
        _lists.closeAll(_out);
      }
      if (isSeparator) {
        _openOnly(const []);
        continue;
      }
      if (itemAt[start] case final item?) {
        _openOnly(const []);
        _lists.enter(_out, item);
      }
      _openOnly([...active]..sort(_nesting));
      _writeText(plain, start, cuts[i + 1]);
    }
    _openOnly(const []);
    _lists.closeAll(_out);
    _out.write('</span>');
    return _out.toString();
  }

  // [plain] from [start] to [end], escaped, every line break a `<br>`.
  void _writeText(String plain, int start, int end) {
    var run = start;
    for (var at = start; at < end; at++) {
      final replacement = switch (plain.codeUnitAt(at)) {
        0x0A => '<br>',
        0x26 => '&amp;',
        0x3C => '&lt;',
        0x3E => '&gt;',
        _ => null,
      };
      if (replacement == null) continue;
      _out
        ..write(plain.substring(run, at))
        ..write(replacement);
      run = at + 1;
    }
    _out.write(plain.substring(run, end));
  }

  // The order elements over one run nest in, outermost first: a quote or a
  // code block, then the one that started first, a longer one before a
  // shorter one; over one range, a link outside styles, styles outside code,
  // code outside an atom, because the decoder reads nothing inside code or an
  // atom.
  static int _nesting(Entity a, Entity b) {
    final block = _isBlock(b).compareTo(_isBlock(a));
    if (block != 0) return block;
    final start = a.offset.compareTo(b.offset);
    if (start != 0) return start;
    final end = b.end.compareTo(a.end);
    if (end != 0) return end;
    return _depthOf(a).compareTo(_depthOf(b));
  }

  static int _isBlock(Entity entity) => _depthOf(entity) == 0 ? 1 : 0;

  // How deep an element sits among elements over one range.
  static int _depthOf(Entity entity) => switch (entity.kind) {
    EntityKind$Style(style: EntityStyle.quote) || EntityKind$CodeBlock() => 0,
    EntityKind$Link() || EntityKind$Username() || EntityKind$Hashtag() => 1,
    EntityKind$Style(style: EntityStyle.code) => 3,
    EntityKind$Style() => 2,
    EntityKind$Mention() || EntityKind$InlineContent() => 4,
    EntityKind$List() => throw StateError('Lists are written by _OpenLists.'),
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
    EntityKind$Link() || EntityKind$Username() || EntityKind$Hashtag() => 'a',
    EntityKind$Mention() || EntityKind$InlineContent() => 'span',
    EntityKind$CodeBlock() => 'pre',
    EntityKind$List() => throw StateError('Lists are written by _OpenLists.'),
  };

  static String _openTagOf(Entity entity) => switch (entity.kind) {
    EntityKind$Link(:final url) => '<a href="${_escapeAttribute(url)}">',
    EntityKind$Username(:final name) =>
      '<a href="${RichTextHtml.usernameScheme}${_escapeAttribute(name)}">',
    EntityKind$Hashtag(:final tag) =>
      '<a href="${RichTextHtml.hashtagScheme}${_escapeAttribute(tag)}">',
    EntityKind$Mention(:final id) =>
      '<span ${RichTextHtml.mentionAttribute}="${_escapeAttribute(id)}">',
    EntityKind$InlineContent(:final key) =>
      '<span ${RichTextHtml.contentKeyAttribute}="${_escapeAttribute(key.encoded)}">',
    // `lang` is the attribute the reference Android client reads.
    EntityKind$CodeBlock(:final language?) =>
      '<pre lang="${_escapeAttribute(language)}">',
    EntityKind$CodeBlock() ||
    EntityKind$Style() ||
    EntityKind$List() => '<${_tagOf(entity)}>',
  };

  static String _escapeAttribute(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// The `ul` / `ol` and `li` elements open while items are written.
///
/// Every level up to the depth of the current item has a list and an item open:
/// a nested list lives inside the `li` of the item before it. An item that
/// jumps more than one level gets empty items to nest under, which other apps
/// show as empty bullets and the decoder reads as nothing.
final class _OpenLists {
  // The kind of the list open at each depth.
  final _stack = <EntityListKind>[];

  // Where the item written last ends.
  int end = 0;

  bool get isOpen => _stack.isNotEmpty;

  void enter(StringBuffer out, Entity item) {
    final EntityKind$List(:listKind, :depth) = item.kind as EntityKind$List;
    if (_stack.isNotEmpty && item.offset != end + 1) closeAll(out);
    end = item.end;
    if (_stack.isNotEmpty && depth <= _stack.length - 1) {
      while (_stack.length - 1 > depth) {
        out.write('</li></${_tag(_stack.removeLast())}>');
      }
      out.write('</li>');
      if (_stack.last != listKind) {
        out.write('</${_tag(_stack.removeLast())}>');
        _open(out, listKind);
      }
      out.write('<li>');
      return;
    }
    while (_stack.length < depth) {
      _open(out, EntityListKind.bullet);
      out.write('<li>');
    }
    _open(out, listKind);
    out.write('<li>');
  }

  void closeAll(StringBuffer out) {
    while (_stack.isNotEmpty) {
      out.write('</li></${_tag(_stack.removeLast())}>');
    }
  }

  void _open(StringBuffer out, EntityListKind kind) {
    _stack.add(kind);
    out.write('<${_tag(kind)}>');
  }

  static String _tag(EntityListKind kind) => switch (kind) {
    EntityListKind.bullet => 'ul',
    EntityListKind.ordered => 'ol',
  };
}

// --- Reading ---------------------------------------------------------------

/// The formatting a text node inherits from its ancestors.
final class _Context {
  const _Context({
    this.styles = const {},
    this.target,
    this.preserveSpace = false,
    this.inAtom = false,
    this.inCode = false,
    this.listKind = EntityListKind.bullet,
    this.listDepth = -1,
  });

  final Set<EntityStyle> styles;

  // What an enclosing `a` makes of the text: a link, or in this app's own HTML
  // a username or hashtag.
  final EntityKind? target;
  final bool preserveSpace;

  // The kind of the nearest enclosing list, and how many lists enclose the
  // text less one (-1 outside any).
  final EntityListKind listKind;
  final int listDepth;

  // Inside a mention or inline content: nothing starts or ends inside one.
  final bool inAtom;

  // Inside code: code holds no other entity.
  final bool inCode;

  _Context copyWith({
    Set<EntityStyle>? styles,
    EntityKind? target,
    bool? preserveSpace,
    bool? inAtom,
    bool? inCode,
    EntityListKind? listKind,
    int? listDepth,
  }) => _Context(
    styles: styles ?? this.styles,
    target: target ?? this.target,
    preserveSpace: preserveSpace ?? this.preserveSpace,
    inAtom: inAtom ?? this.inAtom,
    inCode: inCode ?? this.inCode,
    listKind: listKind ?? this.listKind,
    listDepth: listDepth ?? this.listDepth,
  );
}

final class _Decoder {
  _Decoder(this._document)
    : _ownRoot = _document.querySelector('[${RichTextHtml.ownMarker}]');

  final dom.Document _document;

  // The element [RichTextHtml.encode] wrote, when the HTML is its own: read
  // exactly, and alone, as a platform may wrap it in a document of its own
  // (Windows' HTML Format puts line breaks around the fragment).
  final dom.Element? _ownRoot;

  bool get _own => _ownRoot != null;

  final _text = _DecodedText();
  final _entities = <Entity>[];

  // The items open, innermost last. An item's text is cut where a list nested
  // in it begins, so each frame holds where the text of its current part
  // starts, or null before any.
  final _items = <_ItemFrame>[];

  // Where the last item part ended. In this app's own HTML the next `li` that
  // starts right there follows it without a `br`, and takes a line break.
  int _lastItemEnd = -1;

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
  // The schemes another app's link keeps: ones a user can follow.
  static const _followable = {'http', 'https', 'mailto', 'tel', 'tg', 'ftp'};

  // The schemes no link keeps, not even in HTML marked as this app's own,
  // which any page can mark: they run code or carry a document.
  static const _unsafe = {'javascript', 'vbscript', 'data', 'file', 'blob'};

  static final RegExp _collapsible = RegExp(r'[ \t\n\r\f]+');
  static final RegExp _classSeparator = RegExp(r'\s+');

  // What a browser ignores in a scheme: `java\tscript:` is `javascript:`.
  static final RegExp _ignoredInScheme = RegExp(r'[\x00-\x20]');

  RichText run() {
    final root = _ownRoot ?? _document.body;
    if (root != null) _walkChildren(root, const _Context());
    _trimTrailingSpace();
    final plain = _text.toString();
    final runs = _joinedRuns();
    final entities = _own ? runs : _withoutWholeTextStyles(plain, runs);
    return _build(plain, entities);
  }

  // Text runs of one style or link that touch, as one entity. The value
  // trims a style to non-whitespace before it joins touching ones, so runs
  // split at a space (`<b>one <i>two</i></b>`) would otherwise stay apart.
  // Atoms, quotes and list items are an element's whole range already.
  List<Entity> _joinedRuns() {
    final joined = <Entity>[];
    final open = <EntityKind, int>{};
    final sorted = [..._entities]..sort((a, b) => a.offset.compareTo(b.offset));
    for (final entity in sorted) {
      final kind = entity.kind;
      if (kind.isAtomic ||
          kind == EntityKind.quote ||
          kind is EntityKind$List) {
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
    // Our own HTML spells out every line break, except the one between items.
    final block = !_own && _blocks.contains(tag);
    if (block) _pendingBreak = _text.isNotEmpty;
    if (tag == 'ul' || tag == 'ol') _endItemPart();

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

    // A code block is its element's whole range, with nothing else inside:
    // the formatting of its markup is not the code's.
    if (tag == 'pre' && !context.inAtom && !context.inCode) {
      final start = _flushedLength();
      _walkChildren(element, const _Context(preserveSpace: true, inCode: true));
      if (_text.length > start) {
        _entities.add(
          Entity(
            start,
            _text.length - start,
            EntityKind.codeBlock(language: _languageOf(element)),
          ),
        );
      }
      if (block) _pendingBreak = true;
      return;
    }

    final quote = !context.inAtom && (tag == 'blockquote' || tag == 'details');
    final start = quote ? _flushedLength() : 0;
    final item = tag == 'li' && !context.inAtom && !context.inCode;
    if (item) _beginItem(context);
    _walkChildren(element, _contextOf(element, tag, context));
    if (item) _endItem();
    if (quote && _text.length > start) {
      _entities.add(Entity(start, _text.length - start, EntityKind.quote));
    }
    if (block) _pendingBreak = true;
  }

  void _beginItem(_Context context) {
    // The break the encoder leaves out between consecutive items.
    if (_own && _lastItemEnd == _text.length && _text.isNotEmpty) {
      _text.write('\n');
    }
    _items.add(
      _ItemFrame(
        context.listKind,
        context.listDepth.clamp(0, EntityKind$List.maxDepth),
      ),
    );
  }

  void _endItem() {
    _endItemPart();
    _items.removeLast();
  }

  // The text the current item has so far is an item of its own: what comes
  // after a list nested in it is another.
  void _endItemPart() {
    if (_items.isEmpty) return;
    final frame = _items.last;
    if (frame.start case final start? when _text.length > start) {
      _entities.add(
        Entity(
          start,
          _text.length - start,
          EntityKind.list(listKind: frame.kind, depth: frame.depth),
        ),
      );
      _lastItemEnd = _text.length;
    }
    frame.start = null;
  }

  // The text length once a pending line break is written: where the next
  // text starts.
  int _flushedLength() {
    _flushBreak();
    return _text.length;
  }

  // Mention ids and content keys are trusted only in this app's own HTML:
  // a page could put them over any text, a mention that shows one name and
  // notifies another. The reference clients' custom emoji tag is read from
  // anyone, as they read it.
  EntityKind? _atomOf(dom.Element element) {
    final attributes = element.attributes;
    if (_own) {
      if (attributes[RichTextHtml.contentKeyAttribute] case final encoded?) {
        if (ContentKey.tryParse(encoded) case final key?) {
          return EntityKind.inlineContent(key);
        }
      }
      if (attributes[RichTextHtml.mentionAttribute] case final id?
          when id.isNotEmpty) {
        return EntityKind.mention(id);
      }
    }
    if (element.localName == 'animated-emoji') {
      if (attributes['data-document-id'] case final id? when id.isNotEmpty) {
        return EntityKind.inlineContent(ContentKey.document(id));
      }
    }
    return null;
  }

  static final RegExp _languageName = RegExp(r'^[A-Za-z0-9+#._-]+$');

  // A code block's language as code sites write it: an attribute of the
  // `pre`, or a `language-` / `lang-` class of the `code` inside it.
  static String? _languageOf(dom.Element pre) {
    String? valid(String? name) =>
        name != null && _languageName.hasMatch(name) ? name : null;
    for (final attribute in const [
      'lang',
      'language',
      'lng',
      'data-language',
    ]) {
      if (valid(pre.attributes[attribute]) case final language?) {
        return language;
      }
    }
    final classes = (pre.querySelector('code')?.attributes['class'] ?? '')
        .split(RegExp(r'\s+'));
    for (final name in classes) {
      for (final prefix in const ['language-', 'lang-']) {
        if (name.startsWith(prefix)) {
          if (valid(name.substring(prefix.length)) case final language?) {
            return language;
          }
        }
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
    if (const {'code', 'tt', 'kbd', 'samp'}.contains(tag)) {
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
    if ((element.attributes['class'] ?? '')
            .split(_classSeparator)
            .contains('tg-spoiler') ||
        element.attributes['data-entity-type'] == 'MessageEntitySpoiler') {
      styles.add(EntityStyle.spoiler);
    }
    _applyCss(css, styles);
    final isList = tag == 'ul' || tag == 'ol';
    return context.copyWith(
      styles: styles,
      target: tag == 'a'
          ? _targetOf(element) ?? context.target
          : context.target,
      preserveSpace: preserveSpace,
      listKind: isList
          ? (tag == 'ol' ? EntityListKind.ordered : EntityListKind.bullet)
          : context.listKind,
      listDepth: isList ? context.listDepth + 1 : context.listDepth,
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

  // This app's own links come back as they were written, whatever their
  // scheme, or none; another app's only with a scheme a user can follow. No
  // link with an unsafe scheme is kept. A username or hashtag is this app's
  // own link to a scheme of its own; elsewhere it is not a followable one, so
  // it keeps its text. A link cannot hold the schemes of mentions, usernames
  // and hashtags either, since markup would read them back as those.
  EntityKind? _targetOf(dom.Element element) {
    final href = element.attributes['href'];
    if (href == null) return null;
    final normalized = href.replaceAll(_ignoredInScheme, '');
    final colon = normalized.indexOf(':');
    final scheme = colon > 0
        ? normalized.substring(0, colon).toLowerCase()
        : null;
    if (_unsafe.contains(scheme)) return null;
    if (!_own)
      return _followable.contains(scheme) ? EntityKind.link(href.trim()) : null;
    if (href.isEmpty || href.contains('\n') || href.contains('\r')) return null;
    if (href.startsWith(RichTextHtml.usernameScheme)) {
      final name = href.substring(RichTextHtml.usernameScheme.length);
      return name.isEmpty ? null : EntityKind.username(name);
    }
    if (href.startsWith(RichTextHtml.hashtagScheme)) {
      final tag = href.substring(RichTextHtml.hashtagScheme.length);
      return tag.isEmpty ? null : EntityKind.hashtag(tag);
    }
    return href.startsWith('mention:') ? null : EntityKind.link(href);
  }

  void _breakLine() {
    _flushBreak();
    _trimTrailingSpace();
    if (_items.isNotEmpty) _items.last.start ??= _text.length;
    _text.write('\n');
  }

  // A block ends a line that is still open, and never adds an empty one.
  void _flushBreak() {
    if (!_pendingBreak) return;
    _pendingBreak = false;
    if (_text.isEmpty || _text.endsWithUnit(0x0A)) return;
    _trimTrailingSpace();
    _text.write('\n');
  }

  // Collapsed whitespace does not end a line (not in our own HTML, which
  // keeps every space).
  void _trimTrailingSpace() {
    if (_own || !_text.trimTrailingSpaces()) return;
    _clipEntitiesTo(_text.length);
  }

  // Each entity ends where the text ended when it was added, so the ones
  // past [length] are the last ones added.
  void _clipEntitiesTo(int length) {
    for (var i = _entities.length - 1; i >= 0; i--) {
      final entity = _entities[i];
      if (entity.end <= length) break;
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
      text = text.replaceAll(_collapsible, ' ');
      final lineStart =
          _text.isEmpty || _text.endsWithUnit(0x0A) || _pendingBreak;
      if (lineStart || _text.endsWithUnit(0x20)) text = text.trimLeft();
      text = text.replaceAll(' ', ' ');
    }
    if (text.isEmpty) return;
    _flushBreak();
    final start = _text.length;
    if (_items.isNotEmpty) _items.last.start ??= start;
    _text.write(text);
    final end = _text.length;
    // Inside an atom the context is the atom's own: styles around it cover
    // it whole, and nothing inside it adds any.
    for (final style in context.styles) {
      _entities.add(Entity(start, end - start, EntityKind.style(style)));
    }
    if (context.target case final kind?) {
      _entities.add(Entity(start, end - start, kind));
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
  // code blocks and list items, then everything but mentions and inline
  // content.
  static RichText _build(String plain, List<Entity> entities) {
    bool styleless(Entity entity) =>
        entity.kind is! EntityKind$Style || entity.kind == EntityKind.quote;
    for (final keep in <bool Function(Entity)>[
      (_) => true,
      styleless,
      (entity) =>
          styleless(entity) &&
          entity.kind is! EntityKind$CodeBlock &&
          entity.kind is! EntityKind$List,
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

/// An item being read: its list's kind, its depth, and where its current part
/// of text starts.
final class _ItemFrame {
  _ItemFrame(this.kind, this.depth);

  final EntityListKind kind;
  final int depth;
  int? start;
}

/// The decoded text so far. It grows at its end and loses spaces off its
/// end, and the decoder asks for its last character per text node and line
/// break, which a [StringBuffer] could answer only by copying all of it.
final class _DecodedText {
  // Never holds an empty string.
  final _chunks = <String>[];

  int get length => _length;
  int _length = 0;

  bool get isEmpty => _length == 0;
  bool get isNotEmpty => _length != 0;

  void write(String text) {
    if (text.isEmpty) return;
    _chunks.add(text);
    _length += text.length;
  }

  bool endsWithUnit(int unit) =>
      _chunks.isNotEmpty &&
      _chunks.last.codeUnitAt(_chunks.last.length - 1) == unit;

  /// Drops the spaces at the end; whether there were any.
  bool trimTrailingSpaces() {
    var trimmed = false;
    while (_chunks.isNotEmpty) {
      final last = _chunks.last;
      var end = last.length;
      while (end > 0 && last.codeUnitAt(end - 1) == 0x20) {
        end--;
      }
      if (end == last.length) break;
      trimmed = true;
      _length -= last.length - end;
      if (end > 0) {
        _chunks.last = last.substring(0, end);
        break;
      }
      _chunks.removeLast();
    }
    return trimmed;
  }

  @override
  String toString() => _chunks.join();
}
