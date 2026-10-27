import 'package:chat_scroll_view/src/chat_scroll/chat_selection_policy.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_metrics.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Host-facing knobs for markdown text-selection edge autoscroll.
///
/// The chat viewport owns the writer, subject-flush gate, policy velocity,
/// and markdown [targetResolver]. Hosts only override whether scrolling is
/// on, the absolute speed cap, and the soft arm band — not the raw markdown
/// autoscroll config (host-union / MediaQuery / resolver seams stay internal).
@immutable
final class ChatMarkdownAutoscrollOptions {
  /// Creates host overrides for edge autoscroll.
  ///
  /// Null [maxVelocity] / [edgeZone] keep the policy defaults from
  /// [ChatMarkdownAutoscroll.config].
  const ChatMarkdownAutoscrollOptions({
    this.enabled = true,
    this.maxVelocity,
    this.edgeZone,
  }) : assert(
         maxVelocity == null || maxVelocity > 0,
         'maxVelocity must be positive when set',
       ),
       assert(
         edgeZone == null || edgeZone > 0,
         'edgeZone must be positive when set',
       );

  /// Disables edge autoscroll entirely.
  static const ChatMarkdownAutoscrollOptions disabled =
      ChatMarkdownAutoscrollOptions(enabled: false);

  /// When false, the markdown scope does not edge-scroll.
  final bool enabled;

  /// Absolute max velocity (logical px/s). Null → policy default.
  final double? maxVelocity;

  /// Soft arm band depth (logical px). Null → policy default.
  final double? edgeZone;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMarkdownAutoscrollOptions &&
          enabled == other.enabled &&
          maxVelocity == other.maxVelocity &&
          edgeZone == other.edgeZone;

  @override
  int get hashCode => Object.hash(enabled, maxVelocity, edgeZone);
}

/// Chat viewport adapter for markdown selection edge autoscroll.
///
/// Owns the seam between [MarkdownSelectionScope.autoscroll] and
/// [RenderChatScrollView]: builds the scope config, resolves the target once
/// per drag, and applies screen-space deltas through the anchor writer.
///
/// Host-union gating stays off — markdown bodies *are* the scrolling content
/// and the viewport builds only what is visible.
///
/// ### Defaults
///
/// | Policy | Cap | Edge band |
/// | --- | --- | --- |
/// | [$Mobile] | half-line × Hz | [ChatSelectionMetrics.textAutoScrollEdgeZoneMobile] |
/// | [$Desktop] | fixed ~15ms product | [ChatSelectionMetrics.textAutoScrollEdgeZoneDesktop] |
@immutable
final class ChatMarkdownAutoscroll implements MarkdownAutoscrollTarget {
  /// Binds this target to [viewportRender].
  const ChatMarkdownAutoscroll(this.viewportRender);

  /// The chat viewport this target drives.
  final RenderChatScrollView viewportRender;

  /// Builds the markdown scope config from [options] + selection [policy].
  ///
  /// Always installs [resolve] as the target resolver — hosts must not supply
  /// a foreign writer. Prefer [ChatMarkdownAutoscrollOptions] on
  /// [ChatMarkdownBody.autoscroll] over calling this directly.
  static MarkdownSelectionAutoscrollConfig config({
    ChatMarkdownAutoscrollOptions options =
        const ChatMarkdownAutoscrollOptions(),
    ChatSelectionPolicy? policy,
    double? displayRefreshHz,
  }) {
    if (!options.enabled) {
      return MarkdownSelectionAutoscrollConfig.disabled;
    }
    final effectivePolicy = policy ?? ChatSelectionPolicy.forPlatform();
    final hz = displayRefreshHz ?? readDisplayRefreshHz();
    final velocity =
        options.maxVelocity ??
        resolveMaxVelocity(effectivePolicy, displayRefreshHz: hz);
    final edge = options.edgeZone ?? resolveEdgeZone(effectivePolicy);
    assert(velocity > 0, 'maxVelocity must be positive');
    assert(edge > 0, 'edgeZone must be positive');
    return MarkdownSelectionAutoscrollConfig(
      edgeZone: edge,
      maxVelocity: velocity,
      useMediaQueryPadding: false,
      useHostUnionGate: false,
      targetResolver: resolve,
    );
  }

  /// Soft arm band for [policy].
  @visibleForTesting
  static double resolveEdgeZone(ChatSelectionPolicy policy) => switch (policy) {
    ChatSelectionPolicy$Mobile() =>
      ChatSelectionMetrics.textAutoScrollEdgeZoneMobile,
    ChatSelectionPolicy$Desktop() =>
      ChatSelectionMetrics.textAutoScrollEdgeZoneDesktop,
  };

  /// Absolute max velocity (logical px/s) for [policy].
  @visibleForTesting
  static double resolveMaxVelocity(
    ChatSelectionPolicy policy, {
    required double displayRefreshHz,
  }) {
    assert(displayRefreshHz > 0, 'displayRefreshHz must be positive');
    return switch (policy) {
      ChatSelectionPolicy$Mobile() =>
        ChatSelectionMetrics.textAutoScrollPixelsPerFrame * displayRefreshHz,
      ChatSelectionPolicy$Desktop() =>
        ChatSelectionMetrics.textAutoScrollDesktopMaxVelocity,
    };
  }

  /// Hz of the first attached display, or 60 when none is reported.
  static double readDisplayRefreshHz() {
    for (final view in SchedulerBinding.instance.platformDispatcher.views) {
      final hz = view.display.refreshRate;
      if (hz > 1) return hz;
    }
    return 60;
  }

  /// Resolves the enclosing [RenderChatScrollView], or null when not mounted.
  static MarkdownAutoscrollTarget? resolve(MarkdownAutoscrollRequest request) {
    final ctx = request.contentContext ?? request.scopeContext;
    final viewport = findViewport(ctx);
    if (viewport == null) return null;
    return ChatMarkdownAutoscroll(viewport);
  }

  /// Walks ancestors of [context] for the enclosing chat viewport.
  @visibleForTesting
  static RenderChatScrollView? findViewport(BuildContext context) {
    for (
      var node = context.findRenderObject();
      node != null;
      node = node.parent
    ) {
      if (node is RenderChatScrollView) return node;
    }
    return null;
  }

  @override
  MarkdownAutoscrollViewport? get viewport {
    final bounds = viewportRender.markdownAutoscrollGlobalBounds;
    if (bounds == null) return null;
    return MarkdownAutoscrollViewport(
      globalBounds: bounds,
      padding: viewportRender.markdownAutoscrollPadding,
    );
  }

  @override
  bool canScroll({required bool forward}) {
    // forward = positive screen delta = toward newer = span direction -1.
    final direction = forward ? -1 : 1;
    return viewportRender.canMarkdownEdgeAutoscroll(direction);
  }

  @override
  double applyScrollDelta(double delta) =>
      viewportRender.applyMarkdownAutoscrollDelta(delta);
}
