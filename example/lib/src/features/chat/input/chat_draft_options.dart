import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_link_preview.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:listen/listen.dart' as listen;
import 'package:message_media/message_media.dart';

/// The operations of the `overlay` diagnostics events the chat's wiring of
/// the draft options emits. The overlay's own are `OverlayOp`'s.
enum ChatDraftOptionsOp implements DiagnosticOp {
  /// A host hook the draft options need is not wired (warning): `hook`, a
  /// [ChatDraftOptionsHook] name.
  wiringMissing,
}

/// A host hook of the draft options, as `wiringMissing` names it.
enum ChatDraftOptionsHook {
  /// The live preview's bubble: the overlay draws a stand-in without it.
  bubbleBuilder,

  /// The preview's link taps with their contour: a tap the bubble could not
  /// outline chooses the link with no mark.
  onLinkTap,

  /// The carrying out of the keyboard intent: without it a policy that
  /// holds the keyboard states nothing, and the keyboard stays as it is.
  keyboardIntent,
}

/// The chat's draft options: the link preview strip's open (and, on the
/// web, hover) action opens them on the composer's draft, and their edits
/// go into the draft through the [linkPreview] watcher, whose changes the
/// draft store keeps.
///
/// One per chat screen, made and disposed with the input set. It is the
/// overlay's [DraftOptionsHost]:
///
/// - **Edits.** Position and size go to the watcher's `invertMedia` and
///   media; another link to `ChatLinkPreview.choose`; remove has already
///   applied the shared [ChatLinkPreview.dismissal] (the remove row's), so
///   the watcher only follows it ([ChatLinkPreview.dismissalApplied]).
/// - **Another link.** A tap on a link of the preview is looked up through
///   [ChatLinkPreview.lookUp]: under live apply the edit has chosen it, and
///   that is the strip's own lookup; under commit on save it is a lookup the
///   strip does not show, so a cancel leaves the strip on its link.
/// - **The page.** While the strip's card resolves, the open overlay
///   follows it, as long as the overlay previews the card's link.
/// - **Denied previews.** The watcher's availability turns the controllers'
///   `linkPreviewsAllowed`: an overlay that is up closes with its motion,
///   then reports the preview removed.
/// - **Size row.** A page's media is read through the chat's
///   [MessageMediaPolicy] size rule (`LinkPreviewMediaSizeRule`).
///
/// The policy is the platform's unless one is given, read at the first
/// open (iPad's from the window's width class then). The web's is the menu
/// anchored at the strip ([DraftOptionsWebMenuController]); the others the
/// overlay ([DraftOptionsController]).
final class ChatDraftOptions implements DraftOptionsHost {
  /// The draft options of [composer]'s draft, whose link preview is
  /// [linkPreview].
  ///
  /// [bubbleBuilder] draws the live preview (a stand-in, reported as
  /// missing, when null); [mediaPolicy] is the chat's, whose size rule the
  /// size row follows; [carriesKeyboardIntent] says whether the host carries
  /// the composer's keyboard intent out. [policy] overrides the platform's;
  /// [correlation] gives the events' ids.
  ChatDraftOptions({
    required this.linkPreview,
    required this.composer,
    required this.mediaPolicy,
    this.bubbleBuilder,
    this.carriesKeyboardIntent = true,
    DraftOptionsPolicy? policy,
    ChatCorrelation Function()? correlation,
    ComposerClock clock = ComposerClock.system,
  }) : _policy = policy,
       _correlation = correlation,
       _clock = clock {
    linkPreview.card.addListener(_onCard);
    linkPreview.draftChanged.addListener(_onDraftChanged);
  }

  /// The watcher of the draft's link preview.
  final ChatLinkPreview linkPreview;

  /// The composer whose draft the options edit.
  final ComposerController composer;

  /// The chat's media policy.
  final MessageMediaPolicy mediaPolicy;

  /// Draws the live preview; null draws a stand-in.
  final DraftOptionsBubbleBuilder? bubbleBuilder;

  /// Whether the host carries the composer's keyboard intent out.
  final bool carriesKeyboardIntent;

  final ChatCorrelation Function()? _correlation;
  final ComposerClock _clock;
  DraftOptionsPolicy? _policy;
  DraftOptionsController? _overlay;
  DraftOptionsWebMenuController? _menu;
  var _disposed = false;

  /// The open overlay's session, or null (none is up, or the web's menu).
  DraftOptionsSession? get overlaySession => _overlay?.session;

  /// The strip's open action: opens the draft options at the link page on
  /// the strip at [stripRect] (global), over [context]'s window.
  void open(BuildContext context, Rect stripRect) {
    if (_disposed) return;
    final input = _input();
    if (input == null) return;
    switch (_policyOf(context)) {
      case final DraftOptionsPolicy$Web web:
        _menuOf(web).open(context, stripRect);
      case final policy:
        final opened = _overlayOf(policy).open(
          context,
          value: input.value,
          page: input.page,
          text: input.text,
          stripRect: stripRect,
          links: input.links,
        );
        if (opened && bubbleBuilder == null) {
          _missing(ChatDraftOptionsHook.bubbleBuilder);
        }
    }
  }

  /// The strip's hover report on the web, where a mouse resting on it opens
  /// the menu; null on the other platforms, which open on a tap only.
  ComposerLinkPreviewHover? hoverOf(BuildContext context) =>
      switch (_policyOf(context)) {
        final DraftOptionsPolicy$Web web => (rect) {
          if (!_disposed) _menuOf(web).hover(context, rect);
        },
        _ => null,
      };

  /// Closes what is up at once and stops following the watcher.
  /// Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    linkPreview.card.removeListener(_onCard);
    linkPreview.draftChanged.removeListener(_onDraftChanged);
    _overlay?.dispose();
    _menu?.dispose();
  }

  // --- DraftOptionsHost ----------------------------------------------------

  @override
  void linkPartEdited(DraftLinkPart part) {
    if (_disposed) return;
    final options = part.options;
    if (options.removed) {
      // The remove row reports the edit, then applies the shared dismissal:
      // the watcher follows once it has. Denied previews are its own.
      scheduleMicrotask(() {
        if (!_disposed) linkPreview.dismissalApplied();
      });
      return;
    }
    if (linkPreview.card.value?.url != options.url) {
      linkPreview.choose(options.url);
    }
    linkPreview
      ..setMedia(options.media)
      ..invertMedia = part.invertMedia;
  }

  @override
  listen.ValueListenable<LinkPreviewState> chooseLink(Uri url) =>
      linkPreview.lookUp(url);

  // --- Wiring --------------------------------------------------------------

  DraftOptionsPolicy _policyOf(BuildContext context) =>
      _policy ??= DraftOptionsPolicy.forPlatform(
        defaultTargetPlatform,
        isWeb: kIsWeb,
        regularWidth: ChromeWidthClass.of(context) != ChromeWidthClass.compact,
      );

  DraftOptionsController _overlayOf(DraftOptionsPolicy policy) {
    if (_overlay case final overlay?) return overlay;
    final holds = policy.keyboard.intent == ComposerKeyboardIntent.hold;
    if (holds && !carriesKeyboardIntent) {
      _missing(ChatDraftOptionsHook.keyboardIntent);
    }
    return _overlay = DraftOptionsController(
      policy: policy,
      host: this,
      bubbleBuilder: _bubble,
      // A hold nobody carries out would only block the keyboard requests.
      composer: carriesKeyboardIntent ? composer : null,
      clock: _clock,
      correlation: _correlation,
      dismissal: linkPreview.dismissal,
      mediaOf: _mediaOf,
    )..linkPreviewsAllowed = linkPreview.available;
  }

  DraftOptionsWebMenuController _menuOf(DraftOptionsPolicy$Web policy) =>
      _menu ??= DraftOptionsWebMenuController(
        policy: policy,
        host: this,
        input: () => _input() ?? _emptyInput,
        clock: _clock,
        correlation: _correlation,
        dismissal: linkPreview.dismissal,
        mediaOf: _mediaOf,
      )..linkPreviewsAllowed = linkPreview.available;

  // What a hover that outlived the card opens on: nothing to preview.
  static final _emptyInput = DraftOptionsInput(
    value: DraftLinkPart(options: LinkPreviewOptions(url: Uri())),
    page: LinkPreviewState.none,
  );

  /// The draft as the options open on it, or null without a card.
  DraftOptionsInput? _input() => switch (linkPreview.card.value) {
    final card? => DraftOptionsInput(
      value: DraftLinkPart(
        options: card.options,
        invertMedia: linkPreview.invertMedia,
      ),
      page: _stateOf(card),
      text: composer.richText,
      links: linkPreview.urls,
    ),
    null => null,
  };

  static LinkPreviewState _stateOf(ChatLinkPreviewCard card) =>
      switch (card.page) {
        final page? => LinkPreviewState.loaded(page),
        null => LinkPreviewState.pending,
      };

  Widget _bubble(BuildContext context, DraftOptionsPreview preview) =>
      switch (bubbleBuilder) {
        final build? => build(context, preview),
        null => _StandInBubble(preview: preview),
      };

  DraftLinkMedia _mediaOf(LinkPreview page, LinkPreviewOptions options) {
    final rule = mediaPolicy.linkPreview.mediaSize;
    final kind = switch (LinkPreviewMediaSizeRule.mediaOf(page)?.slot) {
      LinkPreviewMediaSlot.media => DraftLinkMediaKind.video,
      LinkPreviewMediaSlot.photo => DraftLinkMediaKind.photo,
      null => DraftLinkMediaKind.none,
    };
    return DraftLinkMedia(
      kind: kind,
      shrinkable: rule.offersSwitch(page),
      large: rule.resolve(page, options: options) == LinkPreviewMediaSize.large,
    );
  }

  void _onCard() {
    final overlay = _overlay;
    final card = linkPreview.card.value;
    if (overlay == null || card == null) return;
    // A link chosen in the overlay is followed by its own lookup.
    if (overlay.session?.value.value.options.url != card.url) return;
    overlay.page = _stateOf(card);
  }

  void _onDraftChanged() {
    final allowed = linkPreview.available;
    _overlay?.linkPreviewsAllowed = allowed;
    _menu?.linkPreviewsAllowed = allowed;
  }

  void _missing(ChatDraftOptionsHook hook) =>
      ChatDraftOptionsDiagnostics.wiringMissing(hook, _correlation);
}

/// The `wiringMissing` event, for the parts of the wiring that find a hook
/// missing (the options, the preview's bubble).
abstract final class ChatDraftOptionsDiagnostics {
  /// Reports [hook] missing, with [correlation]'s ids.
  static void wiringMissing(
    ChatDraftOptionsHook hook,
    ChatCorrelation Function()? correlation,
  ) => ChatDiagnostics.current.emit(
    ChatEventLevel.warning,
    ChatEventCategory.overlay,
    ChatDraftOptionsOp.wiringMissing,
    correlation: correlation?.call() ?? ChatCorrelation.none,
    fields: () => {'hook': hook.name},
  );
}

/// The preview without the host's bubble: the draft's text in chrome type.
class _StandInBubble extends StatelessWidget {
  const _StandInBubble({required this.preview});

  final DraftOptionsPreview preview;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(preview.text.plain, style: ChromeTypography.of(context)),
  );
}
