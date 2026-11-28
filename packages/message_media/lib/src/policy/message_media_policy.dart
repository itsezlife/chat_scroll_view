import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:message_media/src/chrome/media_chrome_slots.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/diagnostics/media_trace.dart';
import 'package:message_media/src/gesture/media_gesture_policy.dart';
import 'package:message_media/src/layout/link_preview_card.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/outgoing/media_send_flight_policy.dart';
import 'package:message_media/src/paint/media_cell_builders.dart';
import 'package:message_media/src/policy/link_preview_card_policy.dart';
import 'package:message_media/src/policy/media_autoplay_policy.dart';
import 'package:message_media/src/policy/media_box_sizing.dart';
import 'package:message_media/src/policy/media_corner_policy.dart';
import 'package:message_media/src/policy/media_file_stack_policy.dart';
import 'package:message_media/src/policy/media_layout_policy.dart';
import 'package:message_media/src/transition/media_transition_policy.dart';

/// The platform family a [MessageMediaPolicy]'s defaults come from.
enum MessageMediaPlatform {
  /// Android phones and tablets.
  android,

  /// iPhone and iPad.
  ios,

  /// macOS, Windows and Linux.
  desktop,
}

/// How a chat lays out and draws message media, with each platform's
/// defaults, overridable in parts.
///
/// One object per platform family: [MessageMediaPolicy.android],
/// [MessageMediaPolicy.ios], [MessageMediaPolicy.desktop], the web's
/// [MessageMediaPolicy.web] (by the window and the pointer, over the
/// browser's operating system's family), or the running app's with
/// [MessageMediaPolicy.platform]. A host changes one part with
/// [copyWith]: the layout step as a whole ([layoutStep]) or one of the
/// default step's parts through [MediaLayoutPolicy.copyWith], the file rows
/// ([fileStack]) or the link preview card ([linkPreview]), which every step
/// lays out by and the cells draw by, the corner
/// values ([corners]), the autoplay flag ([autoplay]), or one cell builder
/// ([cells], `MediaCellBuilders.copyWith`) leaving the other, the layout
/// transition's timings ([transition]), or a sent item's flight from its
/// send origin ([sendFlight]).
///
/// [layout] runs the step, resolves each cell's corner radii, and reports
/// `media` / `layoutComputed`; `MessageMediaView` paints the result with the
/// cell builders.
@immutable
final class MessageMediaPolicy {
  /// A policy of [family] laying media out with [layoutStep], rounding
  /// corners by [corners] and drawing cells with [cells].
  const MessageMediaPolicy({
    required this.family,
    required this.layoutStep,
    required this.corners,
    required this.autoplay,
    required this.chrome,
    required this.fileStack,
    required this.linkPreview,
    this.cells = const MediaCellBuilders(),
    this.transition = const MediaTransitionPolicy.none(),
    this.sendFlight = const MediaSendFlightPolicy.none(),
    this.gestures = const MediaGesturePolicy(),
  });

  /// The Android family's defaults.
  const MessageMediaPolicy.android()
    : this(
        family: MessageMediaPlatform.android,
        layoutStep: const MediaLayoutPolicy.android(),
        fileStack: const MediaFileStackPolicy.android(),
        linkPreview: const LinkPreviewCardPolicy.android(),
        corners: const MediaCornerPolicy.android(),
        autoplay: const MediaAutoplayPolicy.android(),
        chrome: const MediaChromeSlots.android(),
        transition: const MediaTransitionPolicy.android(),
        gestures: const MediaGesturePolicy.android(),
      );

  /// The iOS family's defaults.
  const MessageMediaPolicy.ios()
    : this(
        family: MessageMediaPlatform.ios,
        layoutStep: const MediaLayoutPolicy.ios(),
        fileStack: const MediaFileStackPolicy.ios(),
        linkPreview: const LinkPreviewCardPolicy.ios(),
        corners: const MediaCornerPolicy.ios(),
        autoplay: const MediaAutoplayPolicy.ios(),
        chrome: const MediaChromeSlots.ios(),
        transition: const MediaTransitionPolicy.ios(),
        sendFlight: const MediaSendFlightPolicy.ios(),
        gestures: const MediaGesturePolicy.ios(),
      );

  /// The desktop family's defaults.
  const MessageMediaPolicy.desktop()
    : this(
        family: MessageMediaPlatform.desktop,
        layoutStep: const MediaLayoutPolicy.desktop(),
        fileStack: const MediaFileStackPolicy.desktop(),
        linkPreview: const LinkPreviewCardPolicy.desktop(),
        corners: const MediaCornerPolicy.desktop(),
        autoplay: const MediaAutoplayPolicy.desktop(),
        chrome: const MediaChromeSlots.desktop(),
        transition: const MediaTransitionPolicy.desktop(),
        gestures: const MediaGesturePolicy.desktop(),
      );

  /// The family of [platform]: Android and iOS their own, every other
  /// operating system desktop.
  factory MessageMediaPolicy.forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.android => const MessageMediaPolicy.android(),
        TargetPlatform.iOS => const MessageMediaPolicy.ios(),
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux ||
        TargetPlatform.fuchsia => const MessageMediaPolicy.desktop(),
      };

  /// The web's policy: boxes by the window's width class, hover by the
  /// pointer's input class, an instant re-layout; every other part is the
  /// family of [platform], the browser's operating system (by default the
  /// running one).
  ///
  /// The web is neither a phone nor a desktop: one browser runs on a phone,
  /// a tablet and a desktop window resized at will, so its layout follows
  /// the window live and its hover follows each event's pointer, never the
  /// desktop preset. What it replaces in the family's defaults:
  ///
  /// | Part | Web |
  /// | --- | --- |
  /// | [layoutStep] | the family's `MediaLayoutPolicy` with `MediaBoxSizing$Web`: 340 boxes on a compact window, 420 otherwise |
  /// | [linkPreview] | the family's card, fitting its media (`LinkPreviewCardWidth.fitMedia`), so large media takes the web's preview box |
  /// | [gestures] | `MediaGesturePolicy.web` |
  /// | [transition] | none: a resize, or any other change, re-lays out at once |
  ///
  /// A host's view of this policy reports `media` / `webClassChanged`
  /// ([isWeb]). The input to [layout] carries the window: its
  /// `displaySize`, and its `widthClass` read with `ChromeWidthClass.of`.
  factory MessageMediaPolicy.web({TargetPlatform? platform}) {
    final base = MessageMediaPolicy.forPlatform(
      platform ?? defaultTargetPlatform,
    );
    return base.copyWith(
      layoutStep: switch (base.layoutStep) {
        final MediaLayoutPolicy step => step.copyWith(
          box: const MediaBoxSizing.web(),
        ),
        final step => step,
      },
      linkPreview: base.linkPreview.copyWith(
        width: LinkPreviewCardWidth.fitMedia,
      ),
      gestures: const MediaGesturePolicy.web(),
      transition: const MediaTransitionPolicy.none(),
    );
  }

  /// The running app's policy: [MessageMediaPolicy.web] in a browser, else
  /// the family of the operating system.
  factory MessageMediaPolicy.platform() => kIsWeb
      ? MessageMediaPolicy.web()
      : MessageMediaPolicy.forPlatform(defaultTargetPlatform);

  /// The family the defaults came from, named in diagnostics; on the web,
  /// the browser's operating system's.
  final MessageMediaPlatform family;

  /// Whether this policy's boxes follow the window live, as the web's
  /// ([MessageMediaPolicy.web]) do: its layout step sizes them with
  /// `MediaBoxSizing$Web`. Its view then reports a change of the window's
  /// width class or the input class (`media` / `webClassChanged`).
  bool get isWeb => switch (layoutStep) {
    MediaLayoutPolicy(box: MediaBoxSizing$Web()) => true,
    _ => false,
  };

  /// The layout step.
  final MediaLayoutStep layoutStep;

  /// How cells' corners are rounded from their neighbours.
  final MediaCornerPolicy corners;

  /// Which boxes play inline (a host flag).
  final MediaAutoplayPolicy autoplay;

  /// The cell builders, one per shape.
  final MediaCellBuilders cells;

  /// The chrome slots over the cells (time pill rect, info badge, status
  /// control, spoiler, options affordance), each replaceable through
  /// `MediaChromeSlots.copyWith`.
  final MediaChromeSlots chrome;

  /// How a change of the layout animates (`MessageMediaTransition`).
  final MediaTransitionPolicy transition;

  /// How a freshly sent item flies in from its send origin (iOS), or none.
  final MediaSendFlightPolicy sendFlight;

  /// How the media answers taps, the mouse and repeated activations in
  /// normal mode (`MessageMediaView` with a selection facade).
  final MediaGesturePolicy gestures;

  /// The file rows: the layout step lays file stacks out by it and the row
  /// cells draw by it, whichever step the policy holds.
  final MediaFileStackPolicy fileStack;

  /// The link preview card: the layout step lays the card out by it and
  /// the card draws by it, whichever step the policy holds.
  final LinkPreviewCardPolicy linkPreview;

  /// Lays [input] out with [layoutStep], resolves each cell's corner radii
  /// with [corners] and reports the time pill's rect ([chrome]'s
  /// placement) when the time sits on the media.
  MediaLayout layout(MediaLayoutInput input) {
    if (!ChatDiagnostics.current.isEnabled(ChatEventLevel.trace)) {
      return _layout(input);
    }
    final stopwatch = Stopwatch()..start();
    final result = _layout(input);
    stopwatch.stop();
    ChatDiagnostics.current.emit(
      ChatEventLevel.trace,
      ChatEventCategory.media,
      MediaOp.layoutComputed,
      correlation: ChatCorrelation(
        chatId: input.correlation.chatId,
        scrollId: input.correlation.scrollId,
        clientMessageId: input.correlation.clientMessageId,
      ),
      fields: () => {
        'platform': family,
        'items': input.items.length,
        'blocks': ChatEvent.clip(
          result.blocks.map((block) => block.kindName).join(','),
        ),
        'availableWidth': input.availableWidth,
        'mosaicAlgorithm': switch (layoutStep) {
          MediaLayoutPolicy(:final mosaicAlgorithm) => ChatEvent.clip(
            mosaicAlgorithm.name,
          ),
          _ => 'hostStep',
        },
        'durationUs': stopwatch.elapsedMicroseconds,
      },
    );
    return result;
  }

  MediaLayout _layout(MediaLayoutInput input) {
    MediaTrace.begin(MediaTrace.layout);
    final laid = corners.resolve(
      layoutStep.layout(input, fileStack: fileStack, linkPreview: linkPreview),
      input,
    );
    final result = laid.withTimePill(chrome.timePill.of(laid, input));
    MediaTrace.end(MediaTrace.layout);
    return result;
  }

  /// A copy with the given parts replaced.
  MessageMediaPolicy copyWith({
    MessageMediaPlatform? family,
    MediaLayoutStep? layoutStep,
    MediaCornerPolicy? corners,
    MediaAutoplayPolicy? autoplay,
    MediaCellBuilders? cells,
    MediaChromeSlots? chrome,
    MediaFileStackPolicy? fileStack,
    LinkPreviewCardPolicy? linkPreview,
    MediaTransitionPolicy? transition,
    MediaSendFlightPolicy? sendFlight,
    MediaGesturePolicy? gestures,
  }) => MessageMediaPolicy(
    family: family ?? this.family,
    layoutStep: layoutStep ?? this.layoutStep,
    corners: corners ?? this.corners,
    autoplay: autoplay ?? this.autoplay,
    cells: cells ?? this.cells,
    chrome: chrome ?? this.chrome,
    fileStack: fileStack ?? this.fileStack,
    linkPreview: linkPreview ?? this.linkPreview,
    transition: transition ?? this.transition,
    sendFlight: sendFlight ?? this.sendFlight,
    gestures: gestures ?? this.gestures,
  );
}
