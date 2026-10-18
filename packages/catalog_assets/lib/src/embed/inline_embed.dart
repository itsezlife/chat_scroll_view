import 'dart:ui';

import 'package:listen/listen.dart';
import 'package:meta/meta.dart';

/// What an [InlineEmbed] is painted with besides its rectangle: the colour of
/// the text it sits in and the opacity of the text.
@immutable
final class InlineEmbedPaintContext {
  /// Creates a context; the default is the embed's own colours, fully opaque.
  const InlineEmbedPaintContext({this.tint, this.opacity = 1})
    : assert(opacity >= 0 && opacity <= 1, 'opacity must be within 0..1');

  /// The text colour, for an embed that is tinted by it (a template asset).
  /// Null leaves an embed in its own colours.
  final Color? tint;

  /// Opacity of the whole paint, 0 to 1.
  final double opacity;
}

/// What a body asks an [InlineEmbedResolver] about: the target of an image or
/// link in the text, split the way the markup spells it.
///
/// For `![alt](unicode:1F44D)` the [scheme] is `unicode`, the [id] `1F44D` and
/// the [alt] the text shown where the embed cannot be (and copied, selected
/// and read aloud in its place).
@immutable
final class InlineEmbedTarget {
  /// Creates a target.
  const InlineEmbedTarget({
    required this.scheme,
    required this.id,
    required this.alt,
  });

  /// The scheme of the target, without the colon.
  final String scheme;

  /// Everything after the scheme's colon.
  final String id;

  /// The alternative text of the reference.
  final String alt;

  @override
  bool operator ==(Object other) =>
      other is InlineEmbedTarget &&
      other.scheme == scheme &&
      other.id == id &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(scheme, id, alt);

  @override
  String toString() => 'InlineEmbedTarget($scheme:$id, alt: $alt)';
}

/// What a body knows about the text an embed is set in, so the resolver can
/// size it.
@immutable
final class InlineEmbedMetrics {
  /// Creates metrics for text of [fontSize] logical pixels whose line has
  /// [ascent] above and [descent] below the baseline, at [devicePixelRatio].
  const InlineEmbedMetrics({
    required this.fontSize,
    required this.ascent,
    required this.descent,
    required this.devicePixelRatio,
  }) : assert(
         fontSize > 0 && ascent > 0 && descent > 0 && devicePixelRatio > 0,
         'metrics need a positive font size, ascent, descent and density',
       );

  /// Font size of the text around the embed, logical pixels.
  final double fontSize;

  /// Distance from the baseline up to the top of the line, logical pixels,
  /// positive. With [descent] it sizes an embed the way the reference
  /// client sizes an inline custom emoji (`AssetPresets.inlineMessage`).
  final double ascent;

  /// Distance from the baseline down to the bottom of the line, logical
  /// pixels, positive.
  final double descent;

  /// Pixels per logical pixel of the display the body is shown on.
  final double devicePixelRatio;

  @override
  bool operator ==(Object other) =>
      other is InlineEmbedMetrics &&
      other.fontSize == fontSize &&
      other.ascent == ascent &&
      other.descent == descent &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode => Object.hash(fontSize, ascent, descent, devicePixelRatio);

  @override
  String toString() =>
      'InlineEmbedMetrics($fontSize, ascent: $ascent, descent: $descent, '
      'x$devicePixelRatio)';
}

/// A painter-based thing set inside text: it has a size, paints itself into a
/// rectangle the body gives it, and says when what it paints has changed.
///
/// This is the contract a markdown body lays out and paints; it carries no
/// widget and no asset type. A body asks its [InlineEmbedResolver] for one per
/// reference, reserves [sizeHint] in the text, calls [paint] while painting,
/// repaints when it hears the [Listenable] signal, and calls [dispose] when
/// the text goes away. The alternative text of the reference, not the embed,
/// is what copy, selection and accessibility use.
///
/// ## Contract
///
/// - [sizeHint] is the size the body reserves; it does not change over the
///   embed's life. [paint] may be given a rectangle of another size and
///   scales to it.
/// - The signal (the [Listenable]) means "what [paint] draws is different
///   now"; it carries nothing. It is silent after [dispose], and a listener
///   must not be added after it (`package:listen` asserts); removing one is
///   always allowed.
/// - [paint] draws only inside the rectangle and nothing at all after
///   [dispose]. It is called during painting and does not schedule work.
/// - [visible] is true on creation. A body sets it false for an embed that is
///   scrolled out of view or hidden, so an animated one stops costing ticks.
/// - [dispose] is idempotent and gives back everything the embed holds.
abstract interface class InlineEmbed implements Listenable {
  /// The logical size the body reserves for the embed.
  Size get sizeHint;

  /// Whether the body shows the embed.
  bool get visible;
  set visible(bool value);

  /// Paints the embed into [rect] of [canvas].
  void paint(Canvas canvas, Rect rect, InlineEmbedPaintContext context);

  /// Gives back what the embed holds. Idempotent.
  void dispose();
}

/// Turns a target in text into the [InlineEmbed] that draws it.
///
/// A host registers resolvers by scheme where it sets up a body; the body
/// owns every embed a resolver returns and disposes it.
abstract interface class InlineEmbedResolver {
  /// A new embed for [target] in text of [metrics], or null when this
  /// resolver does not know the target (the body then shows the alternative
  /// text). Each call returns an embed of its own: disposing one never
  /// affects another made for the same target.
  InlineEmbed? resolve(InlineEmbedTarget target, InlineEmbedMetrics metrics);
}
