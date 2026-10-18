import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_data.dart';
import 'package:chrome_foundation/src/tokens/action_tokens.dart';
import 'package:chrome_foundation/src/tokens/composer_tokens.dart';
import 'package:chrome_foundation/src/tokens/glass_material_tokens.dart';
import 'package:chrome_foundation/src/tokens/panel_tokens.dart';
import 'package:chrome_foundation/src/tokens/placeholder_tokens.dart';
import 'package:chrome_foundation/src/tokens/selection_menu_tokens.dart';
import 'package:chrome_foundation/src/tokens/spoiler_tokens.dart';
import 'package:flutter/widgets.dart';

/// The parts of a chrome theme a dependent can subscribe to.
///
/// A widget that reads only the composer group is rebuilt only when the
/// composer group changes.
enum ChromeThemeAspect {
  /// The semantic [ChromePalette].
  palette,

  /// [ComposerTokens].
  composer,

  /// [PanelTokens].
  panel,

  /// [ActionTokens].
  action,

  /// [PlaceholderTokens].
  placeholder,

  /// [GlassMaterialTokens].
  glass,

  /// [SelectionMenuTokens].
  selectionMenu,

  /// [SpoilerTokens].
  spoiler,
}

/// The **chrome theme scope**: provides the palette and token groups to the
/// subtree. Required: every lookup fails when no scope supplies the group, so
/// there is no silent light fallback.
///
/// A scope supplies any subset of the palette and the token groups.
///
/// - Supplying a [palette] also supplies every group: each one the scope does
///   not pass explicitly is derived from that palette.
/// - Supplying only groups supplies just those; the others resolve through
///   the nearest ancestor scope that supplies them.
///
/// Nesting therefore overrides exactly what the inner scope names: a per-chat
/// scope passing only [composer] leaves panel, action, placeholder and glass
/// to the app-level scope. An inner scope with a [palette] starts over for
/// every group it does not name.
///
/// Independent of `ThemeData`; [ChromePalette.fromColorScheme] is the optional
/// bridge. To animate between two themes use [AnimatedChromeThemeScope].
class ChromeThemeScope extends InheritedModel<ChromeThemeAspect> {
  /// A scope supplying [palette] and/or individual token groups.
  ChromeThemeScope({
    required super.child,
    ChromePalette? palette,
    ComposerTokens? composer,
    PanelTokens? panel,
    ActionTokens? action,
    PlaceholderTokens? placeholder,
    GlassMaterialTokens? glass,
    SelectionMenuTokens? selectionMenu,
    SpoilerTokens? spoiler,
    super.key,
  }) : _palette = palette,
       _composer =
           composer ??
           switch (palette) {
             final palette? => ComposerTokens.fromPalette(palette),
             null => null,
           },
       _panel =
           panel ??
           switch (palette) {
             final palette? => PanelTokens.fromPalette(palette),
             null => null,
           },
       _action =
           action ??
           switch (palette) {
             final palette? => ActionTokens.fromPalette(palette),
             null => null,
           },
       _placeholder =
           placeholder ??
           switch (palette) {
             final palette? => PlaceholderTokens.fromPalette(palette),
             null => null,
           },
       _glass =
           glass ??
           switch (palette) {
             final palette? => GlassMaterialTokens.fromPalette(palette),
             null => null,
           },
       _selectionMenu =
           selectionMenu ??
           switch (palette) {
             final palette? => SelectionMenuTokens.fromPalette(palette),
             null => null,
           },
       _spoiler =
           spoiler ??
           switch (palette) {
             final palette? => SpoilerTokens.fromPalette(palette),
             null => null,
           };

  /// A scope supplying every part of [data] verbatim.
  ChromeThemeScope.data({
    required ChromeThemeData data,
    required Widget child,
    Key? key,
  }) : this(
         palette: data.palette,
         composer: data.composer,
         panel: data.panel,
         action: data.action,
         placeholder: data.placeholder,
         glass: data.glass,
         selectionMenu: data.selectionMenu,
         spoiler: data.spoiler,
         key: key,
         child: child,
       );

  final ChromePalette? _palette;
  final ComposerTokens? _composer;
  final PanelTokens? _panel;
  final ActionTokens? _action;
  final PlaceholderTokens? _placeholder;
  final GlassMaterialTokens? _glass;
  final SelectionMenuTokens? _selectionMenu;
  final SpoilerTokens? _spoiler;

  Object? _part(ChromeThemeAspect aspect) => switch (aspect) {
    ChromeThemeAspect.palette => _palette,
    ChromeThemeAspect.composer => _composer,
    ChromeThemeAspect.panel => _panel,
    ChromeThemeAspect.action => _action,
    ChromeThemeAspect.placeholder => _placeholder,
    ChromeThemeAspect.glass => _glass,
    ChromeThemeAspect.selectionMenu => _selectionMenu,
    ChromeThemeAspect.spoiler => _spoiler,
  };

  /// The whole theme at [context]; depends on every part.
  ///
  /// Throws a [FlutterError] in debug builds when a part has no supplier.
  static ChromeThemeData of(BuildContext context) => ChromeThemeData(
    palette: paletteOf(context),
    composer: composerOf(context),
    panel: panelOf(context),
    action: actionOf(context),
    placeholder: placeholderOf(context),
    glass: glassOf(context),
    selectionMenu: selectionMenuOf(context),
    spoiler: spoilerOf(context),
  );

  /// The semantic palette at [context].
  ///
  /// Throws a [FlutterError] in debug builds when no scope supplies a
  /// palette, as do the other lookups for their group.
  static ChromePalette paletteOf(BuildContext context) =>
      _lookup(context, ChromeThemeAspect.palette)._palette!;

  /// The composer tokens at [context].
  static ComposerTokens composerOf(BuildContext context) =>
      _lookup(context, ChromeThemeAspect.composer)._composer!;

  /// The panel tokens at [context].
  static PanelTokens panelOf(BuildContext context) =>
      _lookup(context, ChromeThemeAspect.panel)._panel!;

  /// The action tokens at [context].
  static ActionTokens actionOf(BuildContext context) =>
      _lookup(context, ChromeThemeAspect.action)._action!;

  /// The placeholder tokens at [context].
  static PlaceholderTokens placeholderOf(BuildContext context) =>
      _lookup(context, ChromeThemeAspect.placeholder)._placeholder!;

  /// The glass material tokens at [context].
  static GlassMaterialTokens glassOf(BuildContext context) =>
      _lookup(context, ChromeThemeAspect.glass)._glass!;

  /// The selection menu tokens at [context].
  static SelectionMenuTokens selectionMenuOf(BuildContext context) =>
      _lookup(context, ChromeThemeAspect.selectionMenu)._selectionMenu!;

  /// The spoiler tokens at [context].
  static SpoilerTokens spoilerOf(BuildContext context) =>
      _lookup(context, ChromeThemeAspect.spoiler)._spoiler!;

  static ChromeThemeScope _lookup(
    BuildContext context,
    ChromeThemeAspect aspect,
  ) {
    // With no supplier, inheritFrom still returns the outermost scope, so a
    // missing part is detected by the part itself, not by a null scope.
    final scope = InheritedModel.inheritFrom<ChromeThemeScope>(
      context,
      aspect: aspect,
    );
    assert(() {
      if (scope == null || scope._part(aspect) == null) {
        throw FlutterError.fromParts([
          ErrorSummary(
            'No ChromeThemeScope supplies ${aspect.name} above this context.',
          ),
          ErrorDescription(
            'Chrome widgets require a ChromeThemeScope; there is no default '
            'theme.',
          ),
          ErrorHint(
            'Wrap the chrome in a ChromeThemeScope that supplies a palette, '
            'or supplies ${aspect.name} explicitly.',
          ),
          context.describeElement('The context used was'),
        ]);
      }
      return true;
    }(), 'No ChromeThemeScope supplies ${aspect.name}.');
    return scope!;
  }

  @override
  bool isSupportedAspect(Object aspect) => switch (aspect) {
    final ChromeThemeAspect known => _part(known) != null,
    _ => false,
  };

  @override
  bool updateShouldNotify(ChromeThemeScope oldWidget) => ChromeThemeAspect
      .values
      .any((aspect) => _part(aspect) != oldWidget._part(aspect));

  @override
  bool updateShouldNotifyDependent(
    ChromeThemeScope oldWidget,
    Set<ChromeThemeAspect> dependencies,
  ) => dependencies.any((aspect) => _part(aspect) != oldWidget._part(aspect));
}

/// A [ChromeThemeScope] that animates to new tokens instead of jumping.
///
/// Takes the same parts as [ChromeThemeScope]. Each part that is supplied is
/// interpolated with its own `lerp` whenever the target changes. A part that
/// goes from supplied to absent (or the reverse) switches at once, since
/// there is nothing to interpolate towards.
///
/// Timing defaults to the `themeSwitch` motion role; an explicit [duration] or
/// [curve] replaces the role's. The enclosing `ChromeMotionScope` speed scales
/// either duration, so reduce-motion makes the switch instant.
class AnimatedChromeThemeScope extends StatelessWidget {
  /// An animated scope supplying [palette] and/or individual token groups.
  const AnimatedChromeThemeScope({
    required this.child,
    this.palette,
    this.composer,
    this.panel,
    this.action,
    this.placeholder,
    this.glass,
    this.selectionMenu,
    this.spoiler,
    this.duration,
    this.curve,
    this.onEnd,
    super.key,
  });

  /// The target palette; see [ChromeThemeScope.new].
  final ChromePalette? palette;

  /// The target composer tokens.
  final ComposerTokens? composer;

  /// The target panel tokens.
  final PanelTokens? panel;

  /// The target action tokens.
  final ActionTokens? action;

  /// The target placeholder tokens.
  final PlaceholderTokens? placeholder;

  /// The target glass material tokens.
  final GlassMaterialTokens? glass;

  /// The target selection menu tokens.
  final SelectionMenuTokens? selectionMenu;

  /// The target spoiler tokens.
  final SpoilerTokens? spoiler;

  /// How long a change takes at normal speed; null uses the `themeSwitch`
  /// role.
  final Duration? duration;

  /// The easing of a change; null uses the `themeSwitch` role.
  final Curve? curve;

  /// Called when an animation to new tokens finishes.
  final VoidCallback? onEnd;

  /// The subtree that sees the animated tokens.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = ChromeMotionScope.of(context);
    final role = motion.motion[MotionRole.themeSwitch];
    return _AnimatedChromeThemeScope(
      palette: palette,
      composer: composer,
      panel: panel,
      action: action,
      placeholder: placeholder,
      glass: glass,
      selectionMenu: selectionMenu,
      spoiler: spoiler,
      duration: motion.speed.scale(duration ?? role.duration),
      curve: curve ?? role.curve,
      onEnd: onEnd,
      child: child,
    );
  }
}

class _AnimatedChromeThemeScope extends ImplicitlyAnimatedWidget {
  const _AnimatedChromeThemeScope({
    required this.child,
    required this.palette,
    required this.composer,
    required this.panel,
    required this.action,
    required this.placeholder,
    required this.glass,
    required this.selectionMenu,
    required this.spoiler,
    required super.duration,
    required super.curve,
    required super.onEnd,
  });

  final ChromePalette? palette;
  final ComposerTokens? composer;
  final PanelTokens? panel;
  final ActionTokens? action;
  final PlaceholderTokens? placeholder;
  final GlassMaterialTokens? glass;
  final SelectionMenuTokens? selectionMenu;
  final SpoilerTokens? spoiler;
  final Widget child;

  @override
  AnimatedWidgetBaseState<_AnimatedChromeThemeScope> createState() =>
      _AnimatedChromeThemeScopeState();
}

class _AnimatedChromeThemeScopeState
    extends AnimatedWidgetBaseState<_AnimatedChromeThemeScope> {
  _PartTween<ChromePalette>? _palette;
  _PartTween<ComposerTokens>? _composer;
  _PartTween<PanelTokens>? _panel;
  _PartTween<ActionTokens>? _action;
  _PartTween<PlaceholderTokens>? _placeholder;
  _PartTween<GlassMaterialTokens>? _glass;
  _PartTween<SelectionMenuTokens>? _selectionMenu;
  _PartTween<SpoilerTokens>? _spoiler;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _palette =
        visitor(
              _palette,
              widget.palette,
              (v) => _PartTween<ChromePalette>(
                ChromePalette.lerp,
                v as ChromePalette,
              ),
            )
            as _PartTween<ChromePalette>?;
    _composer =
        visitor(
              _composer,
              widget.composer,
              (v) => _PartTween<ComposerTokens>(
                ComposerTokens.lerp,
                v as ComposerTokens,
              ),
            )
            as _PartTween<ComposerTokens>?;
    _panel =
        visitor(
              _panel,
              widget.panel,
              (v) =>
                  _PartTween<PanelTokens>(PanelTokens.lerp, v as PanelTokens),
            )
            as _PartTween<PanelTokens>?;
    _action =
        visitor(
              _action,
              widget.action,
              (v) => _PartTween<ActionTokens>(
                ActionTokens.lerp,
                v as ActionTokens,
              ),
            )
            as _PartTween<ActionTokens>?;
    _placeholder =
        visitor(
              _placeholder,
              widget.placeholder,
              (v) => _PartTween<PlaceholderTokens>(
                PlaceholderTokens.lerp,
                v as PlaceholderTokens,
              ),
            )
            as _PartTween<PlaceholderTokens>?;
    _glass =
        visitor(
              _glass,
              widget.glass,
              (v) => _PartTween<GlassMaterialTokens>(
                GlassMaterialTokens.lerp,
                v as GlassMaterialTokens,
              ),
            )
            as _PartTween<GlassMaterialTokens>?;
    _selectionMenu =
        visitor(
              _selectionMenu,
              widget.selectionMenu,
              (v) => _PartTween<SelectionMenuTokens>(
                SelectionMenuTokens.lerp,
                v as SelectionMenuTokens,
              ),
            )
            as _PartTween<SelectionMenuTokens>?;
    _spoiler =
        visitor(
              _spoiler,
              widget.spoiler,
              (v) => _PartTween<SpoilerTokens>(
                SpoilerTokens.lerp,
                v as SpoilerTokens,
              ),
            )
            as _PartTween<SpoilerTokens>?;
  }

  @override
  Widget build(BuildContext context) => ChromeThemeScope(
    palette: _palette?.evaluate(animation),
    composer: _composer?.evaluate(animation),
    panel: _panel?.evaluate(animation),
    action: _action?.evaluate(animation),
    placeholder: _placeholder?.evaluate(animation),
    glass: _glass?.evaluate(animation),
    selectionMenu: _selectionMenu?.evaluate(animation),
    spoiler: _spoiler?.evaluate(animation),
    child: widget.child,
  );
}

/// A tween over an immutable token value with its own `lerp`.
class _PartTween<T extends Object> extends Tween<T> {
  _PartTween(this._lerp, T begin) : super(begin: begin);

  final T Function(T a, T b, double t) _lerp;

  @override
  T lerp(double t) => _lerp(begin as T, end as T, t);
}
