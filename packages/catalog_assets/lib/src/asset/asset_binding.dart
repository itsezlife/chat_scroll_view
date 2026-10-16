import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:content_model/content_model.dart';

/// One surface's live attach to a cache entry, from `AssetCacheScope.attach`
/// until [detach].
///
/// A binding signals (as an [Observable]) when what it would paint changes:
/// its stage improved, a baked page it draws from landed, or an animation
/// ticked. The signal carries nothing; the surface reads [readiness] and
/// [paintable] and repaints.
///
/// ## What a binding pins
///
/// The entry it attached to stays in the cache, whatever the budget, until
/// the last binding on it detaches; a glyph binding also holds the atlas page
/// its glyph is on. Both are counts owned by the binding, taken at attach and
/// given back exactly once at [detach], so evicting, clearing or replacing
/// anything in the scope never changes them.
///
/// ## Failure
///
/// There is none to see. An asset that cannot be produced keeps the stage it
/// reached, usually [AssetStage.placeholder], whether the cause is a missing
/// network, a server error or bad data, and is attempted again on the next
/// attach, when the host reports connectivity (if the failure was transient)
/// or on [retry]. [lastError] is for logs and diagnostics, not for painting.
abstract interface class AssetBinding implements Observable {
  /// Which content.
  ContentKey get key;

  /// Which pixels the entry holds.
  AssetSpec get spec;

  /// How this surface uses the asset.
  AssetProfile get profile;

  /// How far the asset has come, as this binding would paint it.
  ///
  /// For a glyph on a platform that bakes this asks the atlas for its sprite,
  /// which may queue a page to be loaded again, so it is not a pure read.
  AssetReadiness get readiness;

  /// The best paintable available now, never null: before anything is
  /// produced it is the scope's placeholder. Read it when painting; do not
  /// keep it, a better stage replaces it.
  AssetPaintable get paintable;

  /// The error of the latest failed attempt for this entry, or null. Cleared
  /// when an attempt advances. Diagnostics only.
  Object? get lastError;

  /// Whether the playback clock is advancing this binding: its profile
  /// animates, it is [visible], its paintable animates and no pause layer is
  /// set.
  bool get isPlaying;

  /// Whether the surface shows this binding. Defaults to true. An invisible
  /// binding stays attached and pinned but is not advanced, so a leaf
  /// scrolled out of view costs no ticks.
  bool get visible;
  set visible(bool value);

  /// Paints the asset into [rect] at the scope's playback time: [paintable]
  /// clipped to the profile's corner radius, in [tint] and at [opacity].
  void paint(Canvas canvas, Rect rect, {Color? tint, double opacity = 1});

  /// Attempts the entry again now if nothing is running and it is not final.
  /// Does nothing otherwise.
  void retry();

  /// Gives the attach back. Idempotent: a second call changes nothing. After
  /// it the binding is silent and its [paintable] is the placeholder.
  void detach();
}
