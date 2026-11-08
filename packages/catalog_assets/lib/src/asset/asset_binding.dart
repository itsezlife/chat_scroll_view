import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_playback.dart';
import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';

/// One surface's live attach to a cache entry, from `AssetCacheScope.attach`
/// until [detach].
///
/// A binding signals (as a [Listenable]) when what it would paint changes:
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
abstract interface class AssetBinding implements Listenable {
  /// Which content.
  ContentKey get key;

  /// Which pixels the entry holds.
  AssetSpec get spec;

  /// How this surface uses the asset.
  AssetProfile get profile;

  /// How far the asset has come, as this binding would paint it.
  ///
  /// While the entry is below its first frame and another spec of the same
  /// content is further, this is that entry's stage, never final (see
  /// [paintable]).
  ///
  /// For a glyph on a platform that bakes this asks the atlas for its sprite,
  /// which may queue a page to be loaded again, so it is not a pure read.
  AssetReadiness get readiness;

  /// The best paintable available now, never null: before anything is
  /// produced it is the scope's placeholder. Read it when painting; do not
  /// keep it, a better stage replaces it.
  ///
  /// The same content decoded at another spec counts: while the entry is
  /// below its first frame, this is the paintable of the entry of the same
  /// key and decode mode with the best stage (the larger decode on a tie),
  /// drawn into this binding's rectangle with its own profile, until the
  /// entry's own stage catches up.
  AssetPaintable get paintable;

  /// The error of the latest failed attempt for this entry, or null. Cleared
  /// when an attempt advances. Diagnostics only.
  Object? get lastError;

  /// Whether the playback clock is advancing this binding: its profile
  /// animates, it is [visible], its paintable animates and no pause layer is
  /// set.
  bool get isPlaying;

  /// Where this binding's playback stands: advancing, held at its rest frame
  /// after a pass that did not loop, or not moving. Signalled to the
  /// listeners when it changes.
  ///
  /// The end of a pass is heard on the first playback tick after the paint
  /// that held the rest frame, so up to one frame late; a binding that has
  /// ended no longer costs ticks.
  AssetPlayback get playback;

  /// Plays another pass and says whether it started.
  ///
  /// It starts when the pass of a profile that does not loop has ended
  /// ([AssetPlayback.ended]), or when a profile that does not animate holds
  /// its first frame and has not been asked to play. It does nothing, returning
  /// false, while a pass is running or looping (a pass is never rewound), for a
  /// hidden or detached binding, and for an entry that has no animation yet.
  ///
  /// The decoded asset is one playback for every binding of its entry
  /// (`AssetProfile.animate`), so surfaces that share an entry replay
  /// together.
  bool replay();

  /// Whether the surface shows this binding. Defaults to true. An invisible
  /// binding stays attached and pinned but is not advanced, so a leaf
  /// scrolled out of view costs no ticks.
  bool get visible;
  set visible(bool value);

  /// Whether the surface holds this binding's playback: it shows the binding
  /// but wants it still. Defaults to false.
  ///
  /// A held binding is not advanced, as an invisible one is, but it stays
  /// shown: it paints at the time it was held, so a repaint shows the same
  /// frame, and its paintable keeps that frame where it lives
  /// ([AssetPaintable.keepFrame]) however long the hold lasts. Releasing the
  /// hold plays on from that frame. It is the hold of one surface, where a
  /// pause layer of the clock holds every surface of the scope.
  bool get held;
  set held(bool value);

  /// Advances the asset's playback for this frame without painting, for a
  /// surface that draws the paintable's sprite itself (see
  /// [AssetPaintable.advancePlayback]).
  ///
  /// Call it before reading `paintable.sprite` of an animated paintable, with
  /// the same playback time, animate flag and loop settings [paint] would use.
  /// A surface that calls [paint] needs no call.
  void advancePlayback();

  /// Paints the asset into [rect] at the scope's playback time: [paintable]
  /// clipped to the profile's corner radius, in [tint] and at [opacity].
  void paint(Canvas canvas, Rect rect, {Color? tint, double opacity = 1});

  /// Paints the stand-in this binding kept under content that replaced it
  /// (the thumbnail the entry showed before its first frame), into [rect], and
  /// says whether there was one.
  ///
  /// A bitmap thumbnail stays fully opaque under content that fades in, so the
  /// cell is never less drawn than before the content arrived; the surface
  /// calls [releaseStandIn] once the content is opaque. Only a binding that was
  /// attached while the thumbnail was showing has one: a binding attached
  /// after the content arrived never fades and has nothing to keep under it.
  bool paintStandIn(Canvas canvas, Rect rect);

  /// Lets go of the stand-in of [paintStandIn]; the entry disposes the
  /// thumbnail when every binding that waited for the content has. Idempotent,
  /// and a detach is a release.
  void releaseStandIn();

  /// Attempts the entry again now if nothing is running and it is not final.
  /// Does nothing otherwise.
  void retry();

  /// Gives the attach back. Idempotent: a second call changes nothing. After
  /// it the binding is silent and its [paintable] is the placeholder.
  void detach();
}
