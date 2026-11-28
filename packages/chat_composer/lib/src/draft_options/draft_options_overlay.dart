import 'dart:async';

import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/draft_options/draft_link_part.dart';
import 'package:chat_composer/src/draft_options/draft_options_host.dart';
import 'package:chat_composer/src/draft_options/draft_options_policy.dart';
import 'package:chat_composer/src/draft_options/draft_options_session.dart';
import 'package:chat_composer/src/draft_options/overlay_op.dart';
import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/input/composer_keyboard_intent.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Opens and closes the **draft options overlay**: one overlay in the root
/// overlay over a `ChromeScrim`, with a page per draft part (the link page
/// in this cut), the live preview from the host's [bubbleBuilder] and its
/// edits reported to the [host] by the [policy]'s apply mode.
///
/// One per composer, kept by the host. The host calls [open] from the link
/// preview strip's open action, feeds the link's [page] while it resolves,
/// and turns [linkPreviewsAllowed] off when the chat denies previews: an
/// overlay that is up then closes with its animation, and the draft's
/// preview is reported removed after it is gone.
///
/// Given the [composer], it states the policy's keyboard intent through it
/// ([DraftOptionsPolicy.keyboard]): a raised keyboard held under the
/// overlay is reopened as it closes and its hold ended once it is gone; the
/// remove row ends the hold with [ComposerKeyboardIntent.hide]. The host
/// carries the intent out.
///
/// The web's [DraftOptionsPolicy$Web] has no overlay; its menu is a
/// different surface, and [open] asserts it is not asked for one.
final class DraftOptionsController {
  /// A controller of [policy] reporting to [host], drawing the preview with
  /// [bubbleBuilder].
  ///
  /// [correlation] gives the ids of its events (the chat);
  /// [reduceTransparency] is the host's setting, which leaves the scrim
  /// without its still; [composer] is the composer whose keyboard the
  /// overlay states its intent through, none stating nothing.
  DraftOptionsController({
    required this.policy,
    required this.host,
    required this.bubbleBuilder,
    this.composer,
    ComposerClock clock = ComposerClock.system,
    ChatCorrelation Function()? correlation,
    this.reduceTransparency = false,
  }) : _clock = clock,
       _correlation = correlation;

  /// Within this of an accepted open, another open is dropped and a press
  /// on the scrim passes through: a burst of taps on the strip opens one
  /// overlay and does not close it again.
  static const Duration openGuard = ChromeTapTiming.repeatGuard;

  /// How the overlay is presented and applied.
  final DraftOptionsPolicy policy;

  /// Where edits go.
  final DraftOptionsHost host;

  /// Builds the live preview.
  final DraftOptionsBubbleBuilder bubbleBuilder;

  /// The composer the keyboard intent is stated through; null states none.
  final ComposerController? composer;

  /// Whether the scrim takes no still, for the host's reduce-transparency
  /// setting.
  final bool reduceTransparency;

  final ComposerClock _clock;
  final ChatCorrelation Function()? _correlation;
  _OpenOverlay? _open;
  DateTime? _acceptedAt;
  bool _allowed = true;
  bool _disposed = false;
  // A hold's pending reopen and release, from the last close.
  ComposerTimer? _reopenTimer;
  ComposerTimer? _releaseTimer;
  var _releaseReopened = false;

  /// The open overlay's session, or null when none is up. A session that is
  /// closing stays here until its overlay is gone.
  DraftOptionsSession? get session => _open?.session;

  /// Whether an overlay is up (closing included).
  bool get isOpen => _open != null;

  /// Whether the chat allows link previews. Turned off while an overlay is
  /// up, it closes the overlay (trigger `denied`) and, once it is gone,
  /// reports the preview removed; while off, [open] refuses.
  bool get linkPreviewsAllowed => _allowed;
  set linkPreviewsAllowed(bool allowed) {
    if (allowed == _allowed) return;
    _allowed = allowed;
    if (allowed) return;
    _open?.session.close(DraftOptionsCloseTrigger.denied);
  }

  /// The link's page moved to [state]; the open overlay's preview follows.
  set page(LinkPreviewState state) => _open?.session.pageState = state;

  /// Opens the overlay at [part] over the window of [context], with the
  /// host's current [value], the link's [page] and the draft's [text]; true
  /// when it opened. [links] are the text's links in text order, the ones a
  /// tap in the live preview may choose (none: every tap is ignored).
  ///
  /// Called between frames (a tap handler), so the scrim's still is of the
  /// window without the overlay. [stripRect] is the strip's global rect, the
  /// origin of a presentation that grows from it.
  ///
  /// Refused while link previews are denied, while an overlay is up, and on
  /// a policy that does not open on a pending page while [page] is not
  /// loaded; an open within [openGuard] of the accepted one is dropped.
  bool open(
    BuildContext context, {
    required DraftLinkPart value,
    required LinkPreviewState page,
    model.RichText text = model.RichText.empty,
    DraftPart part = DraftPart.link,
    Rect? stripRect,
    List<Uri> links = const [],
  }) {
    assert(
      policy.usesOverlay,
      'The web draft options are a menu anchored at the strip, not this '
      'overlay.',
    );
    final scrimPreset = policy.scrim;
    if (_disposed || scrimPreset == null) return false;
    final now = _clock.now();
    if (_acceptedAt case final accepted?
        when now.difference(accepted) < openGuard) {
      final ms = now.difference(accepted).inMilliseconds;
      _emit(ChatEventLevel.debug, OverlayOp.openDropped, () => {'ms': ms});
      return false;
    }
    final refused = switch (page) {
      _ when !_allowed => 'denied',
      _ when _open != null => 'alreadyOpen',
      LinkPreviewState$Loaded() => null,
      _ when !policy.opensOnPending => 'desktopNotLoaded',
      _ => null,
    };
    if (refused != null) {
      _emit(
        ChatEventLevel.debug,
        OverlayOp.openRefused,
        () => {'why': refused},
      );
      return false;
    }
    _acceptedAt = now;
    final keyboardWasUp =
        (MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0) > 0;
    final held = _stateKeyboard(keyboardWasUp: keyboardWasUp);
    late final _OpenOverlay open;
    final session = DraftOptionsSession(
      policy: policy,
      host: host,
      part: part,
      initial: value,
      page: page,
      origin: stripRect,
      links: links,
      clock: _clock,
      keyboardWasUp: keyboardWasUp,
      correlation: _correlation,
      onClose: (trigger) => _closed(open, trigger),
    );
    final scrim = ChromeScrimController(
      context,
      preset: scrimPreset,
      reduceTransparency: reduceTransparency,
      onPhase: (phase) => _scrimPhase(scrimPreset, phase),
      onDismiss: (by) => session.close(switch (by) {
        ChromeScrimDismissal.outside => DraftOptionsCloseTrigger.outside,
        ChromeScrimDismissal.back => DraftOptionsCloseTrigger.back,
        ChromeScrimDismissal.escape => DraftOptionsCloseTrigger.escape,
      }),
    );
    final entry = OverlayEntry(
      builder: (context) => DraftOptionsOverlay(
        session: session,
        scrim: scrim,
        bubbleBuilder: bubbleBuilder,
        text: text,
        passesPresses: () =>
            _clock.now().difference(now) < openGuard && !session.isClosing,
      ),
    );
    open = _open = _OpenOverlay(session, scrim, entry, held: held);
    Overlay.of(context, rootOverlay: true).insert(entry);
    return true;
  }

  /// Takes an open overlay away at once (trigger `disposed`) and opens no
  /// more.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_open case final open?) {
      open.session.close(DraftOptionsCloseTrigger.disposed);
    }
    _reopenTimer?.cancel();
    if (_releaseTimer case final release?) {
      // A hold still waiting for its release ends now, without its delay.
      release.cancel();
      _releaseHold(reopened: _releaseReopened);
    }
  }

  // --- Keyboard intent ---

  /// States the policy's intent for an open with [keyboardWasUp]; true when
  /// it holds the keyboard.
  bool _stateKeyboard({required bool keyboardWasUp}) {
    final composer = this.composer;
    if (composer == null) return false;
    _reopenTimer?.cancel();
    _reopenTimer = null;
    _releaseTimer?.cancel();
    _releaseTimer = null;
    final intent = switch (policy.keyboard.intent) {
      // Nothing to hold: the keyboard is down.
      ComposerKeyboardIntent.hold when !keyboardWasUp =>
        ComposerKeyboardIntent.keep,
      final intent => intent,
    };
    composer.setKeyboardIntent(intent);
    _emitIntent(intent, keyboardWasUp: keyboardWasUp, reopened: false);
    return intent == ComposerKeyboardIntent.hold;
  }

  /// A held keyboard on a close by [trigger]: reopened after the policy's
  /// delay unless the remove row closed it or the owner went away.
  void _closeKeyboard(DraftOptionsCloseTrigger trigger) {
    final composer = this.composer;
    if (composer == null) return;
    final reopens = switch (trigger) {
      DraftOptionsCloseTrigger.remove ||
      DraftOptionsCloseTrigger.disposed => false,
      _ => true,
    };
    if (!reopens) return;
    _reopenTimer = _clock.after(policy.keyboard.reopenDelay, () {
      _reopenTimer = null;
      composer.reopenKeyboard();
    });
  }

  /// Ends a hold once the overlay is gone, after the policy's delay; at once
  /// for a controller going away.
  void _scheduleRelease(DraftOptionsCloseTrigger trigger) {
    final reopened = switch (trigger) {
      DraftOptionsCloseTrigger.remove ||
      DraftOptionsCloseTrigger.disposed => false,
      _ => true,
    };
    if (_disposed) {
      _releaseHold(reopened: reopened);
      return;
    }
    _releaseReopened = reopened;
    _releaseTimer = _clock.after(
      policy.keyboard.holdReleaseDelay,
      () => _releaseHold(reopened: reopened),
    );
  }

  void _releaseHold({required bool reopened}) {
    _releaseTimer = null;
    final composer = this.composer;
    if (composer == null) return;
    final intent = reopened
        ? ComposerKeyboardIntent.keep
        : ComposerKeyboardIntent.hide;
    composer.setKeyboardIntent(intent);
    _emitIntent(intent, keyboardWasUp: true, reopened: reopened);
  }

  void _emitIntent(
    ComposerKeyboardIntent intent, {
    required bool keyboardWasUp,
    required bool reopened,
  }) => _emit(
    ChatEventLevel.debug,
    OverlayOp.keyboardIntent,
    () => {
      'intent': intent.name,
      'keyboardWasUp': keyboardWasUp,
      'reopened': reopened,
    },
  );

  // --- Closing ---

  void _closed(_OpenOverlay open, DraftOptionsCloseTrigger trigger) {
    if (trigger == DraftOptionsCloseTrigger.disposed) {
      open.scrim.cancel();
    } else {
      open.scrim.close();
    }
    if (open.held) _closeKeyboard(trigger);
    unawaited(
      open.scrim.done.then((_) {
        open.entry.remove();
        if (identical(_open, open)) _open = null;
        if (open.held) _scheduleRelease(trigger);
        if (trigger == DraftOptionsCloseTrigger.denied) {
          open.session.reportRemoved();
        }
        // After the frame that drops the entry: its builders still listen.
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => open.session.dispose(),
        );
      }),
    );
  }

  void _scrimPhase(ChromeScrimPreset preset, ChromeScrimPhase phase) {
    Map<String, Object> base() => {
      'owner': 'draftOptions',
      'preset': preset.name,
    };
    switch (phase) {
      case ChromeScrimPhase$Captured(:final captureTime, :final stillSize):
        _emit(
          ChatEventLevel.trace,
          OverlayOp.scrimCaptured,
          () => {
            ...base(),
            'captureUs': captureTime.inMicroseconds,
            'stillWidth': stillSize.width.round(),
            'stillHeight': stillSize.height.round(),
          },
        );
      case ChromeScrimPhase$StillReady(:final makeTime, :final glassSource):
        _emit(
          ChatEventLevel.trace,
          OverlayOp.scrimStillReady,
          () => {
            ...base(),
            'cpuMs': makeTime.inMilliseconds,
            'glassSource': glassSource,
          },
        );
      case ChromeScrimPhase$StillSkipped(:final why):
        _emit(
          ChatEventLevel.debug,
          OverlayOp.scrimStillSkipped,
          () => {...base(), 'why': why.name},
        );
      case ChromeScrimPhase$Dismissed(:final by, :final closeOn):
        _emit(
          ChatEventLevel.debug,
          OverlayOp.scrimDismissed,
          () => {...base(), 'by': by.name, 'closeOn': closeOn.name},
        );
      case ChromeScrimPhase$Cancelled():
        _emit(ChatEventLevel.debug, OverlayOp.scrimCancelled, base);
      case ChromeScrimPhase$Disposed(:final stills):
        _emit(
          ChatEventLevel.trace,
          OverlayOp.scrimDisposed,
          () => {...base(), 'stills': stills},
        );
      case ChromeScrimPhase$CaptureFailed(:final error, :final glassSource):
        _emit(
          ChatEventLevel.error,
          OverlayOp.scrimCaptureFailed,
          () => {
            ...base(),
            'errorType': '${error.runtimeType}',
            'glassSource': glassSource,
          },
        );
    }
  }

  void _emit(
    ChatEventLevel level,
    OverlayOp op,
    Map<String, Object> Function() fields,
  ) => ChatDiagnostics.current.emit(
    level,
    ChatEventCategory.overlay,
    op,
    correlation: _correlation?.call() ?? ChatCorrelation.none,
    fields: fields,
  );
}

final class _OpenOverlay {
  _OpenOverlay(this.session, this.scrim, this.entry, {required this.held});

  final DraftOptionsSession session;
  final ChromeScrimController scrim;
  final OverlayEntry entry;

  /// Whether this open holds the keyboard.
  final bool held;
}

/// The draft options overlay's skin: the scrim, the text root and the open
/// part's page, over a [session].
///
/// A `DraftOptionsController` mounts it in the root overlay. The page holds
/// its title by the policy and the live preview from [bubbleBuilder]; the
/// link page's rows and each platform's presentation build on it. Under
/// commit on save, Enter saves (Escape is the scrim's).
class DraftOptionsOverlay extends StatelessWidget {
  /// The overlay of [session] over [scrim].
  const DraftOptionsOverlay({
    required this.session,
    required this.scrim,
    required this.bubbleBuilder,
    this.text = model.RichText.empty,
    this.passesPresses,
    super.key,
  });

  /// The key of the chosen link's highlight above the live preview.
  static const Key linkHighlightKey = ValueKey('draftOptionsLinkHighlight');

  /// The open's value, page and close.
  final DraftOptionsSession session;

  /// The scrim under the page.
  final ChromeScrimController scrim;

  /// Builds the live preview.
  final DraftOptionsBubbleBuilder bubbleBuilder;

  /// The draft's text, for the preview.
  final model.RichText text;

  /// While it answers true, presses pass through the overlay to what is
  /// under it (the opening's tap guard); null takes every press.
  final bool Function()? passesPresses;

  @override
  Widget build(BuildContext context) {
    Widget overlay = ChromeScrim(
      controller: scrim,
      child: Center(
        child: _DraftOptionsPage(
          session: session,
          bubbleBuilder: bubbleBuilder,
          text: text,
        ),
      ),
    );
    if (session.policy.apply == DraftOptionsApply.commitOnSave) {
      // The box takes focus, so Enter and Escape reach it: a scope of its
      // own, since the route's scope keeps its focus and would leave the
      // scrim's autofocus unheard. Live apply leaves focus (and a raised
      // keyboard) where it is.
      overlay = FocusScope(
        autofocus: true,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: overlay,
        ),
      );
    }
    if (passesPresses case final passes?) {
      overlay = _PressPassThrough(passes: passes, child: overlay);
    }
    return ChromeTextRoot(child: overlay);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    session.apply();
    return KeyEventResult.handled;
  }
}

class _DraftOptionsPage extends StatelessWidget {
  const _DraftOptionsPage({
    required this.session,
    required this.bubbleBuilder,
    required this.text,
  });

  final DraftOptionsSession session;
  final DraftOptionsBubbleBuilder bubbleBuilder;
  final model.RichText text;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final strings = ChromeStringsScope.composerOf(context).draftOptions;
    final style = ChromeTypography.of(context);
    final (title, subtitle) = switch (session.policy.title) {
      DraftOptionsTitle.titleAndSubtitle => (
        strings.linkTitle,
        strings.linkSubtitle,
      ),
      // One part in this cut: the title shows.
      DraftOptionsTitle.titleWithOnePart => (strings.linkTitle, null),
      DraftOptionsTitle.none => (null, null),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.surface),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?switch (title) {
            final title? => Text(
              title,
              style: style.copyWith(fontWeight: FontWeight.bold),
            ),
            null => null,
          },
          ?switch (subtitle) {
            final subtitle? => Text(subtitle, style: style),
            null => null,
          },
          Stack(
            children: [
              ValueListenableBuilder(
                valueListenable: session.page,
                builder: (context, page, _) => ValueListenableBuilder(
                  valueListenable: session.value,
                  builder: (context, part, _) => bubbleBuilder(
                    context,
                    DraftOptionsPreview(
                      text: text,
                      part: part,
                      page: page,
                      onLinkTap: session.tapLink,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: _DraftLinkHighlightLayer(highlight: session.highlight),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chosen link's mark above the live preview: its contour filled in the
/// accent and, while its page is pending, a spinner over it.
///
/// A layer of its own over the host's bubble, so the bubble's text engine
/// draws nothing new; it takes no presses, so a tap on another link still
/// reaches the bubble.
class _DraftLinkHighlightLayer extends StatelessWidget {
  const _DraftLinkHighlightLayer({required this.highlight});

  /// The size of the spinner over a pending link.
  static const double _spinnerExtent = 20;

  final ValueListenable<DraftLinkHighlight?> highlight;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder(
      valueListenable: highlight,
      builder: (context, shown, _) => switch (shown) {
        null => const SizedBox.shrink(),
        final shown => _mark(context, shown),
      },
    ),
  );

  Widget _mark(BuildContext context, DraftLinkHighlight shown) {
    final accent = ChromeThemeScope.paletteOf(context).accent;
    final center = shown.contour.getBounds().center;
    return Stack(
      key: DraftOptionsOverlay.linkHighlightKey,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ContourPainter(
              shown.contour,
              accent.withValues(alpha: 0.2),
            ),
          ),
        ),
        if (shown.pending)
          Positioned(
            left: center.dx - _spinnerExtent / 2,
            top: center.dy - _spinnerExtent / 2,
            child: const ChromeSpinner(
              extent: _spinnerExtent,
              strokeWidth: 2,
              inset: 2,
            ),
          ),
      ],
    );
  }
}

class _ContourPainter extends CustomPainter {
  _ContourPainter(this.contour, this.color);

  final Path contour;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawPath(contour, Paint()..color = color);

  @override
  bool shouldRepaint(_ContourPainter old) =>
      !identical(old.contour, contour) || old.color != color;
}

/// Lets presses through to what is under it while [passes] answers true.
class _PressPassThrough extends SingleChildRenderObjectWidget {
  const _PressPassThrough({required this.passes, super.child});

  final bool Function() passes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPressPassThrough(passes);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPressPassThrough renderObject,
  ) => renderObject.passes = passes;
}

class _RenderPressPassThrough extends RenderProxyBox {
  _RenderPressPassThrough(this.passes);

  bool Function() passes;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !passes() && super.hitTest(result, position: position);
}
