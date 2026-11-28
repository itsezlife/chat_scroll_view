import 'package:attach_model/attach_model.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:content_model/content_model.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// A photo the host picked, by id [id]; [byteSize] when the intake knew it.
AttachItem photo(String id, {int? byteSize}) => AttachItem(
  id: AttachItemId(id),
  source: AttachSource.library('asset-$id'),
  kind: AttachKind.photo,
  facts: AttachFacts(byteSize: byteSize),
);

/// A video the host picked, by id [id].
AttachItem video(String id) => AttachItem(
  id: AttachItemId(id),
  source: AttachSource.file('/videos/$id.mp4'),
  kind: AttachKind.video,
);

/// The media key of attach item [id]: one per id, the same on every call.
MediaKey mediaKeyOf(String id) => _mediaKeys.putIfAbsent(
  id,
  () => MediaKey.local(
    '00000000-0000-4000-8000-'
    '${_mediaKeys.length.toRadixString(16).padLeft(12, '0')}',
  ),
);

final Map<String, MediaKey> _mediaKeys = {};

/// The local content key of attach item [id].
ContentKey localKeyOf(String id) => ContentKey.document('local-$id');

/// The preparation input of attach item [id].
PreparationInput inputOf(String id) => PreparationInput('/inputs/$id');

/// The tests' host resolver: a library photo is prepared as a photo, a
/// file video as a video, and an item whose id starts with `remote-` is
/// content the server already has.
OutgoingSendItem sendItemOf(AttachItem item, SendForm form) => OutgoingSendItem(
  localKey: localKeyOf(item.id),
  mediaKey: mediaKeyOf(item.id),
  source: switch (item) {
    _ when item.id.startsWith('remote-') => const PublishSource.remote(),
    AttachItem(kind: AttachKind.video) => PublishSource.prepare(
      inputOf(item.id),
      const PreparationIntent.video(),
    ),
    _ => PublishSource.prepare(
      inputOf(item.id),
      const PreparationIntent.photo(),
    ),
  },
);

/// Client message ids `cm1`, `cm2`, … in order.
String Function() clientMessageIdsFrom([int first = 1]) {
  var next = first;
  return () => 'cm${next++}';
}
