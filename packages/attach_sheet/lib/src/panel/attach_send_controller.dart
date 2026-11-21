import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/debug/attach_log.dart';
import 'package:attach_sheet/src/host/attach_caption_dock.dart';
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
    caption = ComposerController(
      text: _captionText,
      focusNode: _CaptionFocusNode(),
    );
    AttachLog.log(
      AttachLog.caption,
      'created: inline content ${_captionText == null ? 'as text' : 'drawn'}',
    );
    caption.restore(initialCaption);
    selection.caption = caption.richText;
    caption.focusNode.addListener(_captionFocus);
    caption.text.addListener(_captionChanged);
    selection.changes.addListener(_selectionChanged);
    selection.captionChanges.addListener(_sharedCaptionChanged);
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

  // The field is the selection's shared caption: an edit here writes it,
  // and a change there (the viewer, a reorder handing the first item's
  // caption on) loads it here.
  var _syncingCaption = false;

  void _sharedCaptionChanged() {
    if (_syncingCaption || _$disposed) return;
    final shared = selection.caption;
    if (shared == caption.richText) return;
    _syncingCaption = true;
    try {
      caption.restore(shared);
    } finally {
      _syncingCaption = false;
    }
  }

  // Logs each change of the inline content the caption holds.
  void _captionChanged() {
    if (!_syncingCaption) {
      _syncingCaption = true;
      try {
        selection.caption = caption.richText;
      } finally {
        _syncingCaption = false;
      }
    }
    // Typed from the panel: no handle stays up over the caption.
    if (captionDock?.panelUp ?? false) caption.hideSelectionUi();
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

  /// The request sent, once Send was accepted; null before.
  SendRequest? sent;

  /// Counts refused sends; the field shakes on each.
  final ValueNotifier<int> refusals = ValueNotifier(0);

  /// Whether the selected-items preview is shown in place of the page's
  /// grid: the counter's tap turns it on and off, and it goes when the
  /// selection empties.
  final ValueNotifier<bool> previewingSelection = ValueNotifier(false);

  /// The dock under the sheet's caption bar, the host's; null with no
  /// panel.
  late final AttachCaptionDock? captionDock = _makeDock();
  bool _dockMade = false;
  AttachCaptionDock? _makeDock() {
    _dockMade = true;
    return host.createCaptionDock(caption);
  }

  /// A tap on the caption field: a field that lost its focus takes it back
  /// and asks for its keyboard (the dock then gives the panel's place back).
  void captionTapped() => fieldTapped(caption, captionDock);

  /// A tap on a caption [field] on [dock] (the sheet's, or the viewer's own
  /// over the same text).
  void fieldTapped(ComposerController field, AttachCaptionDock? dock) {
    AttachLog.log(
      AttachLog.caption,
      'tap (panel ${dock?.panelUp ?? false ? 'up' : 'down'}, focus '
      '${field.focusNode.hasFocus}, soft keyboard '
      '${field.softKeyboard.value.name})',
    );
    if (dock != null && dock.panelUp) {
      dock.onFieldTap();
      return;
    }
    // A tap asks for the keyboard: one held back (the panel closed away from
    // the field) is let go.
    field.setSoftKeyboard(SoftKeyboardMode.auto);
    if (!field.focusNode.hasFocus) field.requestFocus();
    field.requestKeyboard();
    dock?.onFieldTap();
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
      items: selection.itemsToSend,
      caption: caption.richText,
      options: sent,
    );
    if (store case final store?) unawaited(store.save(sent));
    this.sent = request;
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
    selection.captionChanges.removeListener(_sharedCaptionChanged);
    previewingSelection.dispose();
    caption.focusNode.removeListener(_captionFocus);
    caption.text.removeListener(_captionChanged);
    if (_dockMade) captionDock?.dispose();
    caption.dispose();
    caption.focusNode.dispose();
    _captionText?.dispose();
    options.dispose();
    refusals.dispose();
  }
}

/// The caption's focus node: it logs who takes focus away from it, with a
/// short stack, so a device log names the caller.
final class _CaptionFocusNode extends FocusNode {
  _CaptionFocusNode() : super(debugLabel: 'Caption');

  @override
  void unfocus({UnfocusDisposition disposition = UnfocusDisposition.scope}) {
    if (hasFocus) {
      AttachLog.log(
        AttachLog.focus,
        'caption unfocus (${disposition.name}) from:\n${_stack()}',
      );
    }
    super.unfocus(disposition: disposition);
  }

  // The first frames past this node, the framework's own left out.
  static String _stack() => StackTrace.current
      .toString()
      .split('\n')
      .skip(2)
      .where((line) => line.trim().isNotEmpty)
      .take(10)
      .join('\n');
}
