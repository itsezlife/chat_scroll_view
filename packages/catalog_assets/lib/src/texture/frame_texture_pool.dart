import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/src/asset/asset_texture.dart';
import 'package:catalog_assets/src/texture/frame_texture_host.dart';
import 'package:flutter/foundation.dart';

/// One playing asset's claim on a texture of a [FrameTexturePool], ended
/// exactly once.
///
/// While it lasts the texture is the holder's alone: its worker locks and
/// posts [texture] by id, and a surface composites it. [release] gives it back
/// to the pool to idle; [discard] gives it back broken (a lock that keeps
/// failing), and the pool destroys it instead of handing it out again.
final class FrameTextureLease {
  FrameTextureLease._(this.texture, this._onEnd, {required this.showsFrame});

  /// The texture claimed: its id, its pixel size (the whole size class) and
  /// the size of the frame it holds.
  final AssetTexture texture;

  /// Whether the texture still shows the last frame of the asset it was
  /// leased for: the asset gave it back with `release(showing:)`, asked for
  /// it again by the same key, and nothing was posted to it between. Every
  /// frame queued on it is that asset's own, so it may be shown at once.
  final bool showsFrame;

  void Function({required bool discard, Object? showing})? _onEnd;

  /// Whether [release] or [discard] was called.
  bool get isReleased => _onEnd == null;

  /// Ends the claim; the texture idles in the pool. Idempotent.
  ///
  /// [showing], when given, names the asset whose last frame the texture
  /// shows now (its holder posted it and goes on from it later): a
  /// [FrameTexturePool.lease] for the same asset takes this texture back
  /// first and shows it at once, while the pool keeps the frame (see *Kept
  /// frames* there).
  void release({Object? showing}) => _end(discard: false, showing: showing);

  /// Ends the claim and destroys the texture. Idempotent, and nothing after a
  /// [release].
  void discard() => _end(discard: true);

  void _end({required bool discard, Object? showing}) {
    final onEnd = _onEnd;
    _onEnd = null;
    onEnd?.call(discard: discard, showing: showing);
  }
}

/// The textures of one [FrameTextureHost], pooled by size class and paid for
/// out of a byte budget (ADR 043, "Pool").
///
/// A host registers one pool with the `AssetCacheScope`; a playing asset asks
/// it for a texture at each lease and keeps its slot on a dynamic page when it
/// answers null. The pool never blocks and never fails a lease.
///
/// ## Size classes
///
/// The classes are those of the dynamic pages (64, 128, 256 and 512 px by
/// default). A texture is square at its class edge, and an asset leases the
/// smallest class its longer side fits in; above the largest class it gets
/// none, as an asset above the page cap shows its still.
///
/// ## Creating only off the frame path
///
/// [lease] never creates: it hands out an idle texture of the class or
/// nothing. Textures are made by [warm], which the host calls when a surface
/// that plays opens, and which waits while [scrolling] is true: creating a
/// texture during a glide was the one hitch source the prototype showed.
///
/// ## Budget
///
/// Every texture counts `edge * edge * 4` bytes for each buffer of the host's
/// queue ([FrameTextureHost.buffersPerTexture]), leased or idle, from the
/// moment it is asked for until it is destroyed. A [warm] the budget does not
/// cover makes room by destroying idle textures of other classes, released
/// longest ago first; it stops when even those would not cover it. Leased
/// textures are never destroyed for room. The default, 48 MiB, is the
/// default of the dynamic frame pages (ADR 022), which a texture replaces for
/// the asset that holds it.
///
/// ## Kept frames
///
/// A texture released with the asset it shows (`release(showing:)`: a cell
/// that left the screen) keeps that frame for the asset. A lease that names
/// the same asset takes it back before any other and without the reuse delay
/// (every frame queued on it is the asset's own), and its holder shows it at
/// once instead of the first-frame still. Another asset takes such a texture
/// only when its class has no idle texture that keeps no frame, and [warm]
/// does not count it as idle, so the cells that come on screen get textures
/// of their own while the ones that left keep theirs. What the kept frames
/// cost together is bounded by [keptFrameBytes], within [budgetBytes]; past
/// it the frame kept longest is forgotten and its texture idles like any
/// other.
///
/// ## Idle textures
///
/// A released texture idles for the next lease of its class, but is not
/// leased again for [reuseDelay]: the surface that showed it keeps its layer
/// until it repaints (an animated one on its next playback tick), and the
/// raster thread may not have drawn the last frame that holds it yet. A
/// frame the next holder posted meanwhile would show there, one frame of
/// another asset. A lease takes the texture released longest ago. Past
/// [idleLimit] idle textures the oldest is destroyed; [releaseIdle] (memory
/// pressure, through the scope) destroys every idle one. Leased textures
/// stay: they are on screen.
///
/// Single-threaded, on the UI isolate. The pool owns its textures and not the
/// host: [dispose] destroys the textures and leaves the host alone.
final class FrameTexturePool {
  /// Creates a pool over [host].
  ///
  /// [now] is the time [reuseDelay] is measured on, by default a stopwatch
  /// started here. [scrolling] is the host's signal that a surface scrolls (a drag or a
  /// fling); null means never. Throws an [ArgumentError] for size classes
  /// that are empty or not strictly ascending, and for a budget that does not
  /// cover one texture of the smallest class.
  FrameTexturePool({
    required this.host,
    this.scrolling,
    this.sizeClasses = const [64, 128, 256, 384, 512],
    this.budgetBytes = defaultBudgetBytes,
    this.idleLimit = defaultIdleLimit,
    this.reuseDelay = defaultReuseDelay,
    this.keptFrameBytes = defaultKeptFrameBytes,
    Duration Function()? now,
  }) : _now = now ?? _stopwatch() {
    if (sizeClasses.isEmpty ||
        sizeClasses.first <= 0 ||
        !_ascending(sizeClasses)) {
      throw ArgumentError.value(
        sizeClasses,
        'sizeClasses',
        'must be positive and strictly ascending',
      );
    }
    final smallest = bytesOfClass(sizeClasses.first);
    if (budgetBytes < smallest) {
      throw ArgumentError.value(
        budgetBytes,
        'budgetBytes',
        'does not cover one texture of the smallest class ($smallest bytes)',
      );
    }
  }

  /// The default of [budgetBytes]: the dynamic pages' default (ADR 022).
  static const int defaultBudgetBytes = 48 * 1024 * 1024;

  /// The default of [idleLimit]: about a screen of a sticker grid, so leaving
  /// a screen and coming back finds its textures.
  static const int defaultIdleLimit = 24;

  /// The default of [reuseDelay]: longer than the playback tick of any
  /// animated asset and than the raster pipeline.
  static const Duration defaultReuseDelay = Duration(milliseconds: 150);

  /// The default of [keptFrameBytes]: half the default budget, about a
  /// screen of a sticker grid on Android (24 cells of 256 px textures of four
  /// buffers, 1 MiB each), as many as [defaultIdleLimit]. Scrolling back a
  /// screen brings back the cells that left it while as many leave the other
  /// edge. Leased textures still come first: a warm for cells on screen
  /// that the budget does not cover leaves them to take kept ones.
  static const int defaultKeptFrameBytes = 24 * 1024 * 1024;

  /// The platform's maker of textures.
  final FrameTextureHost host;

  /// Whether a surface scrolls now; [warm] creates nothing while it does.
  final ValueListenable<bool>? scrolling;

  /// The edges of the texture classes, ascending.
  final List<int> sizeClasses;

  /// What the textures may cost together, in bytes.
  final int budgetBytes;

  /// How many released textures may idle before the oldest is destroyed.
  final int idleLimit;

  /// How long a released texture idles before a lease may take it.
  final Duration reuseDelay;

  /// What the idle textures that keep an asset's frame may cost together;
  /// part of [budgetBytes], not on top of it.
  final int keptFrameBytes;

  // The time since some fixed point; the reuse delay is measured on it.
  final Duration Function() _now;

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  // Idle textures, least recently released first: id to size class.
  final Map<int, int> _idle = {};
  // When each idle texture that was leased before was released; a texture
  // that was only warmed is not here.
  final Map<int, Duration> _releasedAt = {};
  // Idle textures that keep the last frame of an asset, kept longest ago
  // first: id to the asset.
  final Map<int, Object> _kept = {};
  int _keptBytes = 0;
  // Leased textures: id to size class.
  final Map<int, int> _leased = {};
  // Creations asked of the host and not answered yet, per class.
  final Map<int, int> _creating = {};
  int _bytes = 0;
  bool _disposed = false;
  // The one wait for [scrolling] to clear that every waiting warm shares.
  Completer<void>? _scrollEnd;
  VoidCallback? _scrollListener;

  /// What the textures cost now, leased, idle and being created, in bytes.
  int get bytes => _bytes;

  /// Textures released and waiting for a lease.
  int get idleTextures => _idle.length;

  /// Idle textures that keep the last frame of the asset that released them.
  int get keptFrames => _kept.length;

  /// Textures leased now.
  int get leasedTextures => _leased.length;

  /// Leases that found no texture of their class (and so stayed on, or took,
  /// a page slot) since the pool was made; a lease above the largest class
  /// is not counted. A profiler's reading of how often textures ran short.
  int get missedLeases => _missedLeases;
  int _missedLeases = 0;

  /// Warms that stopped short because the budget held only leased textures
  /// and textures of their own class, since the pool was made: the class
  /// stays on page slots until a lease ends.
  int get warmsShortOfRoom => _warmsShortOfRoom;
  int _warmsShortOfRoom = 0;

  /// The textures of each size class now: leased, idle, and of the idle ones
  /// those that keep an asset's frame. Counted when read.
  Map<int, ({int leased, int idle, int kept})> classCounts() => {
    for (final sizeClass in sizeClasses)
      sizeClass: (
        leased: _leased.values.where((c) => c == sizeClass).length,
        idle: _idle.values.where((c) => c == sizeClass).length,
        kept: _kept.keys.where((id) => _idle[id] == sizeClass).length,
      ),
  };

  /// What one texture of [sizeClass] costs.
  int bytesOfClass(int sizeClass) =>
      sizeClass * sizeClass * 4 * host.buffersPerTexture;

  /// The class an asset of [width] x [height] pixels leases, or null above the
  /// largest.
  int? classOf(int width, int height) {
    final edge = math.max(width, height);
    for (final sizeClass in sizeClasses) {
      if (edge <= sizeClass) return sizeClass;
    }
    return null;
  }

  /// An idle texture for an asset of [width] x [height] pixels, or null when
  /// its class has none (or it is above the largest class, or the pool is
  /// disposed): the asset then keeps its page slot. Never creates one.
  ///
  /// The lease's texture names the frame it holds ([width] x [height],
  /// centred), so a surface places the frame, not the square around it.
  ///
  /// [showing] names the asset that asks: a texture it released showing its
  /// frame is taken back first, at once, and the lease says so
  /// ([FrameTextureLease.showsFrame]); see *Kept frames* above.
  FrameTextureLease? lease(int width, int height, {Object? showing}) {
    if (_disposed) return null;
    final sizeClass = classOf(width, height);
    if (sizeClass == null) return null;
    final own = switch (showing) {
      final asset? => _keptFor(asset, sizeClass),
      null => null,
    };
    final id = own ?? _idleOf(sizeClass);
    if (id == null) {
      _missedLeases++;
      return null;
    }
    _forget(id);
    _idle.remove(id);
    _releasedAt.remove(id);
    _leased[id] = sizeClass;
    return FrameTextureLease._(
      AssetTexture(
        id: id,
        width: sizeClass,
        height: sizeClass,
        frameWidth: width,
        frameHeight: height,
      ),
      ({required discard, showing}) =>
          _ended(id, discard: discard, showing: showing),
      showsFrame: own != null,
    );
  }

  int? _keptFor(Object asset, int sizeClass) {
    for (final MapEntry(:key, :value) in _kept.entries) {
      if (value == asset && _idle[key] == sizeClass) return key;
    }
    return null;
  }

  // The released longest ago of the class (the idle map is in release order)
  // that waited the reuse delay, one that keeps no frame before one that does.
  int? _idleOf(int sizeClass) {
    final now = _now();
    int? keeping;
    for (final MapEntry(:key, :value) in _idle.entries) {
      if (value != sizeClass) continue;
      final releasedAt = _releasedAt[key];
      if (releasedAt != null && now - releasedAt < reuseDelay) continue;
      if (!_kept.containsKey(key)) return key;
      keeping ??= key;
    }
    return keeping;
  }

  // The idle texture [id] keeps no frame from now on. Before it leaves the
  // idle map: its class is read there.
  void _forget(int id) {
    if (_kept.remove(id) == null) return;
    _keptBytes -= bytesOfClass(_idle[id]!);
  }

  /// Creates textures of [sizeClass] until it has [count] idle ones (at most
  /// [idleLimit]), off the frame path.
  ///
  /// Waits while [scrolling] is true, before each creation; destroys idle
  /// textures of other classes when the budget does not cover another
  /// texture, and stops early when even that would not, when the host
  /// refuses one, or when the pool is disposed. Never fails. Calls that overlap share the
  /// work: a texture being created counts toward every call's [count].
  ///
  /// Throws an [ArgumentError] for a [sizeClass] that is not one of
  /// [sizeClasses].
  Future<void> warm(int sizeClass, int count) async {
    if (!sizeClasses.contains(sizeClass)) {
      throw ArgumentError.value(sizeClass, 'sizeClass', 'is not a size class');
    }
    final wanted = math.min(count, idleLimit);
    while (!_disposed) {
      // A texture that keeps an asset's frame waits for that asset.
      final have =
          _idle.entries
              .where((e) => e.value == sizeClass && !_kept.containsKey(e.key))
              .length +
          (_creating[sizeClass] ?? 0);
      if (have >= wanted) return;
      if (scrolling?.value ?? false) {
        await _scrollEnded();
        continue;
      }
      final cost = bytesOfClass(sizeClass);
      if (!_makeRoom(cost, sizeClass)) {
        _warmsShortOfRoom++;
        return;
      }
      _bytes += cost;
      _creating[sizeClass] = (_creating[sizeClass] ?? 0) + 1;
      int? id;
      try {
        id = await host.create(sizeClass, sizeClass);
      } on Object catch (error, stackTrace) {
        // The contract says a host answers null for a refusal; one that
        // throws is a bug to see, and the class just stays short.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'catalog_assets',
            context: ErrorDescription('while creating a frame texture'),
          ),
        );
      } finally {
        _creating[sizeClass] = _creating[sizeClass]! - 1;
      }
      if (id == null) {
        _bytes -= cost;
        return;
      }
      if (_disposed) {
        _bytes -= cost;
        host.destroy(id);
        return;
      }
      _idle[id] = sizeClass;
    }
  }

  // Whether [cost] fits the budget, after destroying idle textures of other
  // classes, released longest ago first, as far as that makes it fit. An idle
  // texture is on no screen; a warm is for a lease that waits on a page slot,
  // uploading a frame page on every tick. Without this, textures warmed for a
  // surface that is gone (a chat's stickers, a page left) hold the budget
  // while the surface on screen plays from pages. Nothing is destroyed when
  // even every idle texture of the other classes would not make it fit.
  bool _makeRoom(int cost, int sizeClass) {
    var over = _bytes + cost - budgetBytes;
    if (over <= 0) return true;
    final victims = <int>[];
    for (final MapEntry(:key, :value) in _idle.entries) {
      if (value == sizeClass) continue;
      victims.add(key);
      over -= bytesOfClass(value);
      if (over <= 0) break;
    }
    if (over > 0) return false;
    for (final id in victims) {
      _forget(id);
      _releasedAt.remove(id);
      _destroy(id, _idle.remove(id)!);
    }
    return true;
  }

  /// Forgets the frame an idle texture keeps for [showing]: the asset will
  /// not go on from it (it was disposed; one that takes its key starts at
  /// its first frame). The texture idles like any other.
  void forgetFrameOf(Object showing) {
    final ids = [
      for (final MapEntry(:key, :value) in _kept.entries)
        if (value == showing) key,
    ];
    ids.forEach(_forget);
  }

  /// Destroys every idle texture: the answer to memory pressure. Leased
  /// textures stay.
  void releaseIdle() {
    final idle = List.of(_idle.entries);
    _idle.clear();
    _releasedAt.clear();
    _kept.clear();
    _keptBytes = 0;
    for (final MapEntry(:key, :value) in idle) {
      _destroy(key, value);
    }
  }

  /// Destroys the idle textures now and each leased one when its lease ends;
  /// leases find nothing from now on. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    releaseIdle();
    _stopWaitingForScroll();
  }

  void _ended(int id, {required bool discard, Object? showing}) {
    final sizeClass = _leased.remove(id);
    if (sizeClass == null) return;
    if (discard || _disposed) {
      _destroy(id, sizeClass);
      return;
    }
    _idle[id] = sizeClass;
    _releasedAt[id] = _now();
    if (showing != null) _keep(id, showing, sizeClass);
    while (_idle.length > idleLimit) {
      final oldest = _idle.keys.first;
      _forget(oldest);
      _releasedAt.remove(oldest);
      _destroy(oldest, _idle.remove(oldest)!);
    }
  }

  // One texture keeps an asset's frame: one it kept before (lost to a canvas,
  // say) forgets it. Past the kept budget the frame kept longest goes first.
  void _keep(int id, Object asset, int sizeClass) {
    forgetFrameOf(asset);
    _kept[id] = asset;
    _keptBytes += bytesOfClass(sizeClass);
    while (_keptBytes > keptFrameBytes) {
      _forget(_kept.keys.first);
    }
  }

  void _destroy(int id, int sizeClass) {
    _bytes -= bytesOfClass(sizeClass);
    host.destroy(id);
  }

  Future<void> _scrollEnded() {
    final waiting = _scrollEnd;
    if (waiting != null) return waiting.future;
    final signal = scrolling!;
    final completer = _scrollEnd = Completer<void>();
    void listener() {
      if (!signal.value) _stopWaitingForScroll();
    }

    _scrollListener = listener;
    signal.addListener(listener);
    return completer.future;
  }

  void _stopWaitingForScroll() {
    final listener = _scrollListener;
    if (listener != null) scrolling?.removeListener(listener);
    _scrollListener = null;
    final completer = _scrollEnd;
    _scrollEnd = null;
    completer?.complete();
  }
}

bool _ascending(List<int> values) {
  for (var i = 1; i < values.length; i++) {
    if (values[i] <= values[i - 1]) return false;
  }
  return true;
}
