import 'package:attach_model/attach_model.dart';
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
  /// capture's bytes, [onRefused] hears a capture the selection refused.
  GalleryCaptures({
    required this.selection,
    required this.release,
    this.onRefused,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The open's attach selection.
  final AttachSelection selection;

  /// Deletes a capture's bytes from the capture cache.
  final void Function(MediaKey$Local key) release;

  /// Told each capture the selection refused, as an attach interaction.
  final ValueChanged<AttachInteraction>? onRefused;

  final DateTime Function() _now;

  /// The captures, in the order taken: what the picker shows and pages.
  final ValueNotifier<List<PickerCapture>> list = ValueNotifier(const []);

  /// The camera's shots behind [list], oldest first: what the capture
  /// surface's strip and shots counter show.
  final ValueNotifier<List<CameraShot>> shots = ValueNotifier(const []);

  /// Whether back from the camera's viewer takes the taking back: set by
  /// the first shot (whose viewer opens on it) and by the shots counter,
  /// cleared by the viewer's add-photo button. Back then discards the shot
  /// when it is the only one; two or more stay.
  bool get cancelTakingPhotos => _cancelTakingPhotos;
  bool _cancelTakingPhotos = false;

  /// The viewer opened from the camera over its shots (the counter).
  void viewerOpenedFromCamera() => _cancelTakingPhotos = true;

  /// The viewer's add-photo button: back to the camera for another shot,
  /// keeping this one.
  void addMore() => _cancelTakingPhotos = false;

  /// The capture surface closed: a viewer opened later is not the
  /// camera's.
  void cameraClosed() => _cancelTakingPhotos = false;

  /// The camera's viewer closed: the one shot goes when the taking was
  /// still cancellable (back, not add-photo).
  void viewerClosed() {
    final cancel = _cancelTakingPhotos;
    _cancelTakingPhotos = false;
    if (!cancel || shots.value.length != 1) return;
    remove(shots.value.single);
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
  /// no key (the camera was given no cache) is not a capture here.
  void add(CameraShot shot) {
    final key = shot.key;
    if (key == null) return;
    final output = shot.output;
    final capture = PickerCapture(
      key: key,
      kind: shot.isVideo ? LibraryAssetKind.video : LibraryAssetKind.photo,
      dimensions: output.dimensions,
      duration: shot.isVideo ? output.duration : null,
      byteSize: output.size,
      created: _now(),
    );
    list.value = [...list.value, capture];
    shots.value = [...shots.value, shot];
    // The first shot opens the viewer on it.
    if (shots.value.length == 1) _cancelTakingPhotos = true;
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
    selection.remove(idOf(key));
    release(key);
  }

  /// The sheet is going: releases every capture but those [sent] carries,
  /// and clears the list.
  void discard({Set<AttachItemId> sent = const {}}) {
    for (final capture in list.value) {
      if (!sent.contains(idOf(capture.key))) release(capture.key);
    }
    list.value = const [];
    shots.value = const [];
    _cancelTakingPhotos = false;
  }

  /// Releases the lists.
  void dispose() {
    list.dispose();
    shots.dispose();
  }
}
