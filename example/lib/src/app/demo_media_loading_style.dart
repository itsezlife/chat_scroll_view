import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mpx_core/mpx_core.dart';

/// The app's look of loading media, from its chrome tokens: the media core's
/// platform style with the badge's text in the app's typeface, its capsule in
/// the palette's shadow ink and the outline previews in the quiet skeleton
/// fill.
///
/// Only colours and text change (`copyWith` over the platform's style): the
/// geometry, timings and transitions stay the platform's. Sits under the
/// [ChromeThemeScope] it reads.
class DemoMediaLoadingStyle extends StatelessWidget {
  /// Styles the loading media of [child].
  const DemoMediaLoadingStyle({required this.child, super.key});

  /// The subtree whose media take the style.
  final Widget child;

  /// The platform's [style] with the chrome tokens of [theme] and the text
  /// style of [typeface].
  static MediaLoadingStyle styled(
    MediaLoadingStyle style, {
    required ChromeThemeData theme,
    required TextStyle typeface,
  }) {
    final badge = style.badge;
    return style.copyWith(
      stages: style.stages.copyWith(outlineFill: theme.placeholder.skeleton),
      badge: badge.copyWith(
        // The badge's size and colour are the platform's, over the media; its
        // typeface is the app's.
        textStyle: typeface.merge(badge.textStyle),
        background: theme.palette.shadow.withValues(alpha: badge.background.a),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChromeThemeScope.of(context);
    final typeface = ChromeTypography.of(context);
    return MediaLoadingStyleScope(
      style: (platform) => styled(platform, theme: theme, typeface: typeface),
      child: child,
    );
  }
}
