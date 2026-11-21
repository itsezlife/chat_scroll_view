import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/debug/attach_log.dart';
import 'package:attach_sheet/src/panel/attach_interaction.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_ui/mpx_ui.dart';

/// The camera's captures of one open: the list the picker shows ahead of
/// the library (in the order taken), each capture selected last as it
/// lands, and their bytes released when the sheet goes without sending
/// them.
///
/// A capture is local media under its `MediaKey.local`, in the host's
/// capture cache; it goes to the attach selection as
/// `AttachSource.captured` of the key's stable form.
@internal
final class GalleryCaptures {
  /// The captures of an open over [selection]; [release] deletes a
  /// capture's bytes, [onRefused] hears a capture the selection refused,
  /// [keepPoster] keeps a recording's poster in the capture cache.
  GalleryCaptures({
    required this.selection,
    required this.release,
    this.onRefused,
    this.keepPoster,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Keeps [CaptureOutput.posterPath] of a recording in the capture cache
  /// under a key of its own, a still, and answers it; null for none. The
  /// recording then lands with it as its thumbnail
  /// (`PickerCapture.thumbnail`), so the grid draws its first frame.
  final Future<MediaKey$Local?> Function(CameraShot shot)? keepPoster;

  /// The open's attach selection.
  final AttachSelection selection;

  /// Deletes a capture's bytes from the capture cache.
  final void Function(MediaKey$Local key) release;

  /// Told each capture the selection refused, as an attach interaction.
  final ValueChanged<AttachInteraction>? onRefused;

  final DateTime Function() _now;

  /// The captures, in the order taken: what the picker shows and pages.
  final ValueNotifier<List<PickerCapture>> list = ValueNotifier(const []);

  /// The camera's shots behind [list] that the capture surface's strip and
  /// shots counter show, oldest first.
  ///
  /// A camera session's shots stay off it until the viewer's add-photo
  /// keeps them, so the first shot opens the viewer with no change to the
  /// camera's layout; from then on, and whenever the strip already shows
  /// kept shots, each shot joins it as it lands.
  final ValueNotifier<List<CameraShot>> shots = ValueNotifier(const []);

  // The session's shots not yet on the strip, oldest first.
  final List<CameraShot> _hidden = [];

  // Each recording's poster key, by the recording's.
  final Map<MediaKey$Local, MediaKey$Local> _posters = {};

  // Shots landing in the order taken: a recording waits for its poster,
  // and the shots after it wait for the recording.
  Future<void> _landing = Future.value();
  int _waiting = 0;

  // Set once the sheet went: a shot landing after it is released.
  bool _closed = false;

  /// Whether back from the camera's viewer takes the taking back: set by
  /// the first shot (whose viewer opens on it) and by the shots counter,
  /// cleared by the viewer's add-photo button. Back then discards every
  /// shot of the camera session.
  bool get cancelTakingPhotos => _cancelTakingPhotos;
  bool _cancelTakingPhotos = false;

  // The shots taken since the capture surface opened.
  final List<CameraShot> _session = [];

  /// The capture surface opened: a new camera session.
  void cameraOpened() {
    _session.clear();
    _cancelTakingPhotos = false;
    _hidden.clear();
  }

  /// The viewer opened from the camera over its shots (the counter).
  void viewerOpenedFromCamera() => _cancelTakingPhotos = true;

  /// The viewer's add-photo button: back to the camera for another shot,
  /// keeping this one.
  void addMore() {
    _cancelTakingPhotos = false;
    _show();
  }

  // The hidden shots join the strip.
  void _show() {
    if (_hidden.isEmpty) return;
    shots.value = [...shots.value, ..._hidden];
    _hidden.clear();
  }

  /// The capture surface closed: a viewer opened later is not the
  /// camera's.
  void cameraClosed() {
    _cancelTakingPhotos = false;
    _session.clear();
    // Kept shots: the next session's strip shows them.
    _show();
  }

  /// The camera's viewer closed: when the taking was still cancellable
  /// (back, not add-photo), every shot of the camera session goes.
  void viewerClosed() {
    final cancel = _cancelTakingPhotos;
    _cancelTakingPhotos = false;
    if (!cancel) return;
    [..._session].forEach(remove);
    _session.clear();
  }

  /// The attach item id of the capture under [key].
  static AttachItemId idOf(MediaKey$Local key) =>
      AttachItemId('captured:${key.encoded}');

  /// The attach item of [capture].
  static AttachItem itemOf(PickerCapture capture) {
    final video = capture.kind == LibraryAssetKind.video;
    return AttachItem(
      id: idOf(capture.key),
      source: AttachSource.captured(capture.key.encoded),
      kind: video ? AttachKind.video : AttachKind.photo,
      facts: AttachFacts(
        dimensions: switch (capture.dimensions) {
          final d? => AttachDimensions(d.width, d.height),
          null => null,
        },
        duration: capture.duration,
        byteSize: capture.byteSize,
        mimeType: video ? 'video/mp4' : 'image/jpeg',
        modified: capture.created,
      ),
    );
  }

  /// The capture under [key], or null.
  PickerCapture? captureOf(MediaKey$Local key) {
    for (final capture in list.value) {
      if (capture.key == key) return capture;
    }
    return null;
  }

  /// A shot landed: it joins the list and the selection, last. A shot with
  /// no key (the camera was given no cache) is not a capture here. A
  /// recording with a poster first has [keepPoster] keep it; the shots after
  /// it wait, so the list stays in the order taken.
  void add(CameraShot shot) {
    if (shot.key == null) return;
    final keep = keepPoster;
    final poster = shot.isVideo && shot.output.posterPath != null ? keep : null;
    if (poster == null && _waiting == 0) return _land(shot, null);
    _waiting++;
    // The poster is kept at once; the landing waits for it in turn.
    final keeping = poster?.call(shot);
    _landing = _landing.then((_) async {
      MediaKey$Local? kept;
      if (keeping != null) {
        try {
          kept = await keeping;
        } on Object catch (error) {
          // No poster: the cell shows the recording's own key.
          AttachLog.log(AttachLog.panel, 'poster not kept: $error');
        }
      }
      _waiting--;
      if (_closed) {
        release(shot.key!);
        if (kept != null) release(kept);
        return;
      }
      _land(shot, kept);
    });
  }

  void _land(CameraShot shot, MediaKey$Local? poster) {
    final key = shot.key!;
    final output = shot.output;
    if (poster != null) _posters[key] = poster;
    final capture = PickerCapture(
      key: key,
      kind: shot.isVideo ? LibraryAssetKind.video : LibraryAssetKind.photo,
      dimensions: output.dimensions,
      duration: shot.isVideo ? output.duration : null,
      byteSize: output.size,
      created: _now(),
      thumbnail: poster,
    );
    list.value = [...list.value, capture];
    _session.add(shot);
    // On the strip once it shows; until then the session keeps it.
    if (shots.value.isNotEmpty) {
      shots.value = [...shots.value, shot];
    } else {
      _hidden.add(shot);
    }
    // The open's first capture opens the viewer on it.
    if (list.value.length == 1) _cancelTakingPhotos = true;
    if (selection.toggle(itemOf(capture)) case AttachToggle$Refused(
      :final reason,
    )) {
      onRefused?.call(AttachInteraction.refused(reason));
    }
  }

  /// The shot [shot] was removed from the camera's results strip: it leaves
  /// the list and the selection, and its bytes go.
  void remove(CameraShot shot) {
    final key = shot.key;
    if (key == null) return;
    final before = list.value;
    final after = [
      for (final c in before)
        if (c.key != key) c,
    ];
    if (after.length == before.length) return;
    list.value = after;
    shots.value = [
      for (final s in shots.value)
        if (s.key != key) s,
    ];
    _hidden.removeWhere((s) => s.key == key);
    _session.removeWhere((s) => s.key == key);
    selection.remove(idOf(key));
    release(key);
    if (_posters.remove(key) case final poster?) release(poster);
  }

  /// The sheet is going: releases every capture but those [sent] carries,
  /// and clears the list.
  void discard({Set<AttachItemId> sent = const {}}) {
    _closed = true;
    for (final capture in list.value) {
      if (!sent.contains(idOf(capture.key))) release(capture.key);
    }
    // The posters only drew the grid: they go whatever was sent.
    _posters.values.forEach(release);
    _posters.clear();
    list.value = const [];
    shots.value = const [];
    _hidden.clear();
    _session.clear();
    _cancelTakingPhotos = false;
  }

  /// Releases the lists.
  void dispose() {
    list.dispose();
    shots.dispose();
  }
}
