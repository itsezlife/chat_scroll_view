import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A one-line label whose laid-out text is shared by every label with the
/// same text, style, scale and direction.
///
/// For chrome that repeats on every row (a time, a status glyph): a [Text]
/// builds and lays out a paragraph of its own each time a row is built, and
/// for a short label that costs as much as the message body beside it. The
/// label never wraps or ellipsizes; it is as wide as its text.
class CachedLabel extends LeafRenderObjectWidget {
  /// A label of [text] in [style], merged over the ambient
  /// [DefaultTextStyle] as [Text] does.
  const CachedLabel(this.text, {this.style, super.key});

  /// An [IconData] glyph as a label, laid out like [Icon]: [size] square,
  /// glyph centred, and out of semantics as an [Icon] without a label is.
  static Widget icon(IconData icon, {required double size, Color? color}) =>
      ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: CachedLabel(
              String.fromCharCode(icon.codePoint),
              style: TextStyle(
                inherit: false,
                color: color,
                fontSize: size,
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                fontFamilyFallback: icon.fontFamilyFallback,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ),
      );

  /// The shared, laid-out painter for [text] in [style], for a render object
  /// that paints a label of its own. Do not dispose it.
  static TextPainter painterFor(
    String text,
    TextStyle style, {
    required TextScaler scaler,
    required TextDirection direction,
  }) => _LabelCache.painter(
    text: text,
    style: style,
    scaler: scaler,
    direction: direction,
  );

  /// The label.
  final String text;

  /// Merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  TextPainter _painter(BuildContext context) {
    final ambient = DefaultTextStyle.of(context).style;
    return _LabelCache.painter(
      text: text,
      style: switch (style) {
        final own? when !own.inherit => own,
        _ => ambient.merge(style),
      },
      scaler: MediaQuery.textScalerOf(context),
      direction: Directionality.of(context),
    );
  }

  @override
  RenderCachedLabel createRenderObject(BuildContext context) =>
      RenderCachedLabel(text: text, painter: _painter(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCachedLabel renderObject,
  ) {
    renderObject
      ..text = text
      ..painter = _painter(context);
  }
}

/// Render object of [CachedLabel]: paints a shared, laid-out [TextPainter].
class RenderCachedLabel extends RenderBox {
  /// A label painting [painter], announced as [text].
  RenderCachedLabel({required String text, required TextPainter painter})
    : _text = text,
      _painter = painter;

  String _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    markNeedsSemanticsUpdate();
  }

  TextPainter _painter;
  set painter(TextPainter value) {
    if (identical(value, _painter)) return;
    final resized = value.size != _painter.size;
    _painter = value;
    if (resized) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(_painter.size);

  @override
  void performLayout() => size = computeDryLayout(constraints);

  @override
  double computeMinIntrinsicWidth(double height) => _painter.width;

  @override
  double computeMaxIntrinsicWidth(double height) => _painter.width;

  @override
  double computeMinIntrinsicHeight(double width) => _painter.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _painter.height;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _painter.computeDistanceToActualBaseline(baseline);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) =>
      _painter.paint(context.canvas, offset);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = _painter.textDirection;
  }
}

/// Laid-out painters by label, least recently used evicted past [_capacity].
///
/// An evicted painter is dropped, not disposed: a label still on screen may
/// paint it until its next update.
abstract final class _LabelCache {
  static const int _capacity = 256;
  static final _painters = <_LabelKey, TextPainter>{};

  static TextPainter painter({
    required String text,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
  }) {
    final key = _LabelKey(text, style, scaler, direction);
    final hit = _painters.remove(key);
    if (hit != null) return _painters[key] = hit;
    if (_painters.length >= _capacity) _painters.remove(_painters.keys.first);
    return _painters[key] = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
  }
}

@immutable
class _LabelKey {
  const _LabelKey(this.text, this.style, this.scaler, this.direction);

  final String text;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;

  @override
  bool operator ==(Object other) =>
      other is _LabelKey &&
      other.text == text &&
      other.style == style &&
      other.scaler == scaler &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(text, style, scaler, direction);
}
