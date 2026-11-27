import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/limits/derive_attach_limits.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:listen/listen.dart' as listen;

/// What the picker of one chat reads its rights from: the chat's
/// capabilities, the host's denial feedback and the chat's id for the
/// diagnostics events.
///
/// The host passes one per open beside its own attach limits. The picker
/// then applies the chat's rights on top of those limits, live: a kind the
/// chat denies stops joining, a slow mode puts the picker in one-send mode,
/// and the chat's caption, file and album limits apply when they are
/// narrower than the host's. Pass the host's own limits rather than
/// `deriveAttachLimits(capabilities.value)`: limits narrowed at open stay
/// narrow when the chat lifts a right.
///
/// `const ChatCapabilities()` changes nothing, so a picker given it behaves
/// as one given none.
@immutable
final class AttachCapabilities {
  /// The rights of the chat [chatId], read from [capabilities]; attempts and
  /// texts go through [feedback].
  const AttachCapabilities({
    required this.capabilities,
    required this.chatId,
    this.feedback = CapabilityFeedback.none,
  });

  /// The chat's capabilities, live.
  final listen.ValueListenable<ChatCapabilities> capabilities;

  /// The host's denial texts and its report of attempted denied actions.
  final CapabilityFeedback feedback;

  /// The chat's id, on every diagnostics event.
  final String chatId;
}

/// The chat's rights over one open of the picker: what the pages read to
/// draw a denied kind, and what reports an attempt at one.
///
/// Owned by the open's `AttachSendController` (`capabilities`), created
/// from an [AttachCapabilities] and the selection the host opened with,
/// whose limits it narrows as the chat's value changes:
///
/// - the allowed kinds are the host's less the chat's denied ones;
/// - caption length, file size and album size are the smaller of the two;
/// - one-send mode is on when either asks for it (a slow mode).
///
/// Items already selected stay when a kind is denied or the cap shrinks
/// (the picker keeps the user's work); the send is refused while they are
/// there, through `onDenied`, and the pages mark them.
///
/// A tap on a denied kind reports `onDenied` once per [deniedGuard] per
/// action, so a burst of taps is one report.
final class AttachCapabilityGate {
  /// The gate of [capabilities] over [selection]; the selection's limits
  /// now are the host's, kept as the base the chat's rights narrow.
  AttachCapabilityGate(this.capabilities, {required this.selection})
    : base = selection.limits,
      _id = ChatCorrelation(chatId: capabilities.chatId),
      _$chatSending = capabilities.capabilities.select((c) => c.sending),
      _$limits = attachLimitsOf(
        capabilities.capabilities,
        chatId: capabilities.chatId,
      ) {
    _$sending = ValueNotifier(_$chatSending.value);
    _$chatSending.addListener(_relaySending);
    _$limits.addListener(_apply);
    _apply();
  }

  /// How long after a reported tap on a denied kind another tap of the same
  /// action goes unreported.
  static const deniedGuard = Duration(seconds: 1);

  /// The chat's rights and the host's feedback.
  final AttachCapabilities capabilities;

  /// The open's selection, whose limits this gate keeps.
  final AttachSelection selection;

  /// The host's limits, before the chat's rights.
  final AttachLimits base;

  /// The chat's sending rights, notifying only when they change: what a
  /// page rebuilds on to swap its content for a denied form (a slow mode
  /// tick does not reach it).
  ValueListenable<SendingCapabilities> get sending => _$sending;
  late final ValueNotifier<SendingCapabilities> _$sending;
  final listen.ValueListenable<SendingCapabilities> _$chatSending;

  final ChatCorrelation _id;
  final listen.ValueListenable<AttachLimits> _$limits;
  final Map<CapabilityAction, Timer> _$guards = {};
  bool? _$oneSend;
  bool _$disposed = false;

  CapabilityFeedback get _feedback => capabilities.feedback;

  /// Why the chat denies [kind], or null when it allows it.
  DenialReason? reasonFor(AttachKind kind) =>
      sending.value.media.reasonFor(mediaKindOf(kind));

  /// Whether the chat denies [kind].
  bool denies(AttachKind kind) => reasonFor(kind) != null;

  /// Whether [item] is selected and of a kind the current limits refuse:
  /// what a page marks, and what keeps the send refused.
  bool isDeniedPick(AttachItem item) =>
      selection.contains(item.id) && !selection.limits.allows(item.kind);

  /// The host's text for [kind] denied, drawn in place as [form] (the
  /// page's name for it, reported when the text is missing); null when the
  /// chat allows [kind] or the host gives none.
  String? denialText(AttachKind kind, {required String form}) {
    final reason = reasonFor(kind);
    if (reason == null) return null;
    return _feedback.denialText(
      CapabilityAction.forMediaKind(mediaKindOf(kind)),
      reason,
      correlation: _id,
      form: form,
    );
  }

  /// Reports a refusal of [item] for [reason] when the chat's rights are
  /// why (a kind it denies): `onDenied`, once per [deniedGuard] when
  /// [guarded]. Returns whether it was reported here; the caller raises
  /// any other refusal to the host as an attach interaction.
  bool reportRefusal(
    AttachItem item,
    AttachRefusal reason, {
    bool guarded = true,
  }) {
    if (reason != AttachRefusal.kindNotAllowed) return false;
    final denial = reasonFor(item.kind);
    if (denial == null) return false;
    _denied(item.kind, denial, guarded: guarded);
    return true;
  }

  /// Refuses a send of [items] that holds a kind the chat denies (picked
  /// before it was denied): `onDenied` for the first such item's kind.
  /// Returns whether the send was refused.
  bool refusesSend(Iterable<AttachItem> items) {
    for (final item in items) {
      if (reasonFor(item.kind) case final reason?) {
        _denied(item.kind, reason, guarded: true);
        return true;
      }
    }
    return false;
  }

  void _denied(AttachKind kind, DenialReason reason, {required bool guarded}) {
    final action = CapabilityAction.forMediaKind(mediaKindOf(kind));
    if (guarded) {
      if (_$guards.containsKey(action)) return;
      _$guards[action] = Timer(deniedGuard, () => _$guards.remove(action));
    }
    _feedback.onDenied(action, reason, correlation: _id);
  }

  void _relaySending() => _$sending.value = _$chatSending.value;

  // The host's limits narrowed by the chat's, written to the selection.
  void _apply() {
    if (_$disposed) return;
    final chat = _$limits.value;
    final next = base.copyWith(
      allowedKinds: base.allowedKinds.intersection(chat.allowedKinds),
      captionLength: _min(base.captionLength, chat.captionLength),
      fileSizeLimit: switch ((base.fileSizeLimit, chat.fileSizeLimit)) {
        (final a?, final b?) => _min(a, b),
        (final a?, null) => a,
        (null, final b) => b,
      },
      albumSize: _min(base.albumSize, chat.albumSize),
      oneSend: base.oneSend || chat.oneSend,
    );
    selection.limits = next;
    final was = _$oneSend;
    _$oneSend = next.oneSend;
    // The first value is reported only when it is on: a picker that never
    // enters one-send mode stays quiet.
    if (was == null ? next.oneSend : was != next.oneSend) _reportOneSend(next);
  }

  void _reportOneSend(AttachLimits limits) => ChatDiagnostics.current.emit(
    ChatEventLevel.debug,
    ChatEventCategory.capabilities,
    CapabilitiesOp.pickerOneSend,
    correlation: _id,
    fields: () => {'on': limits.oneSend, 'albumCap': limits.albumSize},
  );

  static int _min(int a, int b) => a < b ? a : b;

  /// Stops following the chat's value; the selection keeps its limits.
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    _$limits.removeListener(_apply);
    _$chatSending.removeListener(_relaySending);
    _$sending.dispose();
    for (final guard in _$guards.values) {
      guard.cancel();
    }
    _$guards.clear();
  }
}

/// The media kind of an attach kind: the chat's right that gates it.
MediaKind mediaKindOf(AttachKind kind) => switch (kind) {
  AttachKind.photo => MediaKind.photo,
  AttachKind.video => MediaKind.video,
  AttachKind.animation => MediaKind.animation,
  AttachKind.file => MediaKind.file,
  AttachKind.audio => MediaKind.audio,
};
