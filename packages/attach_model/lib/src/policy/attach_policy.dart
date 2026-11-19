import 'package:attach_model/src/item/attach_item.dart';
import 'package:attach_model/src/send/send_option_visibility.dart';
import 'package:attach_model/src/send/send_plan.dart';
import 'package:attach_model/src/store/send_option_store.dart';
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

  // --- Send plan ---

  /// The most items in one send group: ten on every stock family, whatever
  /// the selection cap.
  int get maxGroupSize => 10;

  /// Which planned send carries the batch caption.
  CaptionPlacement get captionPlacement;

  /// Whether [item] turns grouping off for the whole batch. [asFiles] is
  /// whether media goes as files (timers are already cleared then).
  ///
  /// Apart from this, an item with a timer and an animation sent as media
  /// never join a group on any family; the plan applies that itself.
  bool ungroupsBatch(AttachItem item, {required bool asFiles});

  // --- Send options ---

  /// Whether "send as file" hides while any item has a spoiler.
  bool get sendAsFileHiddenBySpoiler => false;

  /// When "send in high quality" is offered.
  HighQualityOffer get highQualityOffer;

  /// The long side a standard-quality photo is prepared at; a photo over it
  /// is what [HighQualityOffer.largePhoto] looks for.
  int get standardPhotoSide => 1280;

  /// What the send option store remembers between opens.
  SendOptionPersistence get sendOptionPersistence;
}

// --- Stock families ---

/// The Android family: an in-app grid capped at 100 items.
base class AttachPolicy$Android extends AttachPolicy {
  /// The Android family.
  const AttachPolicy$Android();

  @override
  int? get selectionCap => 100;

  @override
  CaptionPlacement get captionPlacement => CaptionPlacement.firstSend;

  /// Nothing ungroups the batch: an item with a timer leaves only its own
  /// group.
  @override
  bool ungroupsBatch(AttachItem item, {required bool asFiles}) => false;

  @override
  HighQualityOffer get highQualityOffer => HighQualityOffer.allUneditedPhotos;

  /// The high-quality default and the video preset chosen for each number
  /// of presets offered.
  @override
  SendOptionPersistence get sendOptionPersistence =>
      const SendOptionPersistence(
        options: {
          PersistedSendOption.highQuality,
          PersistedSendOption.videoPreset,
        },
        presetPerOfferedCount: true,
      );
}

/// The iOS family: an in-app grid capped at 100 items.
base class AttachPolicy$IOS extends AttachPolicy {
  /// The iOS family.
  const AttachPolicy$IOS();

  @override
  int? get selectionCap => 100;

  @override
  CaptionPlacement get captionPlacement =>
      CaptionPlacement.firstWhenGroupedElseLast;

  /// A timer, an animation or a muted video ungroups the batch.
  @override
  bool ungroupsBatch(AttachItem item, {required bool asFiles}) =>
      item.timer != null || (!asFiles && (item.isAnimated || item.isMuted));

  @override
  bool get sendAsFileHiddenBySpoiler => true;

  @override
  HighQualityOffer get highQualityOffer => HighQualityOffer.allUneditedPhotos;

  /// High quality and one preferred video preset.
  @override
  SendOptionPersistence get sendOptionPersistence =>
      const SendOptionPersistence(
        options: {
          PersistedSendOption.highQuality,
          PersistedSendOption.videoPreset,
        },
      );
}

/// The desktop family: a confirm box that takes any number of items and
/// cuts them into send groups of ten.
base class AttachPolicy$Desktop extends AttachPolicy {
  /// The desktop family.
  const AttachPolicy$Desktop();

  @override
  int? get selectionCap => null;

  @override
  CaptionPlacement get captionPlacement =>
      CaptionPlacement.lastMediaGroupElseLastItem;

  /// Any timer ungroups the batch.
  @override
  bool ungroupsBatch(AttachItem item, {required bool asFiles}) =>
      item.timer != null;

  @override
  HighQualityOffer get highQualityOffer => HighQualityOffer.largePhoto;

  /// Grouping, as files and large photos, only when "Remember" is ticked.
  @override
  SendOptionPersistence get sendOptionPersistence =>
      const SendOptionPersistence(
        options: {
          PersistedSendOption.grouped,
          PersistedSendOption.asFiles,
          PersistedSendOption.highQuality,
        },
        onlyWhenRemembered: true,
      );
}

/// The web family: a confirm box that takes any number of items.
base class AttachPolicy$Web extends AttachPolicy {
  /// The web family.
  const AttachPolicy$Web();

  @override
  int? get selectionCap => null;

  @override
  CaptionPlacement get captionPlacement =>
      CaptionPlacement.firstSendOrTextAhead;

  /// Any animation sent as media ungroups the batch.
  @override
  bool ungroupsBatch(AttachItem item, {required bool asFiles}) =>
      !asFiles && item.isAnimated;

  @override
  HighQualityOffer get highQualityOffer => HighQualityOffer.never;

  @override
  SendOptionPersistence get sendOptionPersistence => SendOptionPersistence.none;
}
