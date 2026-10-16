import 'dart:collection';

import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_binding_base.dart';
import 'package:catalog_assets/src/asset/asset_cache_budgets.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/asset/circle_placeholder.dart';
import 'package:catalog_assets/src/glyph/glyph_binding.dart';
import 'package:catalog_assets/src/glyph/glyph_sprite_source.dart';
import 'package:catalog_assets/src/playback/playback_clock.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// The asset cache of one host: entries keyed by content and [AssetSpec],
/// bindings that pin them, a byte-budgeted LRU for the ones nobody holds, and
/// the playback clock their animations advance by.
///
/// Created by the host and handed to the surfaces that attach; there is no
/// static instance. It owns what it made (entries, the default clock, the
/// default placeholder) and nothing it was handed (a producer, a glyph source,
/// a clock, the memory-pressure signal): [dispose] leaves those alone.
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
  /// entries when it fires. [placeholder] is what a binding paints before any
  /// stage exists (a circle by default).
  AssetCacheScope({
    AssetProducer? producer,
    GlyphSpriteSource? glyphSource,
    AssetCacheBudgets budgets = AssetCacheBudgets.defaults,
    PlaybackClock? clock,
    Listenable? memoryPressure,
    AssetPaintable? placeholder,
  }) : _producer = producer,
       _glyphSource = glyphSource,
       _budgets = budgets,
       _clock = clock ?? PlaybackClock(),
       _ownsClock = clock == null,
       _memoryPressure = memoryPressure,
       placeholder = placeholder ?? const CirclePlaceholder() {
    memoryPressure?.addListener(clearAll);
    glyphSource?.addPageListener(_onGlyphPage);
  }

  final AssetProducer? _producer;
  final PlaybackClock _clock;
  final bool _ownsClock;
  final Listenable? _memoryPressure;
  GlyphSpriteSource? _glyphSource;
  AssetCacheBudgets _budgets;
  bool _disposed = false;

  /// What a binding paints before its entry has produced any stage.
  final AssetPaintable placeholder;

  final Map<(ContentKey, AssetSpec), _Entry> _entries = {};
  // Entries nobody is bound to, per tier, least recently used first.
  final Map<AssetTier, LinkedHashSet<_Entry>> _unpinned = {
    for (final tier in AssetTier.values) tier: LinkedHashSet<_Entry>.identity(),
  };
  final Map<AssetTier, int> _bytes = {
    for (final tier in AssetTier.values) tier: 0,
  };
  final Set<GlyphBinding> _glyphBindings = {};

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
  /// Bindings already attached move to the new source in place: each gives
  /// back its hold on the old one, takes one on the new one and signals its
  /// listeners, so a host that plans a new atlas replaces it without
  /// re-attaching every leaf. The scope never disposes a source.
  set glyphSource(GlyphSpriteSource? value) {
    if (identical(_glyphSource, value)) return;
    _glyphSource?.removePageListener(_onGlyphPage);
    _glyphSource = value;
    value?.addPageListener(_onGlyphPage);
    for (final binding in List<GlyphBinding>.of(_glyphBindings)) {
      binding.rebind(value);
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
    final source = _glyphSource;
    if (key is ContentKey$Unicode && source != null) {
      final binding = GlyphBinding(
        key: key,
        spec: spec,
        profile: profile,
        placeholder: placeholder,
        clock: _clock,
        source: source,
        onDetach: _glyphBindings.remove,
      );
      _glyphBindings.add(binding);
      return binding;
    }
    final entry = _entries.putIfAbsent((key, spec), () => _Entry(key, spec));
    final binding = _EntryBinding(scope: this, entry: entry, profile: profile);
    _unpinned[entry.tier]!.remove(entry);
    entry.bindings.add(binding);
    entry.demand.refresh(entry.bindings);
    binding.syncPlayback();
    if (entry.attempt == null && !entry.isFinal) _start(entry);
    return binding;
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
    _memoryPressure?.removeListener(clearAll);
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
    if (previous != null && !identical(previous, paintable)) previous.dispose();
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
    }
    for (final binding in List<_EntryBinding>.of(entry.bindings)) {
      binding.entryChanged();
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
    if (entry.paintable != null) {
      _bytes[entry.tier] = _bytes[entry.tier]! - entry.bytes;
    }
    entry.paintable?.dispose();
    entry
      ..paintable = null
      ..bytes = 0;
  }

  void _detached(_EntryBinding binding) {
    final entry = binding.entry;
    entry.bindings.remove(binding);
    entry.demand.refresh(entry.bindings);
    if (entry.bindings.isNotEmpty) return;
    entry.attempt?.cancel();
    if (entry.stage.index <= AssetStage.placeholder.index) {
      _evict(entry);
    } else {
      _unpinned[entry.tier]!.add(entry);
    }
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
  int bytes = 0;
  AssetTier tier = AssetTier.still;
  Object? lastError;
  AssetFailureKind? failureKind;
  _Attempt? attempt;

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
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) {
    if (!_live) return;
    _end();
    _entry
      ..lastError = error
      ..failureKind = kind;
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

  void _end() {
    ended = true;
    if (identical(_entry.attempt, this)) _entry.attempt = null;
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
         placeholder: scope.placeholder,
         clock: scope.clock,
       );

  final AssetCacheScope _scope;
  final _Entry entry;
  bool _registered = false;
  late final _PlaybackTarget _target = _PlaybackTarget(
    clock.policy.frameIntervalFor(spec),
    signal,
  );

  /// Called by the scope when the entry gained a stage.
  void entryChanged() {
    syncPlayback();
    signal();
  }

  @override
  AssetReadiness get liveReadiness {
    final stage = _effectiveStage;
    return AssetReadiness(
      stage,
      isFinal: entry.isFinal && stage == entry.stage,
    );
  }

  // A profile that does not autoplay shows its placeholder until the full
  // asset exists; a first-frame-only spec has nothing later to wait for.
  AssetStage get _effectiveStage =>
      entry.stage == AssetStage.firstFrame &&
          !profile.autoplayFirstFrame &&
          spec.variant == AssetVariant.full
      ? AssetStage.placeholder
      : entry.stage;

  @override
  AssetPaintable get livePaintable {
    final paintable = entry.paintable;
    if (paintable == null || _effectiveStage != entry.stage) {
      return _scope.placeholder;
    }
    return paintable;
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

  /// Registers with or leaves the playback clock to match what the binding
  /// wants now.
  void syncPlayback() {
    final wanted =
        !isDetached &&
        visible &&
        profile.animate &&
        (entry.paintable?.isAnimated ?? false);
    if (wanted == _registered) return;
    _registered = wanted;
    if (wanted) {
      clock.register(_target);
    } else {
      clock.unregister(_target);
    }
  }

  @override
  void releaseResources() {
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
