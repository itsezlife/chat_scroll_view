import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:message_media/src/chrome/media_chrome_slots.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/diagnostics/media_trace.dart';
import 'package:message_media/src/gesture/media_gesture_policy.dart';
import 'package:message_media/src/gesture/media_semantics_strings.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/paint/media_cell_builders.dart';
import 'package:message_media/src/policy/link_preview_card_policy.dart';
import 'package:message_media/src/policy/media_autoplay_policy.dart';
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
/// [MessageMediaPolicy.ios], [MessageMediaPolicy.desktop], or the running
/// app's with [MessageMediaPolicy.platform]. A host changes one part with
/// [copyWith]: the layout step as a whole ([layoutStep]) or one of the
/// default step's parts through [MediaLayoutPolicy.copyWith], the corner
/// values ([corners]), the autoplay flag ([autoplay]), or one cell builder
/// ([cells], `MediaCellBuilders.copyWith`) leaving the other, or the
/// layout transition's timings ([transition]).
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
    this.cells = const MediaCellBuilders(),
    this.transition = const MediaTransitionPolicy.none(),
    this.gestures = const MediaGesturePolicy(),
    this.semantics = MediaSemanticsStrings.english,
  });

  /// The Android family's defaults.
  const MessageMediaPolicy.android()
    : this(
        family: MessageMediaPlatform.android,
        layoutStep: const MediaLayoutPolicy.android(),
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
        corners: const MediaCornerPolicy.ios(),
        autoplay: const MediaAutoplayPolicy.ios(),
        chrome: const MediaChromeSlots.ios(),
        transition: const MediaTransitionPolicy.ios(),
        gestures: const MediaGesturePolicy.ios(),
      );

  /// The desktop family's defaults.
  const MessageMediaPolicy.desktop()
    : this(
        family: MessageMediaPlatform.desktop,
        layoutStep: const MediaLayoutPolicy.desktop(),
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

  /// The running app's family.
  ///
  /// On the web this is the browser's operating system's family for now:
  /// the web's own box sizes by width class are not laid out yet, and a
  /// phone's browser is not a desktop.
  factory MessageMediaPolicy.platform() =>
      MessageMediaPolicy.forPlatform(defaultTargetPlatform);

  /// The family the defaults came from, named in diagnostics.
  final MessageMediaPlatform family;

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

  /// How the media answers taps, the mouse and repeated activations in
  /// normal mode (`MessageMediaView` with a selection facade).
  final MediaGesturePolicy gestures;

  /// What a screen reader hears for each item.
  final MediaSemanticsStrings semantics;

  /// The file rows' policy the row cells draw by: the default layout
  /// step's, or the family's own under a host's step.
  MediaFileStackPolicy get fileStack => switch (layoutStep) {
    MediaLayoutPolicy(:final fileStack) => fileStack,
    _ => switch (family) {
      MessageMediaPlatform.android => const MediaFileStackPolicy.android(),
      MessageMediaPlatform.ios => const MediaFileStackPolicy.ios(),
      MessageMediaPlatform.desktop => const MediaFileStackPolicy.desktop(),
    },
  };

  /// The link preview card's policy the card draws by: the default layout
  /// step's, or the family's own under a host's step.
  LinkPreviewCardPolicy get linkPreview => switch (layoutStep) {
    MediaLayoutPolicy(:final card) => card,
    _ => switch (family) {
      MessageMediaPlatform.android => const LinkPreviewCardPolicy.android(),
      MessageMediaPlatform.ios => const LinkPreviewCardPolicy.ios(),
      MessageMediaPlatform.desktop => const LinkPreviewCardPolicy.desktop(),
    },
  };

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
    final laid = corners.resolve(layoutStep.layout(input), input);
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
    MediaTransitionPolicy? transition,
    MediaGesturePolicy? gestures,
    MediaSemanticsStrings? semantics,
  }) => MessageMediaPolicy(
    family: family ?? this.family,
    layoutStep: layoutStep ?? this.layoutStep,
    corners: corners ?? this.corners,
    autoplay: autoplay ?? this.autoplay,
    cells: cells ?? this.cells,
    chrome: chrome ?? this.chrome,
    transition: transition ?? this.transition,
    gestures: gestures ?? this.gestures,
    semantics: semantics ?? this.semantics,
  );
}
