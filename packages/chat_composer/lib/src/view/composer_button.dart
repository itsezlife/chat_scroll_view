import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chat_composer/src/view/composer_primary_style.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A square hit target with one chrome icon: the face of every composer
/// action and of the header's dismiss control.
///
/// It never takes focus from the field on a pointer tap, so pressing it
/// leaves the caret and the keyboard where they were, and it is part of the
/// field's tap region, so a desktop field (which lets go of its focus on a
/// mouse press outside that region) keeps it too; keyboard users reach it
/// through traversal and activate it with Enter or Space. A [primary] button
/// is drawn in its [primaryStyle]: a filled disc, or the bare accent glyph.
class ComposerButton extends StatefulWidget {
  /// A button showing [icon], announced as [semanticLabel].
  const ComposerButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.enabled = true,
    this.primary = false,
    this.active = false,
    this.primaryStyle = ComposerPrimaryStyle.disc,
    this.discDiameter = ComposerMetrics.primaryDiscDiameter,
    this.fill,
    this.onFill,
    this.iconSize = ComposerMetrics.actionIconSize,
    this.width = ComposerMetrics.actionSize,
    this.height = ComposerMetrics.actionSize,
    super.key,
  });

  /// The semantic icon.
  final ChromeIconId icon;

  /// What assistive technology announces.
  final String semanticLabel;

  /// Called on tap, click or keyboard activation; ignored when not
  /// [enabled].
  final VoidCallback? onTap;

  /// Whether the button reacts; a disabled one is dimmed.
  final bool enabled;

  /// Whether the button is drawn emphasised, in [primaryStyle].
  final bool primary;

  /// How a [primary] button is drawn.
  final ComposerPrimaryStyle primaryStyle;

  /// Diameter of the disc behind a [primary] glyph in the disc style.
  final double discDiameter;

  /// Disc colour of a [primary] disc, in place of the send colour. A button
  /// given one is not dimmed when it cannot act: the host draws that state
  /// itself.
  final Color? fill;

  /// Glyph colour on [fill], in place of the on-send colour.
  final Color? onFill;

  /// Whether the button is in its active state: the glyph takes the accent
  /// colour and the button is announced as selected. A [primary] button
  /// already is the accent.
  final bool active;

  /// Size of the glyph.
  final double iconSize;

  /// Hit target width.
  final double width;

  /// Hit target height.
  final double height;

  @override
  State<ComposerButton> createState() => _ComposerButtonState();
}

class _ComposerButtonState extends State<ComposerButton> {
  static const _activate = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  static const double _disabledOpacity = 0.4;

  var _focusHighlight = false;
  var _hovered = false;

  bool get _active => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.actionOf(context);
    final own = widget.fill != null;
    final dim = _active || own ? 1.0 : _disabledOpacity;
    // A mouse over a button that would act turns its glyph to the hover
    // colour, as the reference client's does; the accent of an active button
    // and the send disc keep their own.
    final disc =
        widget.primary && widget.primaryStyle == ComposerPrimaryStyle.disc;
    final base = switch ((widget.primary, widget.active)) {
      (true, _) => disc ? widget.onFill ?? tokens.onSend : tokens.send,
      (false, true) => tokens.send,
      (false, false) => _active && _hovered ? tokens.iconHover : tokens.icon,
    };
    final glyph = base.withValues(alpha: base.a * dim);
    final face = Stack(
      alignment: Alignment.center,
      children: [
        if (disc)
          Container(
            width: widget.discDiameter,
            height: widget.discDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (widget.fill ?? tokens.send).withValues(
                alpha: (widget.fill ?? tokens.send).a * dim,
              ),
            ),
          )
        else if (_focusHighlight)
          Container(
            width: ComposerMetrics.primaryDiscDiameter,
            height: ComposerMetrics.primaryDiscDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.floatingSelectedFill,
            ),
          ),
        AnimatedChromeIcon(widget.icon, size: widget.iconSize, color: glyph),
      ],
    );
    return Semantics(
      container: true,
      button: true,
      focusable: _active,
      enabled: _active,
      // Null, not false: an inactive button is not a selectable one.
      selected: widget.active ? true : null,
      label: widget.semanticLabel,
      onTap: _active ? widget.onTap : null,
      excludeSemantics: true,
      // Inside the semantics, so the button's own node stays its root.
      child: TextFieldTapRegion(
        child: FocusableActionDetector(
          enabled: _active,
          mouseCursor: _active ? SystemMouseCursors.click : MouseCursor.defer,
          shortcuts: _activate,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap?.call();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (show) =>
              setState(() => _focusHighlight = show),
          // A region of its own, not the detector's hover highlight: that one
          // is reported only while the framework's highlight mode is the
          // traditional one, which a touch-first platform with a mouse
          // attached has not entered.
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: ScalePressable(
              onPressed: _active ? widget.onTap : null,
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: face,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
