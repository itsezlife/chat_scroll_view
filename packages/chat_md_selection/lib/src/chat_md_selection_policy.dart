import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';

/// Selection policy for message↔text entry, nesting, and Copy.
sealed class ChatMdSelectionPolicy {
  /// Base constructor for policy variants.
  const ChatMdSelectionPolicy();

  /// Nested text subject; Copy clears message mode.
  const factory ChatMdSelectionPolicy.mobile() = ChatMdSelectionPolicy$Mobile;

  /// Exclusive modes; Copy keeps the character range.
  const factory ChatMdSelectionPolicy.desktop() = ChatMdSelectionPolicy$Desktop;

  /// Default from OS family. Pass [platform] / [isWeb] to pin in tests.
  factory ChatMdSelectionPolicy.forPlatform({
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    if (isWeb ?? kIsWeb) {
      return const ChatMdSelectionPolicy.desktop();
    }
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.android =>
        const ChatMdSelectionPolicy.mobile(),
      _ => const ChatMdSelectionPolicy.desktop(),
    };
  }

  /// Whether text entry may proceed when [messageId] is not message-selected.
  bool get allowsTextEntryWithoutMessageSelection;

  /// Whether span-yield long-press may claim text entry.
  bool get claimsSpanYieldForTextEntry;

  /// Whether the text subject must remain in the selected set while active.
  bool get nestsTextSubjectInMessageSelection;

  /// Membership side effects when entering text for [messageId].
  void applyEnterMembership(ChatSelectionController messages, int messageId);

  /// Post-clipboard Copy-success side effects.
  ///
  /// [clearTextSelection] / [clearMessageSelection] are host-supplied so this
  /// type does not own clipboard I/O.
  void applyCopySuccess({
    required VoidCallback clearTextSelection,
    required VoidCallback clearMessageSelection,
  });
}

/// Mobile selection policy.
///
/// Message-then-text entry (span yield / Select text on an already-selected
/// message); nested subject; dismiss-text keeps the subject selected; Copy
/// success clears text and message mode. See ADR 012.
final class ChatMdSelectionPolicy$Mobile implements ChatMdSelectionPolicy {
  /// Creates the mobile policy variant.
  const ChatMdSelectionPolicy$Mobile();

  @override
  bool get allowsTextEntryWithoutMessageSelection => false;

  @override
  bool get claimsSpanYieldForTextEntry => true;

  @override
  bool get nestsTextSubjectInMessageSelection => true;

  @override
  void applyEnterMembership(ChatSelectionController messages, int messageId) {
    messages.replaceSelectedIds(<int>{messageId});
  }

  @override
  void applyCopySuccess({
    required VoidCallback clearTextSelection,
    required VoidCallback clearMessageSelection,
  }) {
    clearTextSelection();
    clearMessageSelection();
  }
}

/// Desktop / web selection policy.
///
/// Direct character-range entry without prior message membership; text-active
/// and message membership are mutually exclusive; Copy writes the clipboard
/// only and keeps the range; dismiss clears text. See ADR 012.
final class ChatMdSelectionPolicy$Desktop implements ChatMdSelectionPolicy {
  /// Creates the desktop / web policy variant.
  const ChatMdSelectionPolicy$Desktop();

  @override
  bool get allowsTextEntryWithoutMessageSelection => true;

  @override
  bool get claimsSpanYieldForTextEntry => false;

  @override
  bool get nestsTextSubjectInMessageSelection => false;

  @override
  void applyEnterMembership(ChatSelectionController messages, int messageId) {
    // Exclusive: text-active and message membership do not nest.
    messages.clear();
  }

  @override
  void applyCopySuccess({
    required VoidCallback clearTextSelection,
    required VoidCallback clearMessageSelection,
  }) {
    // Clipboard only — keep the character range.
  }
}
