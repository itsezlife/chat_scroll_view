import 'dart:async';

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart' show ChatCorrelation;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:listen/listen.dart' as listen;
import 'package:panel_shell/panel_shell.dart';

/// Keeps the panel's sticker and GIF pages in step with one chat's
/// capabilities: the host side of the panel's page availability.
///
/// The sticker page follows `sending.stickers` and the GIF page
/// `sending.media`'s animations; this host keeps the two apart, as the
/// packages do. A denied page takes [form] with the text of [feedback]'s
/// `denialText` for the action and reason (none for a hidden page, which
/// shows no text), and an allowed one is available. A try on a dimmed page
/// ([PageDenied]) goes to [feedback]'s `onDenied` as an attempt from the
/// panel, which reports it.
///
/// Created and disposed with the panel's controller.
final class ChatPanelAvailability {
  /// Binds [shell]'s [stickersPageId] and [gifPageId] to [capabilities],
  /// at once and on each new value.
  ChatPanelAvailability({
    required this.shell,
    required this.capabilities,
    required this.feedback,
    required this.stickersPageId,
    required this.gifPageId,
    String? chatId,
    PageUnavailableForm? form,
  }) : form = form ?? platformForm(defaultTargetPlatform, isWeb: kIsWeb),
       _correlation = ChatCorrelation(chatId: chatId) {
    capabilities.addListener(_apply);
    _events = shell.events.listen(_onEvent);
    _apply();
  }

  /// The panel's controller.
  final PanelShellController shell;

  /// The chat's capabilities.
  final listen.ValueListenable<ChatCapabilities> capabilities;

  /// The denial texts and the report of attempts.
  final CapabilityFeedback feedback;

  /// The id of the sticker page in [shell].
  final String stickersPageId;

  /// The id of the GIF page in [shell].
  final String gifPageId;

  /// The form a denied page takes; the platform's by default
  /// ([platformForm]).
  final PageUnavailableForm form;

  /// The form of [platform]'s family; the web is not desktop.
  ///
  /// Until the chrome reads the window's width class and input class, a
  /// web panel takes the mobile form of the browser's family: [hidden] for
  /// an iOS browser, [dimmed] for any other (a desktop browser too).
  ///
  /// [hidden]: PageUnavailableForm.hidden
  /// [dimmed]: PageUnavailableForm.dimmed
  static PageUnavailableForm platformForm(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    if (!isWeb) return PageUnavailableForm.forPlatform(platform);
    return platform == TargetPlatform.iOS
        ? PageUnavailableForm.hidden
        : PageUnavailableForm.dimmed;
  }

  final ChatCorrelation _correlation;
  late final StreamSubscription<PanelEvent> _events;
  var _disposed = false;

  // The action a page stands for, with why the chat denies it now; null
  // while it is allowed or for another page.
  (CapabilityAction, DenialReason)? _denial(String pageId) {
    final sending = capabilities.value.sending;
    if (pageId == stickersPageId) {
      return switch (sending.stickers) {
        Capability$Denied(:final reason) => (
          CapabilityAction.sendSticker,
          reason,
        ),
        Capability$Allowed() => null,
      };
    }
    if (pageId == gifPageId) {
      return switch (sending.media.reasonFor(MediaKind.animation)) {
        final reason? => (CapabilityAction.sendAnimation, reason),
        null => null,
      };
    }
    return null;
  }

  void _apply() {
    if (_disposed) return;
    for (final pageId in [stickersPageId, gifPageId]) {
      shell.setPageAvailability(
        pageId,
        _availabilityOf(pageId),
        correlation: _correlation,
      );
    }
  }

  PageAvailability _availabilityOf(String pageId) => switch (_denial(pageId)) {
    null => const PageAvailability.available(),
    _ when form == PageUnavailableForm.hidden => form.withText(null),
    (final action, final reason) => form.withText(
      feedback.denialText(
        action,
        reason,
        correlation: _correlation,
        form: switch (form) {
          PageUnavailableForm.dimmed => ChatPanelDenialForm.dimmedTab,
          PageUnavailableForm.hidden ||
          PageUnavailableForm.replaced => ChatPanelDenialForm.replacedPage,
        },
      ),
    ),
  };

  void _onEvent(PanelEvent event) {
    if (event case PageDenied(:final pageId)) {
      if (_denial(pageId) case (final action, final reason)) {
        feedback.onDenied(
          action,
          reason,
          consumer: CapabilityConsumer.panel,
          correlation: _correlation,
        );
      }
    }
  }

  /// Stops following the capabilities and the panel's events.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    capabilities.removeListener(_apply);
    unawaited(_events.cancel());
  }
}

/// Where the panel's host draws a denial text, named in the
/// `denialTextMissing` event when the chat's strings give none.
enum ChatPanelDenialForm implements DenialForm {
  /// The hint of a dimmed tab.
  dimmedTab,

  /// The text in place of a page's content.
  replacedPage,
}
