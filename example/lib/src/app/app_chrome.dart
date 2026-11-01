import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:panel_pages/panel_pages.dart';

/// The app-level scopes every chrome widget reads, over [child].
///
/// Host-owned and above the whole app: the chrome theme (dark palette), the
/// strings, the motion speed (reduce motion mapped to instant: no chrome
/// package reads the platform flag itself), the glass quality, the panel's
/// category icons and the asset cache the content widgets look up. The chat screen adds its own
/// nested scopes (glass source) below.
///
/// Needs a [MediaQuery] above it; nothing here owns [AppServices.assets].
class AppChrome extends StatelessWidget {
  /// Scopes [child] with what [services] provides.
  const AppChrome({required this.services, required this.child, super.key});

  /// Where the asset cache comes from.
  final AppServices services;

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) => ChromeThemeScope(
    palette: const ChromePalette.dark(),
    // The selection menu is a Material card: it takes its fill, text and
    // divider from the app's colour scheme. The dark palette's separator is a
    // 12% black, which is invisible on a dark card.
    selectionMenu: SelectionMenuTokens.fromPalette(
      ChromePalette.fromColorScheme(Theme.of(context).colorScheme),
    ),
    // The desktop pointer menu of the composer's field is drawn in the
    // reference client's own night colours, for a 1:1 look.
    pointerMenu: PointerMenuTokens.referenceNight,
    child: ChromeStringsScope(
      strings: demoChromeStrings,
      child: ChromeMotionScope(
        speed: MediaQuery.disableAnimationsOf(context)
            ? ChromeMotionSpeed.instant
            : ChromeMotionSpeed.normal,
        // The glass policy of the app: the best strategy the device supports.
        // A host with a low-power mode passes `liteMode` here.
        child: GlassQualityScope(
          liteMode: DemoConfig.glassLite,
          child: EmojiTabIconScope(
            child: AssetCacheProvider(scope: services.assets, child: child),
          ),
        ),
      ),
    ),
  );
}
