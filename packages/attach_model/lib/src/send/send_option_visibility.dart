import 'package:attach_model/src/item/attach_item.dart';
import 'package:attach_model/src/item/attach_limits.dart';
import 'package:attach_model/src/policy/attach_policy.dart';
import 'package:attach_model/src/send/send_options.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// When a policy offers "send in high quality".
enum HighQualityOffer {
  /// When every item is an unedited photo.
  allUneditedPhotos,

  /// When some photo sent as media has a side over the standard photo side.
  largePhoto,

  /// Never.
  never,
}

/// Which send options the attach panel's menu and the confirm box show for
/// a selection: pure rules over the items, the caption, the options, the
/// policy and the limits.
///
/// The menu (Android, iOS), the send menu and the confirm box checkboxes
/// (desktop) and the more menu (web) each read the getters they draw.
@immutable
final class SendOptionVisibility {
  /// The visibility for [items] with [caption] under [options]. [initial]
  /// is what the options were when the box opened, for [remember].
  SendOptionVisibility({
    required Iterable<AttachItem> items,
    required this.caption,
    required this.options,
    required this.policy,
    required this.limits,
    this.initial = const SendOptions(),
  }) : items = List.unmodifiable(items);

  /// The selected items, in order.
  final List<AttachItem> items;

  /// The batch caption.
  final RichText caption;

  /// The options as they are now.
  final SendOptions options;

  /// The options when the box opened.
  final SendOptions initial;

  /// The platform's rules.
  final AttachPolicy policy;

  /// The host's limits.
  final AttachLimits limits;

  bool get _hasMedia => items.any((item) => item.kind.isMedia);

  bool get _hasPhotoOrVideo => items.any(
    (item) => item.kind == AttachKind.photo || item.kind == AttachKind.video,
  );

  /// "Send as file(s)": some media, allowed by the limits, and on a policy
  /// that hides it under a spoiler, no spoiler.
  bool get sendAsFile =>
      limits.sendAsFileAllowed &&
      _hasMedia &&
      !(policy.sendAsFileHiddenBySpoiler && items.any((i) => i.spoiler));

  /// "Send without grouping": more than one item, grouping allowed.
  bool get withoutGrouping => limits.groupingAllowed && items.length > 1;

  /// "Send in high quality", by [AttachPolicy.highQualityOffer].
  bool get highQuality => switch (policy.highQualityOffer) {
    HighQualityOffer.allUneditedPhotos =>
      items.isNotEmpty &&
          items.every(
            (item) => item.kind == AttachKind.photo && !item.isEdited,
          ),
    HighQualityOffer.largePhoto =>
      !options.asFiles &&
          items.any(
            (item) =>
                item.kind == AttachKind.photo &&
                (item.effectiveDimensions?.longSide ?? 0) >
                    policy.standardPhotoSide,
          ),
    HighQualityOffer.never => false,
  };

  /// "Caption above / below": a caption, every item media, sent as media.
  bool get captionAbove =>
      !caption.isEmpty &&
      !options.asFiles &&
      items.isNotEmpty &&
      items.every((item) => item.kind.isMedia);

  /// "Spoiler": some media sent as media, allowed by the limits.
  bool get spoiler => limits.spoilerAllowed && !options.asFiles && _hasMedia;

  /// The confirm box's "Group items" checkbox: grouping allowed and two
  /// neighbours that can share a group (the same kind, photo and video, or
  /// media next to a file, which group once sent as files).
  bool get groupCheckbox {
    if (!limits.groupingAllowed) return false;
    for (var i = 1; i < items.length; i++) {
      if (_canShare(items[i - 1].kind, items[i].kind)) return true;
    }
    return false;
  }

  /// The confirm box's "Send as documents" checkbox: some photo or video;
  /// in slow mode (no grouping) exactly one item that is one.
  bool get asDocumentsCheckbox {
    if (!limits.groupingAllowed) {
      return items.length == 1 && _hasPhotoOrVideo;
    }
    return _hasPhotoOrVideo;
  }

  /// The confirm box's "Remember": only after a checkbox differs from
  /// [initial].
  bool get remember =>
      options.grouped != initial.grouped || options.asFiles != initial.asFiles;

  static bool _canShare(AttachKind a, AttachKind b) {
    if (a == AttachKind.animation || b == AttachKind.animation) return false;
    if (a == b) return true;
    bool groupable(AttachKind k) =>
        k == AttachKind.photo || k == AttachKind.video || k == AttachKind.file;
    return groupable(a) && groupable(b);
  }
}
