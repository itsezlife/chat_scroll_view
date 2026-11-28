import 'dart:async';

import 'package:attach_sheet/attach_sheet.dart' show AttachCapabilities;
import 'package:bulletins/bulletins.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/chat_composer.dart' show ComposerPanelAction;
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_denial_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/demo_chat_rights.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_bulletins.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:listen/listen.dart' as listen;

/// The host side of one chat's **chat capabilities**: the one signal the
/// chat's consumers read, the denial feedback they report through, and the
/// demo's resolution of both.
///
/// - [capabilities] is the chat's value, wrapped once with its diagnostics
///   (`valueChanged`, `invalidValue` under [chatId]); the screen passes this
///   same listenable to the composer, the picker and the Logs screen, so
///   each value is reported once whoever reads it.
/// - [feedback] words every denial from [strings] and shows an attempt as a
///   bulletin on [bulletins]: one per attempt the packages report (their
///   input guards decide what an attempt is), a hint on the touch families
///   and a toast on desktop and the web. A restriction the user can lift
///   carries the lift as the bulletin's action.
/// - [send] marks a send in slow mode: the next send waits an interval from
///   now, and the send is pending until it lands. A chat whose sends go
///   through the outbox marks the interval with [startInterval] instead and
///   follows the outbox's send in flight as `pending`
///   ([followSendInFlight]).
/// - [set] and [update] replace the value live (the debug switcher).
///
/// Created and disposed with the chat screen.
final class ChatCapabilitiesHost {
  /// The host of [chatId], starting at [initial]; attempts show on
  /// [bulletins]. [now] is the clock slow mode and dated bans are read at.
  ChatCapabilitiesHost({
    required this.chatId,
    required ChatCapabilities initial,
    required this.bulletins,
    this.strings = ChatDenialStrings.demo,
    bool? hintBulletins,
    DateTime Function() now = DateTime.now,
  }) : _now = now,
       _hint = hintBulletins ?? _touchFamily(),
       _value = listen.ValueNotifier(initial) {
    capabilities = _value.withDiagnostics(chatId: chatId);
    String text(CapabilityAction action, DenialReason reason) =>
        strings.text(action, reason, now: _now());
    feedback = CapabilityFeedback(denialText: text, onDenied: _showDenied);
    panelFeedback = CapabilityFeedback(denialText: text);
  }

  /// The host of a demo chat with [rights], resolved now.
  factory ChatCapabilitiesHost.forRights(
    DemoChatRights rights, {
    required String chatId,
    required BulletinController bulletins,
    ChatDenialStrings strings = ChatDenialStrings.demo,
    bool? hintBulletins,
    DateTime Function() now = DateTime.now,
  }) => ChatCapabilitiesHost(
    chatId: chatId,
    initial: rights.resolve(now()),
    bulletins: bulletins,
    strings: strings,
    hintBulletins: hintBulletins,
    now: now,
  );

  /// The chat's id: every capabilities event of the chat carries it.
  final String chatId;

  /// Where an attempted denied action is shown.
  final BulletinController bulletins;

  /// The words of every denial.
  final ChatDenialStrings strings;

  final DateTime Function() _now;
  final bool _hint;
  final listen.ValueNotifier<ChatCapabilities> _value;
  var _disposed = false;

  /// The chat's capabilities, reporting their diagnostics: what every
  /// consumer of this chat is given.
  late final listen.ValueListenable<ChatCapabilities> capabilities;

  /// The denial texts and the report of attempts, passed beside
  /// [capabilities].
  late final CapabilityFeedback feedback;

  /// The panel's feedback: [feedback]'s texts, and attempts reported
  /// (the `denied` event) but not shown again: the panel shows a try on a
  /// dimmed page as the hint at its tab.
  late final CapabilityFeedback panelFeedback;

  /// The picker's view of the chat: [capabilities], [feedback] and the id.
  AttachCapabilities get attach => AttachCapabilities(
    capabilities: capabilities,
    chatId: chatId,
    feedback: feedback,
  );

  /// The value now.
  ChatCapabilities get value => _value.value;

  /// Replaces the value; consumers react on it.
  void set(ChatCapabilities value) {
    if (_disposed) return;
    _value.value = value;
  }

  /// Replaces the value with [change] of it.
  void update(ChatCapabilities Function(ChatCapabilities value) change) =>
      set(change(value));

  // --- Slow mode -------------------------------------------------------------

  /// Runs [post], one send of the chat. In slow mode the next send may go an
  /// interval from now, and the slow mode is `pending` until [post]
  /// completes; outside slow mode [post] just runs.
  Future<void> send(Future<void> Function() post) async {
    if (_disposed) return post();
    final slow = switch (value.slowMode) {
      final SlowMode$Active slow => slow,
      SlowMode$None() => null,
    };
    if (slow == null) return post();
    update(
      (c) => c.copyWith(
        slowMode: slow.copyWith(
          nextSendAt: _now().add(slow.interval),
          pending: true,
        ),
      ),
    );
    try {
      await post();
    } finally {
      update(
        (c) => c.copyWith(
          slowMode: switch (c.slowMode) {
            final SlowMode$Active slow => slow.copyWith(pending: false),
            final none => none,
          },
        ),
      );
    }
  }

  /// Starts slow mode's wait from now, for a send the outbox accepted;
  /// outside slow mode nothing changes.
  void startInterval() {
    if (_disposed) return;
    if (value.slowMode case final SlowMode$Active slow) {
      update(
        (c) => c.copyWith(
          slowMode: slow.copyWith(nextSendAt: _now().add(slow.interval)),
        ),
      );
    }
  }

  /// Folds [inFlight] (the outbox's send in flight for the chat) into slow
  /// mode's `pending`, from now until [dispose]: the composer and the
  /// picker hold the next send while one is still sending.
  void followSendInFlight(listen.ValueListenable<bool> inFlight) {
    _$inFlight?.removeListener(_foldInFlight);
    _$inFlight = inFlight..addListener(_foldInFlight);
    _foldInFlight();
  }

  listen.ValueListenable<bool>? _$inFlight;

  void _foldInFlight() {
    final pending = _$inFlight?.value ?? false;
    if (_disposed) return;
    if (value.slowMode case final SlowMode$Active slow
        when slow.pending != pending) {
      update((c) => c.copyWith(slowMode: slow.copyWith(pending: pending)));
    }
  }

  // --- Lifting a restriction --------------------------------------------------

  /// The action of the composer's default panel for [access]: the lift of an
  /// `unlockable` restriction; null for the other panels (text alone).
  ComposerPanelAction? accessAction(WriteAccess access) => switch (access) {
    WriteAccess$Restricted(reason: DenialReason$Unlockable(:final kind)) =>
      ComposerPanelAction(
        label: strings.unlockAction(kind),
        onTap: () => lift(kind),
      ),
    _ => null,
  };

  /// Lifts every restriction that [kind] unlocks: the write access and each
  /// right denied as `unlockable(kind)`.
  ///
  /// The demo's stand-in for the host's purchase or boost; a real one is a
  /// request, guarded while in flight. The guard here is the value itself:
  /// once lifted, a repeat finds nothing to lift and changes nothing.
  void lift(String kind) {
    bool locked(Capability capability) => switch (capability) {
      Capability$Denied(reason: DenialReason$Unlockable(kind: final k)) =>
        k == kind,
      _ => false,
    };
    Capability open(Capability right) =>
        locked(right) ? const Capability.allowed() : right;
    final current = value;
    final sending = current.sending;
    final media = sending.media;
    final unlocked = MediaKindSet.of({
      for (final MapEntry(key: mediaKind, value: reason)
          in media.denials.entries)
        if (reason case DenialReason$Unlockable(kind: final k) when k == kind)
          mediaKind,
    });
    final next = current.copyWith(
      writeAccess: switch (current.writeAccess) {
        WriteAccess$Restricted(reason: DenialReason$Unlockable(kind: final k))
            when k == kind =>
          const WriteAccess.canWrite(),
        final access => access,
      },
      sending: sending
          .map(open)
          .copyWith(
            media: SendableMedia(
              allowed: media.allowed | unlocked,
              denials: {
                for (final MapEntry(:key, value: reason)
                    in media.denials.entries)
                  if (!unlocked.contains(key)) key: reason,
              },
            ),
          ),
    );
    if (next != current) set(next);
  }

  // --- Feedback --------------------------------------------------------------

  /// The words of [action] denied for [reason], now.
  String denialText(CapabilityAction action, DenialReason reason) =>
      strings.text(action, reason, now: _now());

  /// Shows [action] denied for [reason] as [feedback] does, for a
  /// component that reports the attempt itself (the outbox).
  void showDenied(CapabilityAction action, DenialReason reason) =>
      _showDenied(action, reason);

  void _showDenied(CapabilityAction action, DenialReason reason) {
    if (_disposed || bulletins.isDisposed) return;
    bulletins.show(
      ChatBulletins.denied(
        strings.text(action, reason, now: _now()),
        hint: _hint,
        action: switch (reason) {
          DenialReason$Unlockable(:final kind) => BulletinAction.button(
            label: strings.unlockAction(kind),
            onPressed: () => lift(kind),
          ),
          _ => null,
        },
      ),
    );
  }

  // The touch families show a denial as a hint at the control it was tried
  // on; desktop and the web as a toast.
  static bool _touchFamily() =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia => true,
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => false,
      };

  /// Stops changing the value; the bulletins are the screen's.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _$inFlight?.removeListener(_foldInFlight);
    _value.dispose();
  }
}
