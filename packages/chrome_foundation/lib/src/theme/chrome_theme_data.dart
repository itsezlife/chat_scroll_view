import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:chrome_foundation/src/tokens/action_tokens.dart';
import 'package:chrome_foundation/src/tokens/composer_tokens.dart';
import 'package:chrome_foundation/src/tokens/glass_material_tokens.dart';
import 'package:chrome_foundation/src/tokens/panel_tokens.dart';
import 'package:chrome_foundation/src/tokens/placeholder_tokens.dart';
import 'package:chrome_foundation/src/tokens/pointer_menu_tokens.dart';
import 'package:chrome_foundation/src/tokens/selection_menu_tokens.dart';
import 'package:chrome_foundation/src/tokens/spoiler_tokens.dart';
import 'package:meta/meta.dart';

/// A complete chrome theme: one [ChromePalette] and one value of every **token
/// group**.
///
/// This is the bundle a root `ChromeThemeScope` carries and what two themes
/// are interpolated between; components read the group they need from the
/// scope, not this bundle.
@immutable
final class ChromeThemeData {
  /// A theme with every part given.
  const ChromeThemeData({
    required this.palette,
    required this.composer,
    required this.panel,
    required this.action,
    required this.placeholder,
    required this.glass,
    required this.selectionMenu,
    required this.pointerMenu,
    required this.spoiler,
  });

  /// The theme where each group is derived from [palette], except those the
  /// host supplies.
  factory ChromeThemeData.fromPalette(
    ChromePalette palette, {
    ComposerTokens? composer,
    PanelTokens? panel,
    ActionTokens? action,
    PlaceholderTokens? placeholder,
    GlassMaterialTokens? glass,
    SelectionMenuTokens? selectionMenu,
    PointerMenuTokens? pointerMenu,
    SpoilerTokens? spoiler,
  }) => ChromeThemeData(
    palette: palette,
    composer: composer ?? ComposerTokens.fromPalette(palette),
    panel: panel ?? PanelTokens.fromPalette(palette),
    action: action ?? ActionTokens.fromPalette(palette),
    placeholder: placeholder ?? PlaceholderTokens.fromPalette(palette),
    glass: glass ?? GlassMaterialTokens.fromPalette(palette),
    selectionMenu: selectionMenu ?? SelectionMenuTokens.fromPalette(palette),
    pointerMenu: pointerMenu ?? PointerMenuTokens.fromPalette(palette),
    spoiler: spoiler ?? SpoilerTokens.fromPalette(palette),
  );

  /// The semantic roles the groups were derived from.
  final ChromePalette palette;

  /// Composer colours.
  final ComposerTokens composer;

  /// Panel colours.
  final PanelTokens panel;

  /// Action chrome colours.
  final ActionTokens action;

  /// Empty-state, hint and skeleton colours.
  final PlaceholderTokens placeholder;

  /// Glass material colours.
  final GlassMaterialTokens glass;

  /// Selection menu colours.
  final SelectionMenuTokens selectionMenu;

  /// Pointer menu colours.
  final PointerMenuTokens pointerMenu;

  /// Spoiler colour and particle motion.
  final SpoilerTokens spoiler;

  /// A copy with the named parts replaced.
  ///
  /// Replacing [palette] does not re-derive the groups: a group that was
  /// overridden by the host stays overridden. Build a new theme with
  /// [ChromeThemeData.fromPalette] to derive again.
  ChromeThemeData copyWith({
    ChromePalette? palette,
    ComposerTokens? composer,
    PanelTokens? panel,
    ActionTokens? action,
    PlaceholderTokens? placeholder,
    GlassMaterialTokens? glass,
    SelectionMenuTokens? selectionMenu,
    PointerMenuTokens? pointerMenu,
    SpoilerTokens? spoiler,
  }) => ChromeThemeData(
    palette: palette ?? this.palette,
    composer: composer ?? this.composer,
    panel: panel ?? this.panel,
    action: action ?? this.action,
    placeholder: placeholder ?? this.placeholder,
    glass: glass ?? this.glass,
    selectionMenu: selectionMenu ?? this.selectionMenu,
    pointerMenu: pointerMenu ?? this.pointerMenu,
    spoiler: spoiler ?? this.spoiler,
  );

  /// Interpolates the palette and every group between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static ChromeThemeData lerp(ChromeThemeData a, ChromeThemeData b, double t) =>
      ChromeThemeData(
        palette: ChromePalette.lerp(a.palette, b.palette, t),
        composer: ComposerTokens.lerp(a.composer, b.composer, t),
        panel: PanelTokens.lerp(a.panel, b.panel, t),
        action: ActionTokens.lerp(a.action, b.action, t),
        placeholder: PlaceholderTokens.lerp(a.placeholder, b.placeholder, t),
        glass: GlassMaterialTokens.lerp(a.glass, b.glass, t),
        selectionMenu: SelectionMenuTokens.lerp(
          a.selectionMenu,
          b.selectionMenu,
          t,
        ),
        pointerMenu: PointerMenuTokens.lerp(a.pointerMenu, b.pointerMenu, t),
        spoiler: SpoilerTokens.lerp(a.spoiler, b.spoiler, t),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChromeThemeData &&
          palette == other.palette &&
          composer == other.composer &&
          panel == other.panel &&
          action == other.action &&
          placeholder == other.placeholder &&
          glass == other.glass &&
          selectionMenu == other.selectionMenu &&
          pointerMenu == other.pointerMenu &&
          spoiler == other.spoiler;

  @override
  int get hashCode => Object.hash(
    palette,
    composer,
    panel,
    action,
    placeholder,
    glass,
    selectionMenu,
    pointerMenu,
    spoiler,
  );

  @override
  String toString() => 'ChromeThemeData($palette)';
}
