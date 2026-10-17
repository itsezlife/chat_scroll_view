import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:emoji_data/src/catalog/emoji_catalog.dart';
import 'package:emoji_data/src/collections/emoji_items.dart';
import 'package:emoji_data/src/collections/emoji_section.dart';
import 'package:emoji_data/src/collections/emoji_spoken_names.dart';
import 'package:listen/listen.dart';

/// The emoji catalogue as a [CollectionSource]: the user's recents followed by
/// one category per [EmojiSection].
///
/// ## Collections
///
/// [collections] lists `CollectionId.recent` first, then
/// `CollectionId.category(sectionId)` for each of the [sections]: the
/// reference client's seven by default, a fold of the catalogue's groups. A
/// group no section names gets a section of its own, with the group's id, after
/// the rest, so a catalogue that gains a group shows it. The collections carry
/// no title and no cover: naming and icons of categories belong to the page. A
/// category holds one item per entry, in palette order, group after group,
/// each described as a unicode emoji drawn as a glyph. The item is the entry's
/// base key, or the variant the user chose for it (see [chooseVariant]).
/// Recents hold what the [RecentsStore] holds for `SemanticKind.unicodeEmoji`,
/// best first, as it was picked: the emoji page's one list, so custom emoji
/// picked on the page are in it too (see *Custom emoji in the recents*).
///
/// ## Loading
///
/// Everything is in memory, but the commands are asynchronous like every
/// source's: [load] publishes `loading` and publishes `loaded` after a
/// microtask (and, with spoken names, after the packs are read), never in the
/// same call. A loaded collection stays current: the
/// recents follow their store, and a category follows the variant choices
/// and the [GlyphSupport], each change one publication for all collections it
/// touches. [pageSize] splits a category into pages (default: one page); the
/// pages already loaded stay loaded when emoji are hidden or shown.
///
/// Nothing fails, so no collection ever reaches `failed`.
///
/// ## Custom emoji in the recents
///
/// The recents list holds every emoji picked on the emoji page, custom emoji
/// (document keys) among the unicode ones, as the reference clients keep one
/// list. The catalogue describes only unicode keys; the others are described
/// by the host's [ContentResolver], asked in one batch for the keys it has
/// not answered yet whenever the recents are derived:
///
/// - until the resolver answers, a key is listed bare, in its place;
/// - a key it resolves is listed with its descriptor from then on;
/// - a key it leaves out (unknown or deleted content) leaves the list, so the
///   page never draws a stand-in for content that will not come, and is not
///   asked about again for the life of the source: the resolver contract
///   says a key left out was attempted and is unknown;
/// - a batch that fails (no connection) is the state "not described yet", not
///   an error: its keys stay bare and are asked again the next time the
///   recents change.
///
/// Without a resolver every key outside the catalogue is listed bare.
///
/// ## Glyph support
///
/// Emoji the [GlyphSupport] says the device cannot draw are left out of
/// every collection. Without one everything shows.
///
/// ## Spoken names
///
/// Given [KeywordSource] and the ordered `languages` (the app language first),
/// each item carries the spoken name of its emoji from the first language
/// that names it, so a screen reader says the name and not the glyph. The
/// packs are read before the first collection is published as loaded (and not
/// again: a source keeps what it read), and a newer pack arriving on
/// [KeywordSource.changes] re-derives the loaded collections. A pack that
/// cannot be read is reported to the zone and leaves the items unnamed; it
/// never fails a collection. Without a keyword source the items have no
/// spoken name.
final class EmojiCollectionSource implements CollectionSource {
  /// Creates the source over [catalog].
  ///
  /// [pageSize] must be positive when given.
  EmojiCollectionSource({
    required EmojiCatalog catalog,
    required RecentsStore recents,
    required PreferenceStore preferences,
    GlyphSupport? glyphSupport,
    KeywordSource? keywords,
    ContentResolver? resolver,
    List<String> languages = const [],
    int? pageSize,
    List<EmojiSection> sections = EmojiSection.reference,
  }) : assert(
         pageSize == null || pageSize > 0,
         'A page size must be positive.',
       ),
       _catalog = catalog,
       _recents = recents,
       _preferences = preferences,
       _items = EmojiItems(
         catalog: catalog,
         preferences: preferences,
         glyphSupport: glyphSupport,
       ),
       _glyphSupport = glyphSupport,
       _keywords = keywords,
       _resolver = resolver,
       _languages = List<String>.unmodifiable(languages),
       _pageSize = pageSize,
       _sections = _withUnnamedGroups(catalog, sections) {
    _collections = ValueNotifier<List<Collection>>(_snapshot());
    _recents.changes.addListener(_refresh);
    _preferences.changes.addListener(_refresh);
    _glyphSupport?.changes.addListener(_refresh);
    _keywords?.changes.addListener(_onKeywords);
  }

  final EmojiCatalog _catalog;
  final RecentsStore _recents;
  final PreferenceStore _preferences;
  final GlyphSupport? _glyphSupport;
  final EmojiItems _items;
  final KeywordSource? _keywords;
  final ContentResolver? _resolver;
  final List<String> _languages;
  final int? _pageSize;
  final List<EmojiSection> _sections;
  late final List<CollectionId> _ids = [
    CollectionId.recent,
    for (final section in _sections) CollectionId.category(section.id),
  ];
  Future<void>? _namesRead;

  late final ValueNotifier<List<Collection>> _collections;
  final Map<CollectionId, CollectionContents> _states = {};
  final Map<CollectionId, int> _pages = {};
  final Map<CollectionId, Future<void>> _loading = {};
  final Set<CollectionId> _loadingMore = {};
  // What the resolver said about recents outside the catalogue: a descriptor,
  // or null for content it does not know.
  final Map<ContentKey, ContentDescriptor?> _resolved = {};
  final Set<ContentKey> _resolving = {};
  bool _disposed = false;

  @override
  ValueListenable<List<Collection>> get collections => _collections;

  /// The entry [key] is the base or a variant of, or null when the catalogue
  /// holds no such key. The same answer for the grid, the variant picker and
  /// search, so they agree on which emoji have variants.
  EmojiEntry? entryOf(ContentKey key) => _catalog.entryOf(key);

  /// The key the grid shows for [entry] now: the chosen variant, else the
  /// base.
  ContentKey$Unicode shownKeyOf(EmojiEntry entry) =>
      _items.shownKey(entry) ?? entry.base;

  /// Remembers [variant] as the user's choice for [entry]. Choosing the base
  /// itself is remembered too, as the base: the grid shows the same emoji, and
  /// `PreferenceStore.preferredVariant` still tells that the user chose, which
  /// is what a page asks to decide how a press opens the variant picker.
  ///
  /// The loaded collections show it before the returned future completes,
  /// which completes when the choice is persisted. Throws an
  /// [ArgumentError] when [variant] is neither the base nor a variant of
  /// [entry].
  Future<void> chooseVariant(EmojiEntry entry, ContentKey$Unicode variant) {
    if (entry.modifiersOf(variant) == null) {
      throw ArgumentError.value(
        variant,
        'variant',
        'Not the base or a variant of ${entry.base}.',
      );
    }
    return _preferences.setPreferredVariant(entry.base, variant);
  }

  @override
  Future<void> load(CollectionId id) {
    if (_disposed || !_ids.contains(id)) return Future<void>.value();
    if (_loading[id] case final running?) return running;
    if (_states[id] != null) return Future<void>.value();
    _states[id] = CollectionContents.loading;
    _publish();
    return _loading[id] = _finishLoad(id);
  }

  Future<void> _finishLoad(CollectionId id) async {
    await Future<void>.value();
    await (_namesRead ??= _readNames());
    _loading.removeWhere((loadingId, _) => loadingId == id);
    if (_disposed) return;
    _pages[id] = 1;
    _states[id] = _contentsOf(id);
    _publish();
  }

  @override
  Future<void> loadMore(CollectionId id) async {
    if (_disposed || _loadingMore.contains(id)) return;
    switch (_states[id]) {
      case CollectionContents$Loaded(nextPageToken: != null):
        break;
      case _:
        return;
    }
    _loadingMore.add(id);
    await Future<void>.value();
    _loadingMore.remove(id);
    if (_disposed) return;
    _pages[id] = _pages[id]! + 1;
    _states[id] = _contentsOf(id);
    _publish();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _recents.changes.removeListener(_refresh);
    _preferences.changes.removeListener(_refresh);
    _glyphSupport?.changes.removeListener(_refresh);
    _keywords?.changes.removeListener(_onKeywords);
    _collections.dispose();
  }

  // The packs of the active languages, as the names the items carry. A pack
  // that cannot be read is reported and costs only the names.
  Future<void> _readNames() async {
    final keywords = _keywords;
    if (keywords == null || _languages.isEmpty) return;
    try {
      final found = await Future.wait([
        for (final language in _languages) keywords.pack(language),
      ]);
      if (_disposed) return;
      _items.spokenNames = EmojiSpokenNames(_catalog, {...found.nonNulls});
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  // A pack was added or replaced: read the names again, and re-derive what is
  // loaded once they are in.
  void _onKeywords() {
    if (_disposed || _namesRead == null) return;
    unawaited(
      (_namesRead = _readNames()).then((_) {
        if (!_disposed) _refresh();
      }),
    );
  }

  // Re-derives what is loaded from the stores, and publishes once if any of
  // it differs.
  void _refresh() {
    if (_disposed) return;
    for (final id in _states.keys.toList()) {
      if (_states[id] case CollectionContents$Loaded()) {
        _states[id] = _contentsOf(id);
      }
    }
    _publish();
  }

  CollectionContents _contentsOf(CollectionId id) {
    if (id == CollectionId.recent) {
      final keys = _recents.recents(SemanticKind.unicodeEmoji);
      _resolveUnknown(keys);
      return CollectionContents.loaded([
        for (final key in keys) ?_recentItemOf(key),
      ]);
    }
    final section = _sections.firstWhere(
      (section) => section.id == (id as CollectionId$Category).id,
    );
    final visible = [
      for (final group in section.groupIds)
        for (final entry in _catalog.entriesOf(group)) ?_items.itemOf(entry),
    ];
    final size = _pageSize;
    final shown = switch (size) {
      final size? => (_pages[id]! * size).clamp(0, visible.length),
      null => visible.length,
    };
    return CollectionContents.loaded(
      visible.sublist(0, shown),
      nextPageToken: shown < visible.length ? PageToken('$shown') : null,
    );
  }

  CollectionItem? _recentItemOf(ContentKey key) {
    if (key case ContentKey$Unicode()) return _items.itemForKey(key);
    if (!_resolved.containsKey(key)) return CollectionItem.bare(key);
    return switch (_resolved[key]) {
      final descriptor? => CollectionItem.described(descriptor),
      null => null,
    };
  }

  // Asks the resolver, in one batch, about the recents outside the catalogue
  // it has not answered and is not answering now.
  void _resolveUnknown(List<ContentKey> keys) {
    final resolver = _resolver;
    if (resolver == null) return;
    final unknown = [
      for (final key in keys)
        if (key is! ContentKey$Unicode &&
            !_resolved.containsKey(key) &&
            !_resolving.contains(key))
          key,
    ];
    if (unknown.isEmpty) return;
    _resolving.addAll(unknown);
    // Through Future.sync: a resolver that throws instead of failing its
    // future is a failed batch too, not an error out of deriving the recents.
    unawaited(
      Future.sync(() => resolver.resolve(unknown)).then(
        (found) {
          _resolving.removeAll(unknown);
          for (final key in unknown) {
            _resolved[key] = found[key];
          }
          _refresh();
        },
        // Not described yet: the keys stay bare and are asked again at the
        // next change (see the class documentation). Reporting it would
        // report every recents change made offline.
        onError: (Object _) => _resolving.removeAll(unknown),
      ),
    );
  }

  // The [sections] that hold a group the catalogue has, and a section for each
  // group of the catalogue they leave out.
  static List<EmojiSection> _withUnnamedGroups(
    EmojiCatalog catalog,
    List<EmojiSection> sections,
  ) {
    final present = {for (final group in catalog.structure.groups) group.id};
    final named = {for (final section in sections) ...section.groupIds};
    return List.unmodifiable([
      for (final section in sections)
        if (section.groupIds.any(present.contains)) section,
      for (final group in catalog.structure.groups)
        if (!named.contains(group.id)) EmojiSection(group.id, [group.id]),
    ]);
  }

  List<Collection> _snapshot() => List.unmodifiable([
    for (final id in _ids)
      Collection(id: id, contents: _states[id] ?? CollectionContents.idle),
  ]);

  void _publish() {
    final next = _snapshot();
    final current = _collections.value;
    var same = next.length == current.length;
    for (var i = 0; same && i < next.length; i++) {
      same = next[i] == current[i];
    }
    if (!same) _collections.value = next;
  }
}
