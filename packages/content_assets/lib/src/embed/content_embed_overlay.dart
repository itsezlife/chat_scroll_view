import 'package:content_assets/src/embed/content_embed.dart';
import 'package:flutter/material.dart';
import 'package:mpx_core/mpx_core.dart';

/// The status control and the media badge over a [ContentEmbed], for a body
/// that paints the embed on its canvas and so has no widget of its own to
/// lay them on: the host stacks this over the rectangle the embed is drawn
/// in, the size of that rectangle.
///
/// It is what `ContentView` lays over its content, read from the embed's
/// binding ([ContentEmbed.binding]): with [MediaStatusMode.control], cancel
/// and an arc while the content downloads, download while it waits for the
/// user or failed (a tap downloads or cancels), and nothing once it shows
/// unless `playAction` offers play ([onPlay]); a bare arc with
/// [MediaStatusMode.arc]; the compact control in the style's corner with
/// [MediaStatusMode.compact]. The badge ([badge]) is the duration or "GIF"
/// at the style's offset, with the size while it downloads.
///
/// Geometry, motion and colours are the loading style's
/// (`MediaLoadingStyleScope`); [statusBuilder] replaces the control, else the
/// closest scope's builder does. Streamable video that is not local shows the
/// control as any other content: a surface that streams video is a
/// `ContentView`.
///
/// It owns nothing: the embed stays the body's to dispose, and the overlay
/// is built again for an embed that replaces it.
class ContentEmbedOverlay extends StatelessWidget {
  /// Lays the controls of [embed] over its rectangle.
  const ContentEmbedOverlay({
    required this.embed,
    this.status = const MediaStatusMode.control(),
    this.badge = true,
    this.onPlay,
    this.statusBuilder,
    super.key,
  });

  /// The embed whose download and content the controls show.
  final ContentEmbed embed;

  /// Which status control shows.
  final MediaStatusMode status;

  /// Whether the media badge shows at the top-left.
  final bool badge;

  /// Called on a tap on play, when [status] offers it.
  final VoidCallback? onPlay;

  /// Builds the status control in place of the default one, or null for the
  /// closest `MediaLoadingStyleScope`'s builder, else the default.
  final MediaStatusBuilder? statusBuilder;

  @override
  Widget build(BuildContext context) {
    final style = MediaLoadingStyleScope.resolve(context);
    final binding = embed.binding;
    final builder =
        statusBuilder ?? MediaLoadingStyleScope.statusBuilderOf(context);
    Widget built(MediaStatusControl control) =>
        builder == null ? control : builder(context, control);
    // The control keeps its style's size whatever the box: never stretched
    // over large media, free to overflow small media.
    Widget centred(MediaStatusControl control) => Positioned.fill(
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: built(control),
      ),
    );
    final corner = style.status.compactOffset;
    final offset = style.badge.offset;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          ...switch (status) {
            MediaStatusMode$None() => const <Widget>[],
            MediaStatusMode$Arc(:final radius) => [
              centred(
                MediaStatusControl.binding(
                  binding,
                  arcOnly: true,
                  diameter: 2 * radius,
                ),
              ),
            ],
            MediaStatusMode$Control(:final playAction) => [
              centred(
                MediaStatusControl.binding(
                  binding,
                  playAction: playAction,
                  onPlay: onPlay,
                ),
              ),
            ],
            MediaStatusMode$Compact() => [
              Positioned(
                left: corner.dx,
                top: corner.dy,
                child: built(
                  MediaStatusControl.binding(binding, compact: true),
                ),
              ),
            ],
          },
          if (badge)
            Positioned(
              left: offset.dx,
              top: offset.dy,
              child: MediaBadge.binding(binding, width: constraints.maxWidth),
            ),
        ],
      ),
    );
  }
}
