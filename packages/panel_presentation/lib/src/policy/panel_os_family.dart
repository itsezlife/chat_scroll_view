import 'package:flutter/foundation.dart';

/// The operating-system family a policy defaults from.
///
/// Mobile families (Android and iOS) get the mobile policy; desktop operating
/// systems and the web, whatever the OS under the browser, get the desktop
/// policy. A host that disagrees passes its own policy or overrides the kind
/// per call.
enum PanelOsFamily {
  /// Android.
  android,

  /// iOS.
  iOS,

  /// macOS.
  macOS,

  /// Windows.
  windows,

  /// Linux.
  linux,

  /// Fuchsia.
  fuchsia,

  /// A browser, on any OS.
  web;

  /// The family of [platform]; [isWeb] wins over it.
  static PanelOsFamily fromPlatform(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb) return web;
    return switch (platform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => iOS,
      TargetPlatform.macOS => macOS,
      TargetPlatform.windows => windows,
      TargetPlatform.linux => linux,
      TargetPlatform.fuchsia => fuchsia,
    };
  }

  /// The family this app is running on.
  static PanelOsFamily get current =>
      fromPlatform(defaultTargetPlatform, isWeb: kIsWeb);

  /// Whether this is a phone or tablet operating system.
  bool get isMobile => this == android || this == iOS;
}
