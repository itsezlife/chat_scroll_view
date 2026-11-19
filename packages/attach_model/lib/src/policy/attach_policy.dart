import 'package:meta/meta.dart';

/// The operating system a host runs on, as the host reports it.
///
/// The model imports no `dart:io` and no Flutter, so the host maps its own
/// platform reading (Flutter's `TargetPlatform`) to this and says separately
/// whether it runs in a browser.
enum AttachHostPlatform {
  /// Android.
  android,

  /// iOS and iPadOS.
  iOS,

  /// macOS.
  macOS,

  /// Windows.
  windows,

  /// Linux.
  linux,

  /// Fuchsia.
  fuchsia,
}

/// The **attach policy**: the model's rules for one platform family, as
/// plain values.
///
/// Four stock families follow their reference clients: [AttachPolicy.android],
/// [AttachPolicy.ios], [AttachPolicy.desktop] and [AttachPolicy.web].
/// [AttachPolicy.forPlatform] picks one. Not sealed: a host changes one rule
/// by extending a stock family and overriding that getter; nothing reads
/// which family a policy is. Run `AttachPolicyContract` from
/// `package:attach_model/testing.dart` over a host's policy.
@immutable
abstract base class AttachPolicy {
  /// A policy; for subclasses.
  const AttachPolicy();

  /// The Android family; see [AttachPolicy$Android].
  const factory AttachPolicy.android() = AttachPolicy$Android;

  /// The iOS family; see [AttachPolicy$IOS].
  const factory AttachPolicy.ios() = AttachPolicy$IOS;

  /// The desktop family; see [AttachPolicy$Desktop].
  const factory AttachPolicy.desktop() = AttachPolicy$Desktop;

  /// The web family; see [AttachPolicy$Web].
  const factory AttachPolicy.web() = AttachPolicy$Web;

  /// The family of [platform]. A browser is the web family on every device
  /// ([isWeb] wins); Android and iOS are their own; every other system is
  /// the desktop family.
  factory AttachPolicy.forPlatform(
    AttachHostPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb) return const AttachPolicy.web();
    return switch (platform) {
      AttachHostPlatform.android => const AttachPolicy.android(),
      AttachHostPlatform.iOS => const AttachPolicy.ios(),
      AttachHostPlatform.macOS ||
      AttachHostPlatform.windows ||
      AttachHostPlatform.linux ||
      AttachHostPlatform.fuchsia => const AttachPolicy.desktop(),
    };
  }

  // --- Selection ---

  /// The most items the attach selection holds; null for no cap. Single
  /// select caps it at 1 whatever this says.
  int? get selectionCap;
}

// --- Stock families ---

/// The Android family: an in-app grid capped at 100 items.
base class AttachPolicy$Android extends AttachPolicy {
  /// The Android family.
  const AttachPolicy$Android();

  @override
  int? get selectionCap => 100;
}

/// The iOS family: an in-app grid capped at 100 items.
base class AttachPolicy$IOS extends AttachPolicy {
  /// The iOS family.
  const AttachPolicy$IOS();

  @override
  int? get selectionCap => 100;
}

/// The desktop family: a confirm box that takes any number of items and
/// cuts them into send groups of ten.
base class AttachPolicy$Desktop extends AttachPolicy {
  /// The desktop family.
  const AttachPolicy$Desktop();

  @override
  int? get selectionCap => null;
}

/// The web family: a confirm box that takes any number of items.
base class AttachPolicy$Web extends AttachPolicy {
  /// The web family.
  const AttachPolicy$Web();

  @override
  int? get selectionCap => null;
}
