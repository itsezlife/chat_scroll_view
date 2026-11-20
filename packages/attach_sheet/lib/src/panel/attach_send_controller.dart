import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/debug/attach_log.dart';
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
  }) : options = ValueNotifier(initialOptions),
       _captionText = host.createCaptionText() {
    caption = ComposerController(text: _captionText);
    AttachLog.log(
      AttachLog.caption,
      'created: inline content ${_captionText == null ? 'as text' : 'drawn'}',
    );
    caption.restore(initialCaption);
    caption.focusNode.addListener(_captionFocus);
    caption.text.addListener(_captionChanged);
    selection.changes.addListener(_selectionChanged);
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

  /// The caption's input, over the host's text controller when it gives
  /// one (`AttachSheetHost.createCaptionText`).
  late final ComposerController caption;
  final ComposerTextController? _captionText;
  int _loggedInline = 0;

  void _captionFocus() => AttachLog.log(
    AttachLog.caption,
    'focus ${caption.focusNode.hasFocus ? 'in' : 'out'} '
    '(soft keyboard ${caption.softKeyboard.value.name})',
  );

  // Logs each change of the inline content the caption holds.
  void _captionChanged() {
    final rich = caption.richText;
    final inline = rich.entities
        .where((e) => e.kind is EntityKind$InlineContent)
        .length;
    if (inline == _loggedInline) return;
    _loggedInline = inline;
    AttachLog.log(
      AttachLog.caption,
      'inline content: $inline in ${rich.plain.length} chars',
    );
  }

  /// The send options.
  final ValueNotifier<SendOptions> options;

  /// Counts refused sends; the field shakes on each.
  final ValueNotifier<int> refusals = ValueNotifier(0);

  /// Whether the selected-items preview is shown in place of the page's
  /// grid: the counter's tap turns it on and off, and it goes when the
  /// selection empties.
  final ValueNotifier<bool> previewingSelection = ValueNotifier(false);

  /// Whether the caption's panel stands in the keyboard's place.
  final ValueNotifier<bool> captionPanelShown = ValueNotifier(false);

  /// The keyboard's last full height, the panel's height in its place; a
  /// keyboard's usual height until one has shown.
  double keyboardHeight = 280;

  // The tallest inset of the keyboard up now: a keyboard on its way up or
  // down reports less than its height, which is never the panel's.
  double _rising = 0;

  /// Tells the controller the keyboard's inset now. A keyboard's full
  /// height is the tallest inset it reaches while up: while it is on its
  /// way up or down the height known before holds (never less), and once it
  /// is down its tallest inset becomes the height.
  void noteKeyboard(double inset) {
    if (captionPanelHandingOff) return;
    if (inset <= 0) {
      if (_rising > 0) keyboardHeight = _rising;
      _rising = 0;
      return;
    }
    if (inset > _rising) _rising = inset;
    if (_rising > keyboardHeight) keyboardHeight = _rising;
  }

  /// The caption's button: the panel takes the keyboard's place (the field
  /// keeps focus and its caret, with no soft keyboard), or gives it back to
  /// the keyboard.
  void toggleCaptionPanel() {
    AttachLog.log(
      AttachLog.panel,
      'toggle: ${captionPanelShown.value ? 'to keyboard' : 'to panel'} '
      '(focus ${caption.focusNode.hasFocus}, height $keyboardHeight)',
    );
    if (captionPanelShown.value) {
      showCaptionKeyboard();
    } else {
      caption
        ..setSoftKeyboard(SoftKeyboardMode.suppressed)
        ..requestFocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
      captionPanelHandingOff = false;
      captionPanelShown.value = true;
    }
  }

  /// Whether the panel last went for the keyboard (its place handed over)
  /// rather than away (back, a close).
  bool get captionPanelLeftForKeyboard => _leftForKeyboard;
  bool _leftForKeyboard = false;

  /// Whether the panel's place is going to the rising keyboard now: its
  /// height is not a resting keyboard's to remember.
  bool captionPanelHandingOff = false;

  /// The keyboard back in the panel's place.
  void showCaptionKeyboard() {
    _leftForKeyboard = true;
    captionPanelHandingOff = true;
    AttachLog.log(AttachLog.panel, 'keyboard back in the panel place');
    captionPanelShown.value = false;
    caption
      ..setSoftKeyboard(SoftKeyboardMode.auto)
      ..requestKeyboard();
  }

  /// The panel goes, the keyboard staying down (back, a close).
  void closeCaptionPanel() {
    if (!captionPanelShown.value) return;
    AttachLog.log(AttachLog.panel, 'closed, the keyboard staying down');
    _leftForKeyboard = false;
    captionPanelShown.value = false;
    caption.setSoftKeyboard(SoftKeyboardMode.auto);
  }

  /// Whether a page can show the selected-items preview (a Gallery is
  /// mounted): only then does the count take taps.
  bool get selectionPreviewAvailable => _previewHosts > 0;
  int _previewHosts = 0;

  /// A page that shows the selected-items preview came ([present]) or went.
  void hostSelectionPreview({required bool present}) =>
      _previewHosts += present ? 1 : -1;

  /// Shows the selected-items preview, or goes back from it; nothing to
  /// preview with nothing selected, or without a page to show it.
  void toggleSelectionPreview() {
    if (!selectionPreviewAvailable) return;
    previewingSelection.value =
        !previewingSelection.value && selection.isNotEmpty;
  }

  void _selectionChanged() {
    if (selection.isEmpty) previewingSelection.value = false;
  }

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
        AttachSendMenuItem.highQuality => visibility.highQuality,
        AttachSendMenuItem.spoiler => visibility.spoiler,
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
      case AttachSendMenuItem.highQuality:
        options.value = options.value.copyWith(
          highQuality: !options.value.highQuality,
        );
      case AttachSendMenuItem.spoiler:
        _toggleSpoilers();
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
        _toggleSpoilers();
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

  void _toggleSpoilers() {
    final spoiler = !allSpoilered;
    for (final item in selection.items) {
      selection.update(item.id, (i) => i.copyWith(spoiler: spoiler));
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
    selection.changes.removeListener(_selectionChanged);
    previewingSelection.dispose();
    captionPanelShown.dispose();
    caption.focusNode.removeListener(_captionFocus);
    caption.text.removeListener(_captionChanged);
    caption.dispose();
    _captionText?.dispose();
    options.dispose();
    refusals.dispose();
  }
}
