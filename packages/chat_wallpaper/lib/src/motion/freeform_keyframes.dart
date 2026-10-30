import 'dart:async';
import 'dart:ui' as ui;

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/render/freeform_gradient.dart';
import 'package:flutter/foundation.dart';

/// What a freeform fill paints in one frame: [base] at full opacity, then
/// [overlay], when present, at [overlayOpacity] over it.
typedef FreeformFrame = ({
  ui.Image base,
  ui.Image? overlay,
  double overlayOpacity,
});

/// A keyframe named by the colour arrangement it shows: the points of [phase]
/// [third] thirds of the way in from their slots at `phase + 1`.
///
/// A step's progress-`0` frame is never named: it is byte-identical to the
/// phase it leaves at progress `1`, so it is always spelled as that
/// `(phase + 1, third: 3)`. One arrangement therefore has one name, and a
/// frame shared by two steps — or by two runs — is one map entry.
typedef _Arrangement = ({int phase, int third});

/// Rasterized keyframes of one [ChatWallpaper$Freeform]: a store of the
/// arrangements of its ring, read through the strip of the current run.
///
/// A `ChatWallpaperMotionController` holds one instance per wallpaper value and
/// hands the same instance to every view painting that value, so all copies
/// show identical images in the same frame.
///
/// ## Ring
///
/// A wallpaper has [ringLength] distinct keyframes: every settled phase of
/// the [FreeformGradient.phaseCount]-slot ring and the [perStep] thirds of
/// each step between neighbouring phases. While [warmsRing] is set, the store
/// keeps every keyframe it has landed until [dispose] and warms the ones it
/// lacks in the background, so every run on a held wallpaper ends up
/// painting frames that are already held. A full ring costs [ringLength]
/// textures of [FreeformGradient.width] × [FreeformGradient.height] RGBA
/// pixels, about 460 KB.
///
/// ## Strip
///
/// A run of `n` steps from phase `from` is `3n + 1` frames: `from` settled,
/// then [perStep] frames per step at progress `⅓`, `⅔` and `1`. A settled
/// wallpaper is the one-frame strip of a zero-step run. Frames are identified
/// by the arrangement they show, so each step's final frame doubles as the
/// next step's start, and every strip is a subset of the ring: on a warm ring
/// each frame a run reads is already held.
///
/// A full-ring strip (`n` = [FreeformGradient.phaseCount]) holds every
/// arrangement of the wallpaper and ends on the one it starts from, so its
/// first and last frames are one image. Motion that keeps circling the ring
/// in either direction paints from it indefinitely without another raster.
///
/// ## Warming
///
/// Every keyframe is rasterized with [FreeformGradient.imageInBackground]:
/// its pixels are computed on a background isolate, so the UI isolate only
/// decodes them. Rasters are requested one frame at a time: the next request
/// goes out only once the previous frame has landed, so decodes and texture
/// uploads spread across frames instead of piling into one. Each landed
/// frame notifies listeners. The next frame requested is the first one not
/// yet held of:
///
/// 1. After [settle], the frame the run rests on. During a run, the strip's
///    frames in playing order; a full-ring strip, which plays in either
///    direction, outward from its start.
/// 2. While [warmsRing] is set, the whole ring outward from the phase the
///    store rests at, or the run started from: by ring distance, each
///    distance first on the `phase − 1` side (where shifts and swirls move),
///    then on the `phase + 1` side (where the spin moves).
///
/// [run] and [settle] only reorder what is requested next: a raster already
/// on its way lands first, and nothing waits for the rest. Until a frame
/// lands, [frameAt] paints the nearest one that has.
///
/// A raster that fails is reported through [FlutterError.reportError] and
/// never requested again; warming moves on to the next frame, and runs keep
/// painting the nearest landed frame in its place.
///
/// ## Painting
///
/// [frameAt] maps a `(phase, progress)` of the run onto the strip. The base is
/// the nearest landed frame at or before that position; the next frame is
/// crossfaded over it only when both have landed. With nothing landed at or
/// before the position, the nearest landed frame after it is the base. Until
/// any frame of a new strip lands it keeps returning what the strip it
/// replaced showed last, so a new run never flashes back to the average
/// colour. It returns `null` only before the first frame ever lands.
///
/// ## Ownership
///
/// Owns every image it holds and releases them all on [dispose]. While
/// [warmsRing] is clear, a settled store keeps only the frame it rests on,
/// releasing every other as soon as that one has landed. A frame that lands
/// after [dispose] is disposed on arrival. Readers must not dispose images
/// returned by [frameAt]; a `RawImage` takes its own clone.
class FreeformKeyframes extends ChangeNotifier {
  /// Starts rasterizing the strip of a [steps]-step run from phase [from];
  /// the default zero-step run is [from] settled. With [warmsRing] the store
  /// goes on to keep and warm the whole ring, about 460 KB of textures; see
  /// [FreeformKeyframes.warmsRing].
  FreeformKeyframes(
    this.wallpaper, {
    required int from,
    required bool warmsRing,
    int steps = 0,
  }) : _warmsRing = warmsRing {
    run(from: from, steps: steps);
  }

  /// Number of keyframes rasterized per phase step, at progress `⅓`, `⅔` and
  /// `1`; the step's progress-`0` frame is the previous step's last.
  ///
  /// Frames between neighbouring keyframes are crossfades, so a step costs
  /// this many rasters however many frames it lasts.
  static const int perStep = 3;

  /// Number of distinct keyframes of one wallpaper: [perStep] for each of the
  /// [FreeformGradient.phaseCount] steps around the ring.
  static const int ringLength = FreeformGradient.phaseCount * perStep;

  /// Wallpaper whose keyframes this holds.
  final ChatWallpaper$Freeform wallpaper;

  /// Frames of the current run in order; never empty once constructed.
  List<_Arrangement> _strip = const [];

  /// Phase the run starts from: frame `0` is this phase settled.
  int get _from => _strip.first.phase;

  /// Landed frames, from anywhere on the ring.
  final Map<_Arrangement, ui.Image> _landed = {};

  /// Frame whose raster has been requested and has not landed yet; at most
  /// one is on its way at a time.
  _Arrangement? _inFlight;

  /// Frames whose raster failed. The renderer is deterministic, so a retry
  /// would fail the same way; they are never requested again.
  final Set<_Arrangement> _failed = {};

  /// What the replaced strip showed last; painted only while no frame of
  /// [_strip] has landed.
  _Arrangement? _replaced;

  /// Frame the ended run rests on; `null` while the run is in progress.
  _Arrangement? _rest;

  bool _warmsRing;

  bool _disposed = false;

  /// Whether the store keeps and warms the whole ring; see "Ring".
  ///
  /// While clear, the store requests only the frames of its strip during a
  /// run and, once settled, keeps only its resting frame, as a store that no
  /// run will play from needs (reduced motion, or a fill that never moves).
  /// Clearing it on a settled store releases every other frame once the
  /// resting one is held; setting it again resumes warming from the phase
  /// the store rests at.
  bool get warmsRing => _warmsRing;

  set warmsRing(bool value) {
    if (value == _warmsRing) return;
    _warmsRing = value;
    _releaseToRest();
    _requestNext();
  }

  /// Whether the store is settled and has landed the frame it rests on.
  bool get _restLanded => switch (_rest) {
    final rest? => _landed.containsKey(rest),
    null => false,
  };

  /// Whether the strip spans the whole ring, so its last frame is its first.
  bool get _isRing => _strip.length > ringLength;

  /// Replaces the strip with a [steps]-step run from phase [from] and moves
  /// its missing frames to the front of what is requested next.
  ///
  /// [steps] must be in `[0, phaseCount]`. Below `phaseCount` no arrangement
  /// repeats within the strip; at `phaseCount` only the first and last
  /// frames share one. A zero-step run is [from] settled, as if [settle]d
  /// there. Frames already held stay held, including those the new strip
  /// does not use.
  void run({required int from, required int steps}) {
    assert(!_disposed, 'run() called on disposed FreeformKeyframes');
    assert(
      steps >= 0 && steps <= FreeformGradient.phaseCount,
      'steps must be in [0, ${FreeformGradient.phaseCount}], got $steps',
    );
    _replaced = _shown();
    _strip = _stripOf(from: from, steps: steps);
    _rest = steps == 0 ? _strip.first : null;
    _releaseToRest();
    _requestNext();
  }

  /// Marks the run as ended at [phase] settled, which must be a phase the
  /// strip holds — the final one for a run that played out, any for a ring.
  ///
  /// The resting frame is requested next if it has not landed, and warming
  /// continues outward from [phase]. Other frames stay held while
  /// [warmsRing] is set; otherwise they are released as soon as the resting
  /// frame is held (now, or when it lands), so a gap never falls back past it.
  void settle({required int phase}) {
    final rest = (phase: phase, third: perStep);
    assert(
      _strip.contains(rest),
      'settle(phase: $phase) is not a settled frame of the strip',
    );
    _rest = rest;
    _releaseToRest();
    _requestNext();
  }

  /// Frame to paint when the run's colour points sit at [phase], [progress]
  /// (`0` … `1`) of the way into it — the motion controller's timeline.
  ///
  /// Between frames `i` and `i + 1` of the strip the base is frame `i` and the
  /// overlay frame `i + 1`, at the position's fraction of the way between
  /// them. The run's starting phase paints frame `0`; a phase the run never
  /// reaches paints its final frame. On a full ring the starting phase is
  /// the last step instead, so a position moving past either end continues
  /// on the frame both ends share.
  FreeformFrame? frameAt({required int phase, required double progress}) {
    final stepsIn = switch ((_from - phase) % FreeformGradient.phaseCount) {
      0 when _isRing => FreeformGradient.phaseCount,
      final steps => steps,
    };
    final position = ((stepsIn - 1 + progress) * perStep).clamp(
      0.0,
      _strip.length - 1.0,
    );
    final index = position.floor();
    final opacity = position - index;
    final exact = _landed[_strip[index]];
    final base = exact ?? _landed[_nearest(index)];
    if (base == null) return null;
    final overlay = switch (exact) {
      _? when opacity > 0 => _landed[_strip[index + 1]],
      _ => null,
    };
    return (base: base, overlay: overlay, overlayOpacity: opacity);
  }

  /// The frame a settled store rests on, once it has landed: what [frameAt]
  /// returns alone at the resting position. `null` during a run and before
  /// the frame lands.
  ui.Image? get restingImage => switch (_rest) {
    final rest? => _landed[rest],
    null => null,
  };

  /// Whether the keyframe [third] (`1` … [perStep]) thirds of the way into
  /// [phase] has landed and is held.
  @visibleForTesting
  bool holds({required int phase, required int third}) =>
      _landed.containsKey((phase: phase, third: third));

  /// Strip frame [index] if landed, else the nearest landed one before it,
  /// then after it, then what the replaced strip showed last.
  _Arrangement? _nearest(int index) {
    for (var i = index; i >= 0; i--) {
      if (_landed.containsKey(_strip[i])) return _strip[i];
    }
    for (var i = index + 1; i < _strip.length; i++) {
      if (_landed.containsKey(_strip[i])) return _strip[i];
    }
    return switch (_replaced) {
      final replaced? when _landed.containsKey(replaced) => replaced,
      _ => null,
    };
  }

  /// What the fill shows once the run is over: the nearest landed frame to
  /// the resting one once settled, else the furthest landed frame.
  _Arrangement? _shown() => switch (_rest) {
    final rest? => _nearest(_strip.lastIndexOf(rest)),
    null => _nearest(_strip.length - 1),
  };

  /// Releases every frame but the resting one while [warmsRing] is clear and
  /// that frame has landed.
  void _releaseToRest() {
    if (_warmsRing || !_restLanded) return;
    for (final MapEntry(key: arrangement, value: image)
        in _landed.entries.toList()) {
      if (arrangement == _rest) continue;
      _landed.remove(arrangement);
      image.dispose();
    }
  }

  /// Requests the first frame of [_wanted] not yet held, unless a raster is
  /// already on its way; its landing requests the one after.
  void _requestNext() {
    if (_disposed || _inFlight != null) return;
    for (final arrangement in _wanted()) {
      if (_landed.containsKey(arrangement) || _failed.contains(arrangement))
        continue;
      _render(arrangement);
      return;
    }
  }

  /// Frames in the order they are requested, repeats included; see
  /// "Warming".
  Iterable<_Arrangement> _wanted() sync* {
    switch (_rest) {
      case final rest?:
        yield rest;
      case null when _isRing:
        yield* _outwardFrom(_from);
      case null:
        yield* _strip;
    }
    if (_warmsRing) yield* _outwardFrom(_rest?.phase ?? _from);
  }

  void _render(_Arrangement arrangement) {
    _inFlight = arrangement;
    final (:phase, :third) = arrangement;
    unawaited(
      FreeformGradient.imageInBackground(
        wallpaper,
        phase: phase,
        progress: third / perStep,
      ).then(
        (image) {
          _inFlight = null;
          if (_disposed) {
            image.dispose();
            return;
          }
          _landed[arrangement] = image;
          _releaseToRest();
          notifyListeners();
          _requestNext();
        },
        onError: (Object error, StackTrace stack) {
          _inFlight = null;
          _failed.add(arrangement);
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'chat_wallpaper',
              context: ErrorDescription(
                'while rasterizing freeform keyframe $arrangement',
              ),
            ),
          );
          _requestNext();
        },
      ),
    );
  }

  /// Arrangements of a [steps]-step run from [from], in playing order.
  static List<_Arrangement> _stripOf({required int from, required int steps}) =>
      [
        (phase: from, third: perStep),
        for (var step = 1; step <= steps; step++)
          for (var third = 1; third <= perStep; third++)
            (phase: (from - step) % FreeformGradient.phaseCount, third: third),
      ];

  /// Every arrangement of the ring once, nearest to [phase] settled first:
  /// [phase] itself, then each ring distance on the `phase − 1` side before
  /// the `phase + 1` side.
  static Iterable<_Arrangement> _outwardFrom(int phase) sync* {
    final ring = _stripOf(from: phase, steps: FreeformGradient.phaseCount);
    yield ring.first;
    for (var distance = 1; distance <= ringLength ~/ 2; distance++) {
      yield ring[distance];
      if (distance < ringLength - distance) yield ring[ringLength - distance];
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in _landed.values) {
      image.dispose();
    }
    _landed.clear();
    super.dispose();
  }
}
