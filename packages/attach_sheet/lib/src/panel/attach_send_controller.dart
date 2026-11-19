import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/host/attach_sheet_host.dart';
import 'package:attach_sheet/src/panel/attach_interaction.dart';
import 'package:attach_sheet/src/policy/attach_panel_style.dart';
import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// The state behind the **attach panel**: the caption, the send options, the
/// menus' entries, and the send itself.
///
/// One per open. The sheet's panel, the picker-mode viewer's bottom slot and
/// the confirm box all draw the same controller, so the caption and options
/// follow the user between them.
///
/// The caption starts as the host's composer text (the **caption move**)
/// and goes back in `AttachOutcome.cancelled`. The options start from the
/// [store] (when given) and are written back on send.
final class AttachSendController {
  /// A controller over [selection] for [policy].
  AttachSendController({
    required this.selection,
    required this.policy,
    required this.host,
    required this.onSend,
    RichText initialCaption = RichText.empty,
    SendOptions initialOptions = const SendOptions(),
    this.store,
  }) : options = ValueNotifier(initialOptions) {
    caption.restore(initialCaption);
    if (store case final store?) {
      unawaited(
        store.restore(initialOptions).then((restored) {
          if (!_$disposed) options.value = restored;
        }),
      );
    }
  }

  /// The open's selection.
  final AttachSelection selection;

  /// The sheet's policy (counter, haptics, menus).
  final AttachSheetPolicy policy;

  /// The sheet's host (schedule picker, external picker, interactions).
  final AttachSheetHost host;

  /// Called with the request when a send is accepted.
  final ValueChanged<SendRequest> onSend;

  /// Where the options are remembered; null for nowhere.
  final SendOptionStore? store;

  /// The caption's input.
  final ComposerController caption = ComposerController();

  /// The send options.
  final ValueNotifier<SendOptions> options;

  /// Counts refused sends; the field shakes on each.
  final ValueNotifier<int> refusals = ValueNotifier(0);

  bool _$disposed = false;

  /// The caption's limit in code points.
  int get captionLimit => selection.limits.captionLength;

  /// The caption length from which the counter shows; null for no counter.
  int? get counterFrom => switch (policy.panel.counterRemaining) {
    final remaining? => captionLimit - remaining,
    null => null,
  };

  /// Which options the current selection offers.
  SendOptionVisibility get visibility => SendOptionVisibility(
    items: selection.items,
    caption: caption.richText,
    options: options.value,
    policy: selection.policy,
    limits: selection.limits,
  );

  bool get _hasTimer => selection.items.any((item) => item.timer != null);

  /// The send menu's entries that show now, in the policy's order.
  List<AttachSendMenuItem> get sendMenu => [
    for (final item in policy.panel.sendMenu)
      if (switch (item) {
        AttachSendMenuItem.silent => true,
        AttachSendMenuItem.schedule || AttachSendMenuItem.whenOnline =>
          selection.limits.scheduleAllowed && !_hasTimer,
        AttachSendMenuItem.captionAbove => visibility.captionAbove,
      })
        item,
  ];

  /// The overflow menu's entries that show now, in the policy's order.
  List<AttachOverflowItem> get overflow {
    final shown = visibility;
    final some = selection.isNotEmpty;
    return [
      for (final item in policy.panel.overflow)
        if (switch (item) {
          AttachOverflowItem.openExternal => !some,
          AttachOverflowItem.sendAsFiles => some && shown.sendAsFile,
          AttachOverflowItem.withoutGrouping => shown.withoutGrouping,
          AttachOverflowItem.spoiler => some && shown.spoiler,
          AttachOverflowItem.quality => shown.highQuality,
          AttachOverflowItem.highQuality => some && !options.value.asFiles,
          AttachOverflowItem.captionAbove => shown.captionAbove,
        })
          item,
    ];
  }

  /// Whether every selected item is under a spoiler.
  bool get allSpoilered =>
      selection.isNotEmpty && selection.items.every((item) => item.spoiler);

  /// Sends with the options, changed by [change] for this send only. A
  /// caption over the limit is refused: the field shakes, the policy's
  /// haptic plays and the host hears an [AttachInteraction.captionTooLong].
  /// Returns whether it was sent.
  bool send([SendOptions Function(SendOptions options)? change]) {
    if (_$disposed) return false;
    final over = caption.length - captionLimit;
    if (over > 0) {
      refusals.value++;
      _haptic(policy.panel.overLimitHaptic);
      host.interaction(AttachInteraction.captionTooLong(over: over));
      return false;
    }
    final sent = change == null ? options.value : change(options.value);
    final request = SendRequest(
      items: selection.items,
      caption: caption.richText,
      options: sent,
    );
    if (store case final store?) unawaited(store.save(sent));
    onSend(request);
    return true;
  }

  /// Runs the send menu's [item].
  Future<void> runSendMenu(
    AttachSendMenuItem item,
    BuildContext context,
  ) async {
    switch (item) {
      case AttachSendMenuItem.silent:
        send((o) => o.copyWith(silent: true));
      case AttachSendMenuItem.schedule:
        final schedule = await host.pickSchedule(context);
        if (schedule != null) send((o) => o.copyWith(schedule: schedule));
      case AttachSendMenuItem.whenOnline:
        send((o) => o.copyWith(schedule: const SendSchedule.whenOnline()));
      case AttachSendMenuItem.captionAbove:
        _toggleCaptionAbove();
    }
  }

  /// Runs the overflow menu's [item].
  void runOverflow(AttachOverflowItem item) {
    switch (item) {
      case AttachOverflowItem.openExternal:
        host.openExternalPicker();
      case AttachOverflowItem.sendAsFiles:
        send((o) => o.copyWith(asFiles: true));
      case AttachOverflowItem.withoutGrouping:
        send((o) => o.copyWith(grouped: false));
      case AttachOverflowItem.spoiler:
        final spoiler = !allSpoilered;
        for (final item in selection.items) {
          selection.update(item.id, (i) => i.copyWith(spoiler: spoiler));
        }
      case AttachOverflowItem.quality:
        options.value = options.value.copyWith(
          highQuality: !options.value.highQuality,
        );
        if (store case final store?) unawaited(store.save(options.value));
      case AttachOverflowItem.highQuality:
        send((o) => o.copyWith(highQuality: true));
      case AttachOverflowItem.captionAbove:
        _toggleCaptionAbove();
    }
  }

  void _toggleCaptionAbove() => options.value = options.value.copyWith(
    captionAbove: !options.value.captionAbove,
  );

  static void _haptic(AttachHaptic haptic) {
    switch (haptic) {
      case AttachHaptic.none:
        return;
      case AttachHaptic.keyboardTap:
        unawaited(HapticFeedback.selectionClick());
      case AttachHaptic.error:
        unawaited(HapticFeedback.heavyImpact());
    }
  }

  /// Releases the caption input.
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    caption.dispose();
    options.dispose();
    refusals.dispose();
  }
}
