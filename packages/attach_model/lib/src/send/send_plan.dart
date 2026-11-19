import 'package:attach_model/src/item/attach_item.dart';
import 'package:attach_model/src/item/attach_limits.dart';
import 'package:attach_model/src/policy/attach_policy.dart';
import 'package:attach_model/src/send/send_options.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// How a planned send goes: as media, as files, or as audio.
///
/// Items of one form share a send group; a change of form starts a new one.
enum SendForm {
  /// Photos, videos and animations shown as media.
  media,

  /// Documents, and media sent as files.
  file,

  /// Music and voice files.
  audio,
}

/// Which planned send carries the batch caption, per platform family.
enum CaptionPlacement {
  /// The first send's first item.
  firstSend,

  /// The first send's first item when the batch is grouped, else the last
  /// send.
  firstWhenGroupedElseLast,

  /// The first item of the last send when it is a media group, else the
  /// last item.
  lastMediaGroupElseLastItem,

  /// The first send's first item when there is one send; with more, a text
  /// send ahead of them and no caption on the media.
  firstSendOrTextAhead,
}

/// One **planned send**: a single item, a send group, or the caption sent
/// as text. The host makes each one message (or one grouped message).
@immutable
sealed class PlannedSend {
  const PlannedSend._();

  /// One item on its own, with the batch caption when it carries it.
  const factory PlannedSend.single(
    AttachItem item, {
    required SendForm form,
    RichText? caption,
  }) = PlannedSend$Single;

  /// A **send group** of two to ten items; [captionIndex] is the item that
  /// carries [caption], when one does.
  factory PlannedSend.group(
    List<AttachItem> items, {
    required SendForm form,
    int? captionIndex,
    RichText? caption,
  }) = PlannedSend$Group;

  /// The batch caption sent as text, ahead of the media.
  const factory PlannedSend.text(RichText caption) = PlannedSend$Text;
}

/// [PlannedSend.single].
final class PlannedSend$Single extends PlannedSend {
  /// One item.
  const PlannedSend$Single(this.item, {required this.form, this.caption})
    : super._();

  /// The item, as it is sent (timers cleared when sent as a file).
  final AttachItem item;

  /// How it goes.
  final SendForm form;

  /// The batch caption, when this send carries it.
  final RichText? caption;

  @override
  String toString() => 'PlannedSend.single(${item.id})';
}

/// [PlannedSend.group].
final class PlannedSend$Group extends PlannedSend {
  /// A send group.
  PlannedSend$Group(
    List<AttachItem> items, {
    required this.form,
    this.captionIndex,
    this.caption,
  }) : items = List.unmodifiable(items),
       assert(items.length >= 2, 'a group of one is a single'),
       assert(
         (captionIndex == null) == (caption == null),
         'a caption and its index come together',
       ),
       super._();

  /// The items, in selection order.
  final List<AttachItem> items;

  /// How they go.
  final SendForm form;

  /// The index into [items] of the item carrying [caption].
  final int? captionIndex;

  /// The batch caption, when this group carries it.
  final RichText? caption;

  @override
  String toString() =>
      'PlannedSend.group(${items.map((i) => i.id).join(', ')})';
}

/// [PlannedSend.text].
final class PlannedSend$Text extends PlannedSend {
  /// The caption as text.
  const PlannedSend$Text(this.caption) : super._();

  /// The batch caption.
  final RichText caption;

  @override
  String toString() => 'PlannedSend.text()';
}

/// Why a send cannot be planned.
enum SendRejection {
  /// No items and no caption.
  empty,

  /// The caption is longer than the attach limits allow.
  captionTooLong,

  /// An item with a self-destruct timer was asked to be scheduled.
  timerWithSchedule,

  /// A schedule was asked for where the attach limits allow none.
  scheduleNotAllowed,
}

/// The **send plan**: the pure result of planning a send.
@immutable
sealed class SendPlan {
  const SendPlan._();
}

/// A plan the host can send: [sends] in order, every item once.
final class SendPlan$Ready extends SendPlan {
  /// A plan of [sends].
  SendPlan$Ready({
    required List<PlannedSend> sends,
    required this.caption,
    required this.options,
  }) : sends = List.unmodifiable(sends),
       super._();

  /// The planned sends, in order.
  final List<PlannedSend> sends;

  /// The batch caption the plan placed; empty for none.
  final RichText caption;

  /// The options the request was planned with, which preparation reads
  /// (high quality, as files, the video preset) and the host sends with
  /// (silent, schedule, caption above).
  final SendOptions options;
}

/// A send the plan refused.
final class SendPlan$Rejected extends SendPlan {
  /// A refusal for [rejection].
  const SendPlan$Rejected(this.rejection) : super._();

  /// Why.
  final SendRejection rejection;

  @override
  String toString() => 'SendPlan.rejected(${rejection.name})';
}

/// Plans [request] under [policy] and [limits]: cuts the items into planned
/// sends and places the caption.
///
/// Pure. Every item appears once, in selection order. Items share a send
/// group of at most [AttachPolicy.maxGroupSize] when their form matches and
/// grouping is on; an item with a timer and an animation sent as media are
/// never grouped, and [AttachPolicy.ungroupsBatch] can turn grouping off for
/// the whole batch. Under "as files", timers are cleared. Spoilers never
/// change the grouping.
SendPlan planSend(
  SendRequest request,
  AttachPolicy policy,
  AttachLimits limits,
) {
  final options = request.options;
  final caption = request.caption;
  if (request.items.isEmpty && caption.isEmpty) {
    return const SendPlan$Rejected(SendRejection.empty);
  }
  if (caption.length > limits.captionLength) {
    return const SendPlan$Rejected(SendRejection.captionTooLong);
  }
  final asFiles = options.asFiles && limits.sendAsFileAllowed;
  final items = [
    for (final item in request.items)
      _asSent(item, asFiles: asFiles, limits: limits),
  ];
  if (options.schedule != null) {
    if (!limits.scheduleAllowed) {
      return const SendPlan$Rejected(SendRejection.scheduleNotAllowed);
    }
    if (items.any((item) => item.timer != null)) {
      return const SendPlan$Rejected(SendRejection.timerWithSchedule);
    }
  }
  if (items.isEmpty) {
    return SendPlan$Ready(
      sends: [PlannedSend.text(caption)],
      caption: caption,
      options: options,
    );
  }

  final grouped =
      options.grouped &&
      limits.groupingAllowed &&
      !items.any((item) => policy.ungroupsBatch(item, asFiles: asFiles));
  final runs = _runs(
    items,
    asFiles: asFiles,
    grouped: grouped,
    maxSize: policy.maxGroupSize,
  );
  return SendPlan$Ready(
    sends: _placeCaption(runs, caption, policy.captionPlacement, grouped),
    caption: caption,
    options: options,
  );
}

// --- Machinery ---

/// One run of items that go together, before the caption is placed.
typedef _Run = ({List<AttachItem> items, SendForm form});

AttachItem _asSent(
  AttachItem item, {
  required bool asFiles,
  required AttachLimits limits,
}) {
  final clearTimer = asFiles || !limits.timerAllowed;
  final clearSpoiler = !limits.spoilerAllowed;
  if (!(clearTimer && item.timer != null) && !(clearSpoiler && item.spoiler)) {
    return item;
  }
  return item.copyWith(
    clearTimer: clearTimer,
    spoiler: clearSpoiler ? false : null,
  );
}

SendForm _formOf(AttachItem item, {required bool asFiles}) =>
    switch (item.kind) {
      AttachKind.audio => SendForm.audio,
      AttachKind.file => SendForm.file,
      AttachKind.photo ||
      AttachKind.video ||
      AttachKind.animation => asFiles ? SendForm.file : SendForm.media,
    };

List<_Run> _runs(
  List<AttachItem> items, {
  required bool asFiles,
  required bool grouped,
  required int maxSize,
}) {
  final runs = <_Run>[];
  _Run? open;
  for (final item in items) {
    final form = _formOf(item, asFiles: asFiles);
    // A timer or an animation shown as media always goes alone, on every
    // platform; the batch-wide rules are the policy's.
    final alone =
        !grouped ||
        item.timer != null ||
        (form == SendForm.media && item.isAnimated);
    if (alone) {
      open = null;
      runs.add((items: [item], form: form));
      continue;
    }
    if (open case final run?
        when run.form == form && run.items.length < maxSize) {
      run.items.add(item);
      continue;
    }
    open = (items: [item], form: form);
    runs.add(open);
  }
  return runs;
}

List<PlannedSend> _placeCaption(
  List<_Run> runs,
  RichText caption,
  CaptionPlacement placement,
  bool grouped,
) {
  if (caption.isEmpty) return [for (final run in runs) _send(run)];
  final last = runs.length - 1;
  switch (placement) {
    case CaptionPlacement.firstSend:
      return [
        for (var i = 0; i < runs.length; i++)
          _send(runs[i], captionIndex: i == 0 ? 0 : null, caption: caption),
      ];
    case CaptionPlacement.firstWhenGroupedElseLast:
      final target = grouped ? 0 : last;
      return [
        for (var i = 0; i < runs.length; i++)
          _send(
            runs[i],
            captionIndex: i != target
                ? null
                : grouped
                ? 0
                : runs[i].items.length - 1,
            caption: caption,
          ),
      ];
    case CaptionPlacement.lastMediaGroupElseLastItem:
      final lastRun = runs[last];
      final mediaGroup =
          lastRun.form == SendForm.media && lastRun.items.length > 1;
      return [
        for (var i = 0; i < runs.length; i++)
          _send(
            runs[i],
            captionIndex: i != last
                ? null
                : mediaGroup
                ? 0
                : lastRun.items.length - 1,
            caption: caption,
          ),
      ];
    case CaptionPlacement.firstSendOrTextAhead:
      if (runs.length > 1) {
        return [PlannedSend.text(caption), for (final run in runs) _send(run)];
      }
      return [_send(runs.single, captionIndex: 0, caption: caption)];
  }
}

PlannedSend _send(_Run run, {int? captionIndex, RichText? caption}) {
  final carried = captionIndex == null ? null : caption;
  if (run.items.length == 1) {
    return PlannedSend.single(
      run.items.single,
      form: run.form,
      caption: carried,
    );
  }
  return PlannedSend.group(
    run.items,
    form: run.form,
    captionIndex: carried == null ? null : captionIndex,
    caption: carried,
  );
}
