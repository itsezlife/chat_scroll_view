import 'dart:developer' show Timeline;

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/limits/attach_op.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';

/// The picker's attach limits of a chat's capabilities.
extension ChatCapabilitiesAttachLimits on ChatCapabilities {
  /// The picker's attach limits for these capabilities.
  ///
  /// - `allowedKinds` is the media kinds of `sending.media` that have an
  ///   attach kind: `photo`, `video`, `animation`, `file` and `audio`. Voice
  ///   and round video are recorded, never picked, so they have none.
  /// - Under a slow mode the picker is in one-send mode (`oneSend`): one
  ///   send unit, and an album is one unit. Grouping stays on and single
  ///   select stays off, so one album or one item goes; a host that wants
  ///   fewer sets its own limits. Without a slow mode all three keep their
  ///   defaults.
  /// - `captionLength`, `fileSizeLimit` and `albumSize` are the `limits` of
  ///   the chat.
  ///
  /// The other fields (timer, schedule, spoiler, send as file) are not
  /// capabilities and keep the defaults of `AttachLimits`.
  /// `const ChatCapabilities().attachLimits` is exactly
  /// `const AttachLimits()`.
  AttachLimits get attachLimits => _AttachTrace.deriveLimits.run(() {
    final limits = this.limits;
    return AttachLimits(
      allowedKinds: {
        for (final kind in sending.media.allowed.kinds) ?kind.attachKind,
      },
      captionLength: limits.captionLength,
      fileSizeLimit: limits.fileSize,
      albumSize: limits.albumSize,
      // One send unit while a slow mode is set: an album is one unit, so
      // grouping is on and the selection is not cut to one item.
      groupingAllowed: true,
      singleSelect: false,
      oneSend: slowMode.isActive,
    );
  });
}

/// The attach limits of a chat, live.
extension ChatCapabilitiesAttachLimitsListenable
    on ValueListenable<ChatCapabilities> {
  /// A listenable of `attachLimits` that notifies only when the limits
  /// change by `==`.
  ///
  /// A slow mode tick changes only `slowMode.nextSendAt`, which the limits
  /// do not read, so it notifies nobody. Like `select`, which it is, it
  /// subscribes only while it has listeners, so it needs no disposal. Each
  /// distinct value reports `limitsDerived` under [chatId].
  ///
  /// The picker's selection holds the limits of one open; a host reads
  /// `value` when it opens the picker, and listens for what changes while
  /// it is open.
  ValueListenable<AttachLimits> attachLimits({required String chatId}) {
    final correlation = ChatCorrelation(chatId: chatId);
    return select(
      (capabilities) => capabilities.attachLimits,
      onValue: (_, limits) => _reportDerived(limits, correlation),
    );
  }

  static void _reportDerived(
    AttachLimits limits,
    ChatCorrelation correlation,
  ) => ChatDiagnostics.current.emit(
    ChatEventLevel.debug,
    ChatEventCategory.capabilities,
    AttachOp.limitsDerived,
    correlation: correlation,
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

/// The chat's right that gates an attach kind.
extension AttachKindMediaKind on AttachKind {
  /// The media kind of this attach kind.
  MediaKind get mediaKind => switch (this) {
    AttachKind.photo => MediaKind.photo,
    AttachKind.video => MediaKind.video,
    AttachKind.animation => MediaKind.animation,
    AttachKind.file => MediaKind.file,
    AttachKind.audio => MediaKind.audio,
  };
}

/// The attach kind a media kind is picked as.
extension MediaKindAttachKind on MediaKind {
  /// The attach kind of this media kind, or null for a kind that is
  /// recorded rather than picked.
  AttachKind? get attachKind => switch (this) {
    MediaKind.photo => AttachKind.photo,
    MediaKind.video => AttachKind.video,
    MediaKind.animation => AttachKind.animation,
    MediaKind.file => AttachKind.file,
    MediaKind.audio => AttachKind.audio,
    MediaKind.voice || MediaKind.roundVideo => null,
  };
}

/// This package's named timeline sections, in the engine's namespace
/// (`chat_scroll_view.<name>`), compiled in only with
/// `--dart-define=chat_scroll_view.trace=phase` (or `fine`).
enum _AttachTrace {
  /// The picker's limits derived from a chat's capabilities.
  deriveLimits('capabilities.deriveLimits');

  const _AttachTrace(String name) : label = 'chat_scroll_view.$name';

  final String label;

  static const String _define = String.fromEnvironment(
    'chat_scroll_view.trace',
  );

  // A constant, so an off build folds every call site away.
  static const bool _enabled = _define == 'phase' || _define == 'fine';

  T run<T>(T Function() body) {
    if (!_enabled) return body();
    Timeline.startSync(label);
    try {
      return body();
    } finally {
      Timeline.finishSync();
    }
  }
}
