import 'dart:collection';
import 'dart:ui' show Canvas, Color, Rect;

import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_binding_base.dart';
import 'package:catalog_assets/src/asset/asset_cache_budgets.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_playback.dart';
import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/asset/circle_placeholder.dart';
import 'package:catalog_assets/src/asset/rect_placeholder.dart';
import 'package:catalog_assets/src/glyph/glyph_binding.dart';
import 'package:catalog_assets/src/glyph/glyph_sprite_source.dart';
import 'package:catalog_assets/src/glyph/text_glyph_paintable.dart';
import 'package:catalog_assets/src/playback/playback_clock.dart';
import 'package:catalog_assets/src/texture/frame_texture_pool.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// The asset cache of one host: entries keyed by content and [AssetSpec],
/// bindings that pin them, a byte-budgeted LRU for the ones nobody holds, and
/// the playback clock their animations advance by.
///
/// Created by the host and handed to the surfaces that attach; there is no
/// static instance. It owns what it made (entries, the default clock, the
/// default placeholder) and nothing it was handed (a producer, a glyph source,
/// a clock, the texture pool, the memory-pressure signal): [dispose] leaves
/// those alone.
///
/// ## Entries
///
/// [attach] finds or creates the entry for `(key, spec)` and returns a
/// binding. The first binding starts an attempt through the [producer]; more
/// bindings share it (one attempt per entry, however many surfaces ask), and
/// when the last binding leaves a running attempt is cancelled. An entry that
/// reached a stage worth keeping stays for the next attach (pager keep-alive)
/// until the budget or [clearAll] drops it; one that has produced nothing
/// beyond a placeholder is dropped at once.
///
/// The same content at another spec is another entry, but not another
/// picture to wait for: while an entry is below its first frame, a binding
/// shows the best stage a **sibling** (an entry of the same key and decode
/// mode at another size) has reached, placed by the binding's own profile,
/// instead of a placeholder (see [AssetBinding.paintable]). It borrows that
/// sibling, which pins it like a binding would, until its own entry catches
/// up or it detaches. A sibling that plays lends its first-frame still
/// ([AssetPaintable.firstFrame]), never its live frame, and one with no still
/// lends nothing: the binding's own entry starts from frame 0, and a frame
/// from the middle of the sibling's loop would jump back when it arrives. A
/// GIF picked from a panel cell is drawn in the message at once, at the
/// cell's pixels, until the message's own decode arrives.
///
/// An entry with a live binding is pinned: neither the budget, [clearAll] nor
/// the memory-pressure signal evicts it, so eviction can never invalidate a
/// binding. A binding gives back exactly what it took, once, and never looks
/// its entry up again, so nothing done to the cache while it is live changes
/// another binding's counts.
///
/// ## Glyphs
///
/// Unicode keys are the glyph media form: with a [glyphSource] registered they
/// bind to a baked sprite on an atlas page and never reach the [producer]
/// (see [GlyphSpriteSource]). Without one they are ordinary entries, which is
/// how a platform that draws glyphs as text plugs in a producer that does.
/// The strategy follows the source for the life of a binding, not only at
/// attach: registering or removing the source moves the bindings already
/// attached.
///
/// ## Textures
///
/// A platform with a texture host registers its [FrameTexturePool] as
/// [textures]; decoders whose assets play take textures from it, and fall back
/// to their dynamic page slots without one (ADR 043). The memory-pressure
/// signal releases its idle textures along with the unpinned entries.
///
/// ## Threading
///
/// Single-threaded: every call, every producer report, every listener and all
/// painting happen on the UI isolate. Producers may decode on other isolates
/// or threads but report here from the UI isolate.
final class AssetCacheScope {
  /// Creates a scope.
  ///
  /// [producer] makes non-glyph entries; without one they stay at
  /// [AssetStage.none]. [glyphSource] is the atlas unicode keys bind to.
  /// [clock] is the playback clock (created, and disposed with the scope, if
  /// omitted). [memoryPressure] is a signal that empties the unpinned
  /// entries when it fires. [systemFonts] is the engine's signal that the
  /// fonts it draws text with changed (`PaintingBinding.systemFonts`): glyphs
  /// drawn as text lay out again and repaint when it fires, since a browser
  /// fetches the font that draws an emoji only once it meets one, and what
  /// was laid out before drew the missing-glyph box. [placeholder] is what a
  /// glyph binding paints before any stage exists (a circle by default);
  /// [mediaPlaceholder] is what any other binding paints (the whole rectangle
  /// in a quiet colour by default, `RectPlaceholder`). [textures] is the
  /// pool of the platform's texture host, or null where there is none.
  AssetCacheScope({
    AssetProducer? producer,
    GlyphSpriteSource? glyphSource,
    AssetCacheBudgets budgets = AssetCacheBudgets.defaults,
    PlaybackClock? clock,
    Listenable? memoryPressure,
    Listenable? systemFonts,
    AssetPaintable? placeholder,
    AssetPaintable? mediaPlaceholder,
    this.textures,
  }) : _producer = producer,
       _glyphSource = glyphSource,
       _budgets = budgets,
       _clock = clock ?? PlaybackClock(),
       _ownsClock = clock == null,
       _memoryPressure = memoryPressure,
       _systemFonts = systemFonts,
       placeholder = placeholder ?? const CirclePlaceholder(),
       mediaPlaceholder = mediaPlaceholder ?? const RectPlaceholder() {
    memoryPressure?.addListener(_onMemoryPressure);
    systemFonts?.addListener(_onSystemFonts);
    glyphSource?.addPageListener(_onGlyphPage);
  }

  final AssetProducer? _producer;
  final PlaybackClock _clock;
  final bool _ownsClock;
  final Listenable? _memoryPressure;
  final Listenable? _systemFonts;
  GlyphSpriteSource? _glyphSource;
  AssetCacheBudgets _budgets;
  bool _disposed = false;

  /// What a glyph binding paints before its entry has produced any stage.
  final AssetPaintable placeholder;

  /// What a binding of any other content paints before its entry has produced
  /// any stage: a glyph has a box and no edges, media has a rectangle.
  final AssetPaintable mediaPlaceholder;

  final Map<(ContentKey, AssetSpec), _Entry> _entries = {};
  // Every entry of a key, whatever its spec: the siblings a binding below its
  // first frame borrows a stage from.
  final Map<ContentKey, Set<_Entry>> _byKey = {};
  // Entries nobody is bound to, per tier, least recently used first.
  final Map<AssetTier, LinkedHashSet<_Entry>> _unpinned = {
    for (final tier in AssetTier.values) tier: LinkedHashSet<_Entry>.identity(),
  };
  final Map<AssetTier, int> _bytes = {
    for (final tier in AssetTier.values) tier: 0,
  };
  final Set<GlyphBinding> _glyphBindings = {};

  // A unicode key that reaches an entry (a glyph drawn as text) is still a
  // glyph: its stand-in is the circle, whatever the media default is.
  AssetPaintable _placeholderOf(ContentKey key) =>
      key is ContentKey$Unicode ? placeholder : mediaPlaceholder;

  /// The textures playing assets may take instead of a page slot, or null
  /// where the platform has no texture host.
  final FrameTexturePool? textures;

  // The idle textures go with the unpinned entries; what is on screen stays.
  void _onMemoryPressure() {
    clearAll();
    if (!_disposed) textures?.releaseIdle();
  }

  /// The clock every animated binding of this scope advances by. Hosts set
  /// its pause layers.
  PlaybackClock get clock => _clock;

  /// The byte budgets of the unattached entries.
  AssetCacheBudgets get budgets => _budgets;
  set budgets(AssetCacheBudgets value) {
    _budgets = value;
    _trim();
  }

  /// The atlas unicode keys bind to, or null.
  GlyphSpriteSource? get glyphSource => _glyphSource;

  /// Registers (or, with null, removes) the source glyph bindings read.
  ///
  /// Every unicode binding already attached moves in place, whichever way it
  /// was made: each gives back what it held of the old mode (a hold on the old
  /// source, or its entry when there was none), takes what the new needs (a
  /// hold on the new source; without one, an entry of the producer) and
  /// signals its listeners. A host that plans a new atlas replaces it without
  /// re-attaching every leaf; one that registers its first atlas late, after
  /// leaves drew as text, moves them onto it; one that drops it sends them
  /// back to the producer instead of leaving a placeholder. The scope never
  /// disposes a source. After [dispose] the value is only remembered.
  set glyphSource(GlyphSpriteSource? value) {
    if (identical(_glyphSource, value)) return;
    if (_disposed) {
      // Nothing is bound or listened to any more; a source arriving late is a
      // host's ordering, not a lifecycle bug worth throwing for.
      _glyphSource = value;
      return;
    }
    _glyphSource?.removePageListener(_onGlyphPage);
    _glyphSource = value;
    value?.addPageListener(_onGlyphPage);
    for (final binding in List<GlyphBinding>.of(_glyphBindings)) {
      binding.rebind(value);
    }
  }

  // Glyphs drawn as text drop their layout, and what draws them repaints.
  void _onSystemFonts() {
    if (_disposed) return;
    for (final entry in _entries.values) {
      if (entry.paintable case final TextGlyphPaintable text) {
        text.systemFontsChanged();
        for (final binding in List<_EntryBinding>.of(entry.bindings)) {
          binding.entryChanged();
        }
      }
    }
    for (final binding in List<GlyphBinding>.of(_glyphBindings)) {
      binding.systemFontsChanged();
    }
  }

  /// Whether any binding is attached to the entry for [key] at [spec].
  bool isAttached(ContentKey key, AssetSpec spec) =>
      _entries[(key, spec)]?.bindings.isNotEmpty ?? false;

  /// Whether the cache holds an entry for [key] at [spec], attached or not.
  bool contains(ContentKey key, AssetSpec spec) =>
      _entries.containsKey((key, spec));

  /// Bytes the entries of [tier] count, attached or not.
  int bytesIn(AssetTier tier) => _bytes[tier]!;

  /// How many entries the cache holds.
  int get entryCount => _entries.length;

  /// Attaches [key] decoded as [spec], to be used as [profile] says.
  ///
  /// Throws a [StateError] after [dispose]: a surface that outlives its scope
  /// is a lifecycle bug to see, not to absorb.
  AssetBinding attach(ContentKey key, AssetSpec spec, AssetProfile profile) {
    if (_disposed) {
      throw StateError('AssetCacheScope.attach called after dispose.');
    }
    if (key case final ContentKey$Unicode glyph) {
      final binding = GlyphBinding(
        key: glyph,
        spec: spec,
        profile: profile,
        placeholder: placeholder,
        clock: _clock,
        source: _glyphSource,
        openEntry: () => _attachEntry(key, spec, profile),
        onDetach: _glyphBindings.remove,
      );
      _glyphBindings.add(binding);
      return binding;
    }
    return _attachEntry(key, spec, profile);
  }

  _EntryBinding _attachEntry(
    ContentKey key,
    AssetSpec spec,
    AssetProfile profile,
  ) {
    final entry = _entries.putIfAbsent((key, spec), () {
      final created = _Entry(key, spec);
      (_byKey[key] ??= Set<_Entry>.identity()).add(created);
      return created;
    });
    final binding = _EntryBinding(scope: this, entry: entry, profile: profile);
    _unpinned[entry.tier]!.remove(entry);
    entry.bindings.add(binding);
    entry.demand.refresh(entry.bindings);
    if (entry.attempt == null && !entry.isFinal) _start(entry);
    // After the start: a memory hit answered inside it needs no sibling.
    binding
      ..reborrow()
      ..syncPlayback();
    return binding;
  }

  // The sibling of [entry] with the best stage beyond [above], the larger
  // decode on a tie, or null. A template decode is alpha only, so only an
  // entry of the same decode mode draws the same picture.
  _Entry? _siblingOf(_Entry entry, AssetStage above) {
    _Entry? best;
    for (final sibling in _byKey[entry.key] ?? const <_Entry>{}) {
      if (identical(sibling, entry) ||
          sibling.lent == null ||
          sibling.spec.decodeMode != entry.spec.decodeMode ||
          sibling.lentStage.index <= above.index) {
        continue;
      }
      if (best == null ||
          sibling.lentStage.index > best.lentStage.index ||
          (sibling.lentStage == best.lentStage &&
              _area(sibling) > _area(best))) {
        best = sibling;
      }
    }
    return best;
  }

  static int _area(_Entry entry) =>
      entry.spec.pixelWidth * entry.spec.pixelHeight;

  // A borrowed sibling is pinned like a bound entry: what a binding shows is
  // never evicted under it.
  void _borrow(_Entry sibling) {
    sibling.borrowers++;
    _unpinned[sibling.tier]!.remove(sibling);
  }

  void _giveBack(_Entry sibling) {
    sibling.borrowers--;
    _release(sibling);
    _trim();
  }

  // An entry nobody binds or borrows any more: what has a stage worth keeping
  // waits in the budget, the rest goes at once.
  void _release(_Entry entry) {
    if (entry.isPinned) return;
    if (entry.stage.index <= AssetStage.placeholder.index) {
      _evict(entry);
    } else {
      _unpinned[entry.tier]!.add(entry);
    }
  }

  /// Drops every entry nobody is bound to, disposing their paintables. Pinned
  /// entries stay: eviction never touches a live binding. This is also what
  /// the memory-pressure signal does. Baked atlas pages are not the cache's
  /// to drop; their source applies its own retention and pressure rules.
  void clearAll() {
    if (_disposed) return;
    for (final tier in AssetTier.values) {
      List<_Entry>.of(_unpinned[tier]!).forEach(_evict);
    }
  }

  /// The host's signal that the network is back: attempts that failed
  /// transiently are repeated for entries that are still attached. Permanent
  /// failures wait for a re-attach or [AssetBinding.retry]; entries nobody is
  /// bound to are left alone.
  void connectivityRestored() {
    if (_disposed) return;
    for (final entry in List<_Entry>.of(_entries.values)) {
      if (entry.bindings.isNotEmpty &&
          entry.attempt == null &&
          !entry.isFinal &&
          entry.failureKind == AssetFailureKind.transient) {
        _start(entry);
      }
    }
  }

  /// Cancels every attempt, disposes every entry, gives back the holds of
  /// live glyph bindings and stops listening to the memory-pressure signal.
  /// Bindings still around go silent. Idempotent. Disposes the clock only if
  /// the scope made it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _memoryPressure?.removeListener(_onMemoryPressure);
    _systemFonts?.removeListener(_onSystemFonts);
    _glyphSource?.removePageListener(_onGlyphPage);
    for (final entry in List<_Entry>.of(_entries.values)) {
      entry.attempt?.cancel();
      for (final binding in List<_EntryBinding>.of(entry.bindings)) {
        binding.detach();
      }
      _evict(entry);
    }
    for (final binding in List<GlyphBinding>.of(_glyphBindings)) {
      binding.detach();
    }
    if (_ownsClock) _clock.dispose();
  }

  // Every glyph binding repaints when any page changes: which cells are on a
  // page is not tracked per binding, and a repaint request is idempotent.
  void _onGlyphPage(int pageIndex) {
    for (final binding in List<GlyphBinding>.of(_glyphBindings)) {
      binding.pageChanged();
    }
  }

  // --- Attempts -------------------------------------------------------------

  void _start(_Entry entry) {
    final producer = _producer;
    if (producer == null) return;
    final attempt = _Attempt(this, entry);
    entry.attempt = attempt;
    // The last attempt's download is no fact about this one: the producer
    // announces it again if the content is still missing, and a binding still
    // drawing the old fraction hears when it does not.
    final previousDownload = entry.download;
    entry.download = null;
    try {
      final task = producer.produce(
        AssetRequest(entry.key, entry.spec),
        attempt,
        entry.demand,
      );
      // The attempt may already have ended inside produce (a memory hit).
      if (!attempt.ended) attempt.task = task;
    } on Object catch (error, stackTrace) {
      // The contract says produce reports failures; one that throws is a
      // bug, recorded for diagnostics and not retried by connectivity.
      attempt.fail(error, stackTrace, AssetFailureKind.permanent);
    }
    if (previousDownload != null && entry.download == null) {
      entry.signalDownload();
    }
  }

  void _advance(
    _Entry entry,
    AssetStage stage,
    AssetPaintable paintable,
    int bytes,
    AssetTier tier,
  ) {
    assert(stage != AssetStage.none, 'advance needs a stage to draw');
    if (stage.index < entry.stage.index) {
      paintable.dispose();
      return;
    }
    final previous = entry.paintable;
    // A thumbnail replaced by content is kept for the bindings that were
    // showing it: they fade the content in over it (a bitmap thumbnail stays
    // opaque beneath, as in the reference client) and release it when the
    // content is opaque. Without a waiting binding there is nobody to keep it
    // for; one that shows a sibling's content was not showing the thumbnail
    // and has nothing to fade over.
    final waiting = [
      for (final binding in entry.bindings)
        if (binding._borrowed == null) binding,
    ];
    final keep =
        previous != null &&
        entry.stage == AssetStage.placeholder &&
        stage.index > AssetStage.placeholder.index &&
        waiting.isNotEmpty;
    if (keep) {
      entry.disposeStandIn();
      entry.standIn = previous;
      for (final binding in waiting) {
        binding._holdsStandIn = true;
        entry.standInHolders++;
      }
    } else if (previous != null && !identical(previous, paintable)) {
      previous.dispose();
    }
    if (previous != null)
      _bytes[entry.tier] = _bytes[entry.tier]! - entry.bytes;
    entry
      ..stage = stage
      ..paintable = paintable
      ..bytes = bytes
      ..tier = tier
      ..lastError = null
      ..failureKind = null;
    _bytes[tier] = _bytes[tier]! + bytes;
    if (entry.isFinal) {
      entry.attempt?.ended = true;
      entry.attempt = null;
      entry.download = null;
    }
    for (final binding in List<_EntryBinding>.of(entry.bindings)) {
      binding.entryChanged();
    }
    // A sibling waiting below its first frame may draw this stage now (or a
    // better one of the entry it borrows from).
    for (final sibling in List<_Entry>.of(_byKey[entry.key] ?? const {})) {
      if (identical(sibling, entry)) continue;
      for (final binding in List<_EntryBinding>.of(sibling.bindings)) {
        binding.siblingChanged(entry);
      }
    }
    _trim();
  }

  // --- Budget ---------------------------------------------------------------

  void _trim() {
    for (final tier in AssetTier.values) {
      final unpinned = _unpinned[tier]!;
      final budget = _budgets.of(tier);
      while (_bytes[tier]! > budget && unpinned.isNotEmpty) {
        _evict(unpinned.first);
      }
    }
  }

  void _evict(_Entry entry) {
    _unpinned[entry.tier]!.remove(entry);
    if (identical(_entries[(entry.key, entry.spec)], entry)) {
      _entries.remove((entry.key, entry.spec));
    }
    final siblings = _byKey[entry.key];
    if (siblings != null && siblings.remove(entry) && siblings.isEmpty) {
      _byKey.remove(entry.key);
    }
    if (entry.paintable != null) {
      _bytes[entry.tier] = _bytes[entry.tier]! - entry.bytes;
    }
    entry.paintable?.dispose();
    entry
      ..disposeStandIn()
      ..paintable = null
      ..bytes = 0;
  }

  void _detached(_EntryBinding binding) {
    final entry = binding.entry;
    entry.bindings.remove(binding);
    entry.demand.refresh(entry.bindings);
    if (binding.held) entry.syncKeep();
    if (entry.bindings.isNotEmpty) return;
    entry.attempt?.cancel();
    // Nobody draws it any more; a re-attach starts an attempt that tells.
    entry.download = null;
    _release(entry);
    _trim();
  }
}

// --- Internals --------------------------------------------------------------

final class _Entry {
  _Entry(this.key, this.spec);

  final ContentKey key;
  final AssetSpec spec;
  final Set<_EntryBinding> bindings = {};
  final _Demand demand = _Demand();
  AssetStage stage = AssetStage.none;
  AssetPaintable? paintable;
  // The thumbnail the content replaced, while a binding still fades over it.
  AssetPaintable? standIn;
  int standInHolders = 0;
  int bytes = 0;
  AssetTier tier = AssetTier.still;
  Object? lastError;
  AssetFailureKind? failureKind;
  _Attempt? attempt;
  // The content's download, 0 to 1, as the last attempt reported it, or null
  // when it reported none. It outlives a failed or cancelled attempt: the
  // content is still missing.
  double? download;
  // Bindings of sibling entries that show this entry's stage.
  int borrowers = 0;

  bool get isPinned => bindings.isNotEmpty || borrowers > 0;

  // What a binding of a sibling entry may show of this one. A paintable that
  // plays may be in the middle of a loop, and the borrower's own entry starts
  // from frame 0: it is lent as its first-frame still, or not at all.
  AssetPaintable? get lent => switch (paintable) {
    final playing? when playing.isAnimated => playing.firstFrame,
    final other => other,
  };

  // The stage of what is lent: a playing paintable's still is a first frame.
  AssetStage get lentStage =>
      (paintable?.isAnimated ?? false) ? AssetStage.firstFrame : stage;

  // Whether the paintable keeps its frame: some binding holds it on screen.
  void syncKeep() =>
      paintable?.keepFrame(keep: bindings.any((binding) => binding.held));

  // Tells the bindings their download changed.
  void signalDownload() {
    for (final binding in List<_EntryBinding>.of(bindings)) {
      binding.downloadChanged();
    }
  }

  void disposeStandIn() {
    standIn?.dispose();
    standIn = null;
    standInHolders = 0;
  }

  bool get isFinal =>
      stage == AssetStage.full ||
      (stage == AssetStage.firstFrame &&
          spec.variant == AssetVariant.firstFrame);
}

final class _Demand implements AssetDemand {
  @override
  AssetPriority priority = AssetPriority.visible;

  void refresh(Set<_EntryBinding> bindings) {
    priority = bindings.any((binding) => binding.visible)
        ? AssetPriority.visible
        : AssetPriority.preload;
  }
}

final class _Attempt implements AssetProgress {
  _Attempt(this._scope, this._entry);

  final AssetCacheScope _scope;
  final _Entry _entry;
  AssetTask? task;
  bool ended = false;

  bool get _live => !ended && identical(_entry.attempt, this);

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) {
    if (!_live || _scope._disposed) {
      paintable.dispose();
      return;
    }
    _scope._advance(_entry, stage, paintable, bytes, tier);
  }

  @override
  void download(double fraction) {
    if (!_live || _scope._disposed) return;
    final value = fraction.clamp(0.0, 1.0);
    if (_entry.download == value) return;
    _entry.download = value;
    _entry.signalDownload();
  }

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) {
    if (!_live) return;
    _entry
      ..lastError = error
      ..failureKind = kind;
    _end();
  }

  @override
  void cancelled() {
    if (!_live) return;
    _end();
  }

  /// Called by the scope: stops the work for good.
  void cancel() {
    if (ended) return;
    final running = task;
    _end();
    running?.cancel();
  }

  // The download stays: a failed or cancelled one leaves the content missing,
  // and the surfaces keep drawing it there, as the reference client keeps its
  // arc while the file does not exist. The final stage, the last binding
  // leaving and the next attempt clear it.
  void _end() {
    ended = true;
    if (!identical(_entry.attempt, this)) return;
    _entry.attempt = null;
  }
}

final class _EntryBinding extends AssetBindingBase {
  _EntryBinding({
    required AssetCacheScope scope,
    required this.entry,
    required super.profile,
  }) : _scope = scope,
       super(
         key: entry.key,
         spec: entry.spec,
         placeholder: scope._placeholderOf(entry.key),
         clock: scope.clock,
       );

  final AssetCacheScope _scope;
  final _Entry entry;
  bool _registered = false;
  // Waiting to release the entry's stand-in.
  bool _holdsStandIn = false;
  // The sibling whose stage this binding shows while its entry is below that
  // stage and below its first frame, or null.
  _Entry? _borrowed;
  // A replay turns a profile that does not animate into one that does, for
  // this binding.
  bool _replayed = false;
  // The pass of a profile that does not loop is over. The animated stage is
  // the entry's final one, so the paintable never changes under it.
  bool _ended = false;
  late final _PlaybackTarget _target = _PlaybackTarget(
    clock.policy.frameIntervalFor(spec),
    _onTick,
  );

  /// Called by the scope when the entry's download changed.
  void downloadChanged() => signal();

  @override
  double? get downloadProgress => isDetached ? null : entry.download;

  /// Called by the scope when the entry gained a stage.
  void entryChanged() {
    reborrow();
    syncPlayback();
    signal();
  }

  /// Called by the scope when [sibling], another entry of this key, gained a
  /// stage: what this binding shows changes when it borrows from it or may
  /// borrow it now.
  void siblingChanged(_Entry sibling) {
    if (_borrowed == null && _ownStage.index >= AssetStage.firstFrame.index) {
      return;
    }
    final before = _borrowed;
    reborrow();
    if (identical(before, sibling) || identical(_borrowed, sibling)) {
      syncPlayback();
      signal();
    }
  }

  /// Borrows the best sibling stage while the entry's own, as this binding
  /// shows it, is below that stage and below its first frame; gives the
  /// sibling back otherwise.
  void reborrow() {
    final own = _ownStage;
    _Entry? next;
    // The sibling's stage as this binding would show it (a profile that does
    // not autoplay waits for the full asset there too) must beat its own.
    if (!isDetached && own.index < AssetStage.firstFrame.index) {
      if (_scope._siblingOf(entry, own) case final sibling?
          when _lentStageOf(sibling).index > own.index) {
        next = sibling;
      }
    }
    final previous = _borrowed;
    if (identical(next, previous)) return;
    _borrowed = next;
    if (next != null) _scope._borrow(next);
    if (previous != null) _scope._giveBack(previous);
  }

  // What this binding paints: its entry's paintable, or the borrowed one.
  AssetPaintable? get _shown => switch (_borrowed) {
    final sibling? => sibling.lent,
    null => entry.paintable,
  };

  // The paint that follows a tick is what steps the paintable, so a pass that
  // ended is seen on the tick after: here, the frame after the one that held.
  void _onTick() {
    if (!profile.loop && !_ended && (_shown?.isHolding ?? false)) {
      _ended = true;
      syncPlayback();
    }
    signal();
  }

  @override
  bool get animates => profile.animate || _replayed;

  @override
  AssetPlayback get playback {
    if (isDetached) return AssetPlayback.idle;
    if (_ended) return AssetPlayback.ended;
    return _registered ? AssetPlayback.playing : AssetPlayback.idle;
  }

  @override
  bool replay() {
    if (isDetached || !visible) return false;
    final paintable = entry.paintable;
    if (paintable == null ||
        !paintable.isAnimated ||
        _ownStage != entry.stage) {
      return false;
    }
    if (_ended) {
      _ended = false;
    } else if (animates) {
      return false;
    }
    _replayed = true;
    syncPlayback();
    signal();
    return true;
  }

  @override
  AssetReadiness get liveReadiness {
    if (_borrowed case final sibling?) {
      // Shown, not final: the entry's own decode is still to come.
      return AssetReadiness(_lentStageOf(sibling));
    }
    final stage = _ownStage;
    return AssetReadiness(
      stage,
      isFinal: entry.isFinal && stage == entry.stage,
    );
  }

  // A profile that does not autoplay shows its placeholder until the full
  // asset exists; a first-frame-only spec has nothing later to wait for.
  AssetStage _stageOf(_Entry of) =>
      of.stage == AssetStage.firstFrame &&
          !profile.autoplayFirstFrame &&
          of.spec.variant == AssetVariant.full
      ? AssetStage.placeholder
      : of.stage;

  // A sibling's stage as this binding shows what it lends: a playing
  // sibling lends a first frame.
  AssetStage _lentStageOf(_Entry sibling) {
    final stage = _stageOf(sibling);
    return stage.index > sibling.lentStage.index ? sibling.lentStage : stage;
  }

  // The entry's own stage as this binding paints it, borrowing aside.
  AssetStage get _ownStage => _stageOf(entry);

  @override
  AssetPaintable get livePaintable {
    if (_borrowed case _Entry(:final lent?)) return lent;
    final paintable = entry.paintable;
    if (paintable == null || _ownStage != entry.stage) {
      return _scope._placeholderOf(entry.key);
    }
    return paintable;
  }

  // A surface that paints the content opaque has nothing left to fade over the
  // thumbnail, so it is released with that paint: surfaces that do not fade
  // never have to know about it.
  @override
  void paint(Canvas canvas, Rect rect, {Color? tint, double opacity = 1}) {
    super.paint(canvas, rect, tint: tint, opacity: opacity);
    if (opacity >= 1 &&
        _holdsStandIn &&
        _ownStage.index > AssetStage.placeholder.index) {
      releaseStandIn();
    }
  }

  @override
  bool paintStandIn(Canvas canvas, Rect rect) {
    final standIn = entry.standIn;
    if (!_holdsStandIn || standIn == null || isDetached) return false;
    standIn.paint(canvas, rect, AssetPaintContext(fit: profile.fit));
    return true;
  }

  @override
  void releaseStandIn() {
    if (!_holdsStandIn) return;
    _holdsStandIn = false;
    if (--entry.standInHolders <= 0) entry.disposeStandIn();
  }

  @override
  Object? get lastError => entry.lastError;

  @override
  bool get isPlaying => _registered && !clock.isPaused;

  @override
  void retry() {
    if (isDetached) return;
    if (entry.attempt == null && !entry.isFinal) _scope._start(entry);
  }

  @override
  void onVisibleChanged() {
    entry.demand.refresh(entry.bindings);
    syncPlayback();
  }

  @override
  void onHeldChanged() => syncPlayback();

  /// Registers with or leaves the playback clock to match what the binding
  /// wants now.
  void syncPlayback() {
    entry.syncKeep();
    final wanted =
        !isDetached &&
        visible &&
        !held &&
        animates &&
        !_ended &&
        (_shown?.isAnimated ?? false);
    if (wanted == _registered) return;
    _registered = wanted;
    if (wanted) {
      // A binding that starts to play wakes a playback another binding of
      // the entry left holding its rest frame; a running one is left alone.
      _shown?.restart();
      clock.register(_target);
    } else {
      clock.unregister(_target);
    }
  }

  @override
  void releaseResources() {
    releaseStandIn();
    if (_borrowed case final sibling?) {
      _borrowed = null;
      _scope._giveBack(sibling);
    }
    if (_registered) {
      _registered = false;
      clock.unregister(_target);
    }
    _scope._detached(this);
  }
}

final class _PlaybackTarget implements PlaybackTarget {
  _PlaybackTarget(this.frameInterval, this._onTick);

  @override
  final Duration frameInterval;

  final VoidCallback _onTick;

  @override
  void tick(Duration now) => _onTick();
}
