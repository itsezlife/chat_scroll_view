import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/draft_options/draft_link_page.dart';
import 'package:chat_composer/src/draft_options/draft_options_gate.dart';
import 'package:chat_composer/src/draft_options/draft_options_host.dart';
import 'package:chat_composer/src/draft_options/draft_options_overlay.dart';
import 'package:chat_composer/src/draft_options/draft_options_policy.dart';
import 'package:chat_composer/src/draft_options/draft_options_session.dart';
import 'package:chat_composer/src/draft_options/draft_options_web_menu.dart';
import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/link_preview/link_preview_dismissal.dart';
import 'package:chat_composer/src/spec/composer_header.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The draft options as one thing a host binds the link preview strip to:
/// the overlay ([DraftOptionsController]) or, on the web, the menu anchored
/// at the strip ([DraftOptionsWebMenuController]), whichever the policy
/// calls for.
///
/// One per composer, kept by the host, which wires the strip's open action
/// to [open] and its hover to [hoverOf], feeds the link's [page] while the
/// strip's card resolves, and turns [linkPreviewsAllowed] by the chat's
/// rights. Each reaches whichever form is up, so a host cannot feed one
/// and miss the other.
///
/// The policy is the given one at every open; without one it is the
/// platform's ([DraftOptionsPolicy.forPlatform]) picked at each open from
/// the window it opens in, so an iPad window that became regular width
/// opens the iPad form next time. A form changes only between opens: the
/// one that is up stays until it closes.
final class DraftOptionsEntry {
  /// The draft options of [host], opening on what [input] answers and
  /// drawing the overlay's live preview with [bubbleBuilder].
  ///
  /// [policy] fixes the form (the platform's at each open when null);
  /// [composer] is the composer the overlay states its keyboard intent
  /// through (none when null); [dismissal] is what the remove row applies,
  /// as the strip's cross does; [mediaOf] reads a page's media for the size
  /// row; [correlation] gives the events' ids; [reduceTransparency] leaves
  /// the scrim without its still.
  DraftOptionsEntry({
    required this.host,
    required this.input,
    required this.bubbleBuilder,
    DraftOptionsPolicy? policy,
    this.composer,
    this.dismissal,
    this.mediaOf,
    this.reduceTransparency = false,
    ComposerClock clock = ComposerClock.system,
    ChatCorrelation Function()? correlation,
  }) : _policy = policy,
       _clock = clock,
       _correlation = correlation;

  /// Where edits go.
  final DraftOptionsHost host;

  /// The draft as the options open on it, read at the open; null when the
  /// draft has no link.
  final DraftOptionsInput? Function() input;

  /// Builds the overlay's live preview.
  final DraftOptionsBubbleBuilder bubbleBuilder;

  /// The composer the overlay states its keyboard intent through.
  final ComposerController? composer;

  /// What the remove row turns off.
  final LinkPreviewDismissal? dismissal;

  /// The host's reading of a page's media for the size row.
  final DraftLinkMediaReader? mediaOf;

  /// Whether the scrim takes no still.
  final bool reduceTransparency;

  final DraftOptionsPolicy? _policy;
  final ComposerClock _clock;
  final ChatCorrelation Function()? _correlation;
  // Reports an overlay open with no draft link; the menu's own gate
  // reports its.
  late final _noDraft = DraftOptionsGate(
    clock: _clock,
    correlation: _correlation,
  );
  _Form? _form;
  bool _allowed = true;
  bool _disposed = false;

  /// The open session, overlay or menu, or null when none is up (a closing
  /// one stays until it is gone).
  DraftOptionsSession? get session => _form?.session;

  /// Whether the options are up (closing included).
  bool get isOpen => _form?.isOpen ?? false;

  /// Whether the chat allows link previews. Turned off while the options
  /// are up, they close (trigger `denied`) and, once gone, report the
  /// preview removed ([DraftOptionsHost.previewDenied]); while off, nothing
  /// opens.
  bool get linkPreviewsAllowed => _allowed;
  set linkPreviewsAllowed(bool allowed) {
    _allowed = allowed;
    _form?.allowed = allowed;
  }

  /// The link's page moved to [state]; the options that are up follow.
  set page(LinkPreviewState state) => _form?.page = state;

  /// The policy an open at [context] takes: the given one, or the
  /// platform's for the window there.
  DraftOptionsPolicy policyOf(BuildContext context) =>
      _policy ??
      DraftOptionsPolicy.forPlatform(
        defaultTargetPlatform,
        isWeb: kIsWeb,
        regularWidth: ChromeWidthClass.of(context) != ChromeWidthClass.compact,
      );

  /// The strip's open action: opens the options at the link page on the
  /// strip at [stripRect] (global), over [context]'s window; true when they
  /// opened. Refused with no draft link, while previews are denied or the
  /// options are up, and as the form's own rules say.
  bool open(BuildContext context, Rect stripRect) {
    if (_disposed) return false;
    switch (_formFor(policyOf(context))) {
      case _Menu(:final menu):
        return menu.open(context, stripRect);
      case _Overlay(:final overlay):
        final draft = input();
        if (draft == null) {
          _noDraft.refuse(DraftOptionsOpenRefusal.noDraft);
          return false;
        }
        return overlay.open(
          context,
          value: draft.value,
          page: draft.page,
          text: draft.text,
          links: draft.links,
          stripRect: stripRect,
        );
    }
  }

  /// The strip's hover report where a mouse resting on it opens the
  /// options (the web's menu); null where only a tap opens them.
  ComposerLinkPreviewHover? hoverOf(BuildContext context) =>
      switch (policyOf(context)) {
        final DraftOptionsPolicy$Web policy => (rect) {
          if (_disposed) return;
          if (_formFor(policy) case _Menu(:final menu)) {
            menu.hover(context, rect);
          }
        },
        DraftOptionsOverlayPolicy() => null,
      };

  /// Takes what is up away at once and opens no more. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _form?.dispose();
  }

  // The form of [policy]: the current one while it fits or is up, else a
  // new one in its place.
  _Form _formFor(DraftOptionsPolicy policy) {
    if (_form case final form?
        when form.isOpen || form.policy.presentation == policy.presentation) {
      return form;
    }
    _form?.dispose();
    final form = switch (policy) {
      final DraftOptionsPolicy$Web policy => _Menu(
        DraftOptionsWebMenuController(
          policy: policy,
          host: host,
          input: input,
          clock: _clock,
          correlation: _correlation,
          dismissal: dismissal,
          mediaOf: mediaOf,
        ),
      ),
      final DraftOptionsOverlayPolicy policy => _Overlay(
        DraftOptionsController(
          policy: policy,
          host: host,
          bubbleBuilder: bubbleBuilder,
          composer: composer,
          clock: _clock,
          correlation: _correlation,
          reduceTransparency: reduceTransparency,
          dismissal: dismissal,
          mediaOf: mediaOf,
        ),
      ),
    }..allowed = _allowed;
    return _form = form;
  }
}

/// The form the entry holds: one controller, read through the same few
/// calls.
sealed class _Form {
  DraftOptionsPolicy get policy;
  DraftOptionsSession? get session;
  bool get isOpen;
  set allowed(bool allowed);
  set page(LinkPreviewState state);
  void dispose();
}

final class _Overlay extends _Form {
  _Overlay(this.overlay);

  final DraftOptionsController overlay;

  @override
  DraftOptionsPolicy get policy => overlay.policy;

  @override
  DraftOptionsSession? get session => overlay.session;

  @override
  bool get isOpen => overlay.isOpen;

  @override
  set allowed(bool allowed) => overlay.linkPreviewsAllowed = allowed;

  @override
  set page(LinkPreviewState state) => overlay.page = state;

  @override
  void dispose() => overlay.dispose();
}

final class _Menu extends _Form {
  _Menu(this.menu);

  final DraftOptionsWebMenuController menu;

  @override
  DraftOptionsPolicy get policy => menu.policy;

  @override
  DraftOptionsSession? get session => menu.session;

  @override
  bool get isOpen => menu.isOpen;

  @override
  set allowed(bool allowed) => menu.linkPreviewsAllowed = allowed;

  @override
  set page(LinkPreviewState state) => menu.page = state;

  @override
  void dispose() => menu.dispose();
}
