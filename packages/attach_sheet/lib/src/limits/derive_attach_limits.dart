import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';

/// The picker's attach limits for one chat's [capabilities].
///
/// - `allowedKinds` is the media kinds of `sending.media` that have an
///   attach kind: `photo`, `video`, `animation`, `file` and `audio`. Voice
///   and round video are recorded, never picked, so they have none.
/// - Under a slow mode the picker is in one-send mode (`oneSend`): one send
///   unit, and an album is one unit. Grouping stays on and single select
///   stays off, so one album or one item goes; a host that wants fewer sets
///   its own limits. Without a slow mode all three keep their defaults.
/// - `captionLength`, `fileSizeLimit` and `albumSize` are the `limits` of
///   the chat.
///
/// The other fields (timer, schedule, spoiler, send as file) are not
/// capabilities and keep the defaults of `AttachLimits`.
/// `const ChatCapabilities()` gives exactly `const AttachLimits()`.
AttachLimits deriveAttachLimits(ChatCapabilities capabilities) {
  final limits = capabilities.limits;
  return AttachLimits(
    allowedKinds: _attachKinds(capabilities.sending.media.allowed),
    captionLength: limits.captionLength,
    fileSizeLimit: limits.fileSize,
    albumSize: limits.albumSize,
    // One send unit while a slow mode is set: an album is one unit, so
    // grouping is on and the selection is not cut to one item.
    groupingAllowed: true,
    singleSelect: false,
    oneSend: capabilities.slowMode.isActive,
  );
}

/// The attach kind of a media kind, or null for a kind that is recorded
/// rather than picked.
AttachKind? attachKindOf(MediaKind kind) => switch (kind) {
  MediaKind.photo => AttachKind.photo,
  MediaKind.video => AttachKind.video,
  MediaKind.animation => AttachKind.animation,
  MediaKind.file => AttachKind.file,
  MediaKind.audio => AttachKind.audio,
  MediaKind.voice || MediaKind.roundVideo => null,
};

Set<AttachKind> _attachKinds(MediaKindSet allowed) => {
  for (final kind in allowed.kinds) ?attachKindOf(kind),
};

/// The attach limits of a chat, live: a listenable of
/// [deriveAttachLimits] that notifies only when the limits change by `==`.
///
/// A slow mode tick changes only `slowMode.nextSendAt`, which the limits do
/// not read, so it notifies nobody. Like `select`, it subscribes to
/// [capabilities] only while it has listeners, so it needs no disposal.
/// Each distinct value reports `limitsDerived` under [chatId].
///
/// The picker's selection holds the limits of one open; a host reads
/// `value` when it opens the picker, and listens for what changes while it
/// is open.
ValueListenable<AttachLimits> attachLimitsOf(
  ValueListenable<ChatCapabilities> capabilities, {
  required String chatId,
}) => _AttachLimitsListenable(capabilities, ChatCorrelation(chatId: chatId));

final class _AttachLimitsListenable extends ChangeNotifier
    implements ValueListenable<AttachLimits> {
  _AttachLimitsListenable(ValueListenable<ChatCapabilities> source, this._id)
    : _source = source.select(deriveAttachLimits);

  final ValueListenable<AttachLimits> _source;
  final ChatCorrelation _id;
  var _attached = false;

  // The last value reported, kept across detaches so a value that arrived
  // while nobody listened is reported once, on the next attach.
  AttachLimits? _reported;

  @override
  AttachLimits get value => _source.value;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_attached) return;
    _attached = true;
    _source.addListener(_onSource);
    _report(_source.value);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _detachIfUnheard();
  }

  @override
  void dispose() {
    if (_attached) _detach();
    super.dispose();
  }

  void _onSource() {
    _report(_source.value);
    notifyListeners();
    _detachIfUnheard();
  }

  void _report(AttachLimits limits) {
    if (limits == _reported) return;
    _reported = limits;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.capabilities,
      CapabilitiesOp.limitsDerived,
      correlation: _id,
      fields: () => {
        'kinds': ([
          for (final kind in limits.allowedKinds) kind.name,
        ]..sort()).join(','),
        'grouping': limits.groupingAllowed,
        'singleSelect': limits.singleSelect,
        'captionLength': limits.captionLength,
        'fileSizeLimit': limits.fileSizeLimit ?? 'none',
        'albumSize': limits.albumSize,
        'oneSend': limits.oneSend,
      },
    );
  }

  void _detachIfUnheard() {
    if (_attached && !hasListeners) _detach();
  }

  void _detach() {
    _source.removeListener(_onSource);
    _attached = false;
  }
}
