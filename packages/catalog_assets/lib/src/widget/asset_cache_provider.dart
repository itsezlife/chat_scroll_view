import 'package:catalog_assets/src/asset/asset_cache_scope.dart';
import 'package:flutter/widgets.dart';

/// Makes the host's [AssetCacheScope] available to the widgets below, so
/// `ContentView` finds the cache without it being passed down by hand.
///
/// The host creates the scope and disposes it; the provider only hands it
/// out and never disposes it. Surfaces that cannot be below a provider take
/// the scope as an argument instead.
class AssetCacheProvider extends InheritedWidget {
  /// Provides [scope] to [child] and everything below.
  const AssetCacheProvider({
    required this.scope,
    required super.child,
    super.key,
  });

  /// The cache every surface below attaches to.
  final AssetCacheScope scope;

  /// The scope of the closest provider above [context], or null.
  ///
  /// Registers [context] as a dependent, so it rebuilds when the host
  /// provides another scope.
  static AssetCacheScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AssetCacheProvider>()?.scope;

  /// The scope of the closest provider above [context].
  ///
  /// Throws a [FlutterError] when there is none: a surface that draws content
  /// without a cache is a wiring mistake to see, not to absorb.
  static AssetCacheScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope;
    throw FlutterError.fromParts([
      ErrorSummary('No AssetCacheProvider found above this widget.'),
      ErrorDescription(
        '${context.widget.runtimeType} draws content through the host\'s '
        'AssetCacheScope, which it looks up with AssetCacheProvider.',
      ),
      ErrorHint(
        'Wrap the app (or the subtree) in AssetCacheProvider(scope: ...), or '
        'pass the scope to the widget directly.',
      ),
    ]);
  }

  @override
  bool updateShouldNotify(AssetCacheProvider oldWidget) =>
      !identical(scope, oldWidget.scope);
}
