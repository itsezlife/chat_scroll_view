/// The camera's captures in one open: listed for the picker, selected
/// last, released when the sheet goes without sending them.
///
/// **Seams:** `GalleryCaptures` over an attach selection, a spy for the
/// cache's release; `AttachPickerSelection` reading capture keys.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:attach_sheet/src/gallery/gallery_captures.dart';
import 'package:content_model/content_model.dart' show RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';
import 'package:mpx_ui/mpx_ui.dart';

MediaKey$Local _key(int n) =>
    MediaKey$Local('00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}');

CameraShot _shot(int n, {bool video = false}) => CameraShot(
  isVideo: video,
  key: _key(n),
  output: CaptureOutput(
    path: '/gone/$n',
    size: 1000 + n,
    duration: video ? const Duration(seconds: 3) : Duration.zero,
    dimensions: const MediaDimensions(1080, 1920),
    headerRewritten: false,
  ),
);

void main() {
  late AttachSelection selection;
  late List<AttachInteraction> interactions;
  late List<MediaKey$Local> released;
  late GalleryCaptures captures;

  setUp(() {
    selection = AttachSelection(
      policy: const AttachPolicy.android(),
      limits: const AttachLimits(),
    );
    interactions = [];
    released = [];
    captures = GalleryCaptures(
      selection: selection,
      release: released.add,
      onRefused: interactions.add,
      now: () => DateTime(2026, 11, 21),
    );
  });

  tearDown(() => captures.dispose());

  test('a shot joins the list, in the order taken, with its facts', () {
    captures
      ..add(_shot(1))
      ..add(_shot(2, video: true));
    expect(captures.list.value.map((c) => c.key), [_key(1), _key(2)]);
    final video = captures.list.value.last;
    expect(video.kind, LibraryAssetKind.video);
    expect(video.duration, const Duration(seconds: 3));
    expect(video.dimensions, const MediaDimensions(1080, 1920));
    expect(video.byteSize, 1002);
    expect(video.created, DateTime(2026, 11, 21));
    expect(captures.list.value.first.duration, isNull);
  });

  test('a shot is selected last, as local media by its key', () {
    selection.toggle(AttachItems.photo('picked'));
    captures.add(_shot(1, video: true));
    final item = selection.items.last;
    expect(selection.orderOf(item.id), 2);
    expect(item.source, AttachSource.captured(_key(1).encoded));
    expect(item.kind, AttachKind.video);
    expect(item.facts.byteSize, 1001);
  });

  test('a capture the selection refuses stays in the grid, unselected, and '
      'the refusal goes to the host', () {
    selection = AttachSelection(
      policy: const AttachPolicy.android(),
      limits: const AttachLimits(allowedKinds: {AttachKind.photo}),
    );
    captures = GalleryCaptures(
      selection: selection,
      release: released.add,
      onRefused: interactions.add,
    );
    captures.add(_shot(1, video: true));
    expect(selection.isEmpty, isTrue);
    expect(captures.list.value, hasLength(1));
    expect(interactions, [
      const AttachInteraction.refused(AttachRefusal.kindNotAllowed),
    ]);
  });

  test('a shot removed from the camera strip leaves the list and the '
      'selection, and its bytes go', () {
    final shot = _shot(1);
    captures
      ..add(shot)
      ..add(_shot(2));
    captures.remove(shot);
    expect(captures.list.value.map((c) => c.key), [_key(2)]);
    expect(selection.contains(GalleryCaptures.idOf(_key(1))), isFalse);
    expect(selection.contains(GalleryCaptures.idOf(_key(2))), isTrue);
    expect(released, [_key(1)]);
  });

  test('the sheet going without a send releases every capture and clears '
      'the list', () {
    captures
      ..add(_shot(1))
      ..add(_shot(2));
    captures.discard();
    expect(released, [_key(1), _key(2)]);
    expect(captures.list.value, isEmpty);
  });

  test('a send keeps what it carries and releases the rest', () {
    captures
      ..add(_shot(1))
      ..add(_shot(2));
    captures.discard(sent: {GalleryCaptures.idOf(_key(2))});
    expect(released, [_key(1)]);
  });

  test("the grid's selection reads a capture's key: checked, numbered, "
      'toggled', () {
    final library = FakeMediaLibrary(assets: 3);
    addTearDown(library.dispose);
    final picker = AttachPickerSelection(
      selection: selection,
      source: library,
      captures: captures,
    );
    selection.toggle(AttachItems.photo('picked'));
    captures.add(_shot(1));
    expect(picker.keys, contains(_key(1)));
    expect(picker.orderOf(_key(1)), 2);
    expect(picker.toggle(_key(1)), isA<PickerToggle$Deselected>());
    expect(picker.orderOf(_key(1)), isNull);
    expect(
      picker.toggle(_key(1)),
      isA<PickerToggle$Selected>().having((t) => t.order, 'order', 2),
    );
  });

  test('a capture is prepared from its file in the capture cache, the '
      'lease released after', () async {
    final released = <String>[];
    final inputs = <String>[];
    final preparation = AttachPreparation(
      prepare: (input, intent) async {
        inputs.add(input.path);
        return const PreparedMedia(
          kind: PreparedKind.photo,
          path: '/out.jpg',
          isOriginal: false,
          byteSize: 1,
        );
      },
      capturedFile: (key) async => (
        path: '/store/${key.uuid}',
        release: () async => released.add(key.uuid),
      ),
    );
    captures.add(_shot(1));
    final done = await preparation.prepareAll(
      SendRequest(items: selection.items, caption: RichText.empty),
    );
    expect(inputs, ['/store/${_key(1).uuid}']);
    expect(released, [_key(1).uuid]);
    expect(done.keys, [GalleryCaptures.idOf(_key(1))]);
  });

  test('a capture with no file to lease is left out', () async {
    final preparation = AttachPreparation(
      prepare: (input, intent) async => fail('nothing to prepare'),
      capturedFile: (key) async => null,
    );
    captures.add(_shot(1));
    final done = await preparation.prepareAll(
      SendRequest(items: selection.items, caption: RichText.empty),
    );
    expect(done, isEmpty);
  });

  group('the capture flow (the camera, its viewer, back)', () {
    test('a shot joins the shots too, oldest first; a removal leaves them', () {
      captures
        ..add(_shot(1))
        ..add(_shot(2, video: true));
      expect(captures.shots.value.map((s) => s.key), [_key(1), _key(2)]);
      captures.remove(_shot(1));
      expect(captures.shots.value.map((s) => s.key), [_key(2)]);
      captures.discard();
      expect(captures.shots.value, isEmpty);
    });

    test('the first shot marks the taking cancellable; back from its viewer '
        'discards it from the captures, the shots, the selection and the '
        'cache', () {
      captures.add(_shot(1));
      expect(captures.cancelTakingPhotos, isTrue);
      captures.viewerClosed();
      expect(captures.list.value, isEmpty);
      expect(captures.shots.value, isEmpty);
      expect(selection.items, isEmpty);
      expect(released, [_key(1)]);
      expect(captures.cancelTakingPhotos, isFalse);
    });

    test('with two or more shots back keeps them', () {
      captures
        ..add(_shot(1))
        ..add(_shot(2));
      captures.viewerClosed();
      expect(captures.shots.value, hasLength(2));
      expect(selection.items, hasLength(2));
      expect(released, isEmpty);

      // The counter opens the viewer again: back still keeps two.
      captures
        ..viewerOpenedFromCamera()
        ..viewerClosed();
      expect(captures.shots.value, hasLength(2));
    });

    test('add-photo clears the mark: back after it keeps the one shot', () {
      captures
        ..add(_shot(1))
        ..addMore()
        ..viewerClosed();
      expect(captures.shots.value, hasLength(1));
      expect(selection.items, hasLength(1));
      expect(released, isEmpty);
    });

    test('the counter over one shot marks it cancellable again', () {
      captures
        ..add(_shot(1))
        ..addMore()
        ..viewerOpenedFromCamera()
        ..viewerClosed();
      expect(captures.shots.value, isEmpty);
      expect(released, [_key(1)]);
    });

    test('a shot the user unchecked is still the one back discards', () {
      captures.add(_shot(1));
      selection.remove(GalleryCaptures.idOf(_key(1)));
      captures.viewerClosed();
      expect(captures.shots.value, isEmpty);
      expect(released, [_key(1)]);
    });
  });
}
