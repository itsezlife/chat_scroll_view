import 'dart:ui' show Rect;

import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/draft_options/draft_link_part.dart';
import 'package:chat_composer/src/draft_options/draft_options_host.dart';
import 'package:chat_composer/src/draft_options/draft_options_policy.dart';
import 'package:chat_composer/src/draft_options/overlay_op.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// What closed the draft options overlay, as its `closed` event names it.
enum DraftOptionsCloseTrigger {
  /// A press outside the overlay's surface.
  outside,

  /// The system back.
  back,

  /// The Escape key.
  escape,

  /// Apply, under live apply: the edits were already reported.
  apply,

  /// Save, under commit on save: the copy was reported.
  save,

  /// Cancel.
  cancel,

  /// The remove row: the preview was removed.
  remove,

  /// Link previews became denied while the overlay was up.
  denied,

  /// The overlay's owner went away.
  disposed,
}

/// One open of the draft options overlay: the value it edits, when edits
/// reach the host, and how it closes.
///
/// Headless: no widgets. A `DraftOptionsController` opens one per overlay
/// and its skin calls [edit], [apply] and [cancel]; a host drawing its own
/// overlay may open one itself. Under [DraftOptionsApply.liveApply] each
/// edit is reported to the [DraftOptionsHost] at once and [apply] only
/// closes; under [DraftOptionsApply.commitOnSave] edits stay in a copy until
/// [apply] saves it, and every other close discards it.
///
/// A session closes once: the first close wins, and edits after it are
/// dropped, so a burst of taps on a row applies nothing while the close
/// runs.
final class DraftOptionsSession {
  /// Opens a session of [policy] on [part], from the host's [initial] value
  /// and the link's [page], and emits `opened`.
  ///
  /// [onClose] is told the trigger of the one close, after its events; the
  /// skin takes the overlay away with it. [correlation] gives the ids of the
  /// events (the chat); [keyboardWasUp] is reported with `opened`.
  DraftOptionsSession({
    required this.policy,
    required DraftOptionsHost host,
    required this.part,
    required DraftLinkPart initial,
    required LinkPreviewState page,
    required ValueChanged<DraftOptionsCloseTrigger> onClose,
    this.origin,
    ComposerClock clock = ComposerClock.system,
    bool keyboardWasUp = false,
    ChatCorrelation Function()? correlation,
  }) : _host = host,
       _onClose = onClose,
       _clock = clock,
       _correlation = correlation,
       _reported = initial,
       _value = ValueNotifier(initial),
       _page = ValueNotifier(page),
       _openedAt = clock.now() {
    _emit(
      ChatEventLevel.info,
      OverlayOp.opened,
      () => {
        'presentation': policy.presentation.name,
        'part': part.name,
        'page': _pageName(page),
        'apply': policy.apply.name,
        'keyboardWasUp': keyboardWasUp,
      },
    );
  }

  /// The policy the session follows.
  final DraftOptionsPolicy policy;

  /// The part the overlay opened at.
  final DraftPart part;

  /// The strip's global rect the overlay opened from, where its
  /// presentation grows from the strip and back; null when it opened from
  /// elsewhere.
  final Rect? origin;

  final DraftOptionsHost _host;
  final ValueChanged<DraftOptionsCloseTrigger> _onClose;
  final ComposerClock _clock;
  final ChatCorrelation Function()? _correlation;
  final ValueNotifier<DraftLinkPart> _value;
  final ValueNotifier<LinkPreviewState> _page;
  final DateTime _openedAt;
  // What the host was last told: the value a denial removes the preview of.
  DraftLinkPart _reported;
  // The fields edited since the last report, in order, for the save's events.
  final List<DraftOptionsField> _unsaved = [];
  int _edits = 0;
  DraftOptionsCloseTrigger? _closedBy;

  /// The link part as the overlay shows it.
  ValueListenable<DraftLinkPart> get value => _value;

  /// Where the link's page stands.
  ValueListenable<LinkPreviewState> get page => _page;

  /// Whether the session has closed: it takes no more edits.
  bool get isClosing => _closedBy != null;

  bool get _live => policy.apply == DraftOptionsApply.liveApply;

  /// The link's page moved to [state].
  set pageState(LinkPreviewState state) => _page.value = state;

  /// The user changed [field], making the part [next].
  void edit(DraftLinkPart next, {required DraftOptionsField field}) {
    if (isClosing || next == _value.value) return;
    _value.value = next;
    _edits++;
    if (_live) {
      _report(next, [field]);
    } else if (!_unsaved.contains(field)) {
      _unsaved.add(field);
    }
  }

  /// Apply under live apply (closes), save under commit on save (reports
  /// the copy, then closes).
  void apply() {
    if (isClosing) return;
    if (_live) {
      close(DraftOptionsCloseTrigger.apply);
      return;
    }
    if (_unsaved.isNotEmpty) _report(_value.value, _unsaved);
    close(DraftOptionsCloseTrigger.save);
  }

  /// Cancel: under commit on save the copy is discarded; under live apply
  /// the edits were reported already and only the overlay closes.
  void cancel() => close(DraftOptionsCloseTrigger.cancel);

  /// Closes the session by [trigger]. Under commit on save anything but a
  /// save discards the copy. Further calls do nothing.
  void close(DraftOptionsCloseTrigger trigger) {
    if (isClosing) return;
    _closedBy = trigger;
    final committed = _live
        ? _edits > 0
        : trigger == DraftOptionsCloseTrigger.save && _edits > 0;
    if (!_live &&
        trigger != DraftOptionsCloseTrigger.save &&
        _unsaved.isNotEmpty) {
      final discarded = _edits;
      _emit(
        ChatEventLevel.debug,
        OverlayOp.editsDiscarded,
        () => {'edits': discarded},
      );
    }
    final openMs = _clock.now().difference(_openedAt).inMilliseconds;
    _emit(
      ChatEventLevel.info,
      OverlayOp.closed,
      () => {
        'trigger': trigger.name,
        'openMs': openMs,
        'edits': _edits,
        'committed': committed,
      },
    );
    _onClose(trigger);
  }

  /// Reports the host's value with the preview removed: link previews were
  /// denied while the overlay was up, and it has closed.
  void reportRemoved() {
    final options = _reported.options;
    if (options.removed) return;
    _report(_reported.copyWith(options: options.copyWith(removed: true)), [
      DraftOptionsField.remove,
    ]);
  }

  /// Lets go of the listenables; called by the session's owner once the
  /// overlay is gone.
  void dispose() {
    _value.dispose();
    _page.dispose();
  }

  void _report(DraftLinkPart part, List<DraftOptionsField> fields) {
    _reported = part;
    final mode = _live || isClosing ? 'live' : 'onSave';
    for (final field in List.of(fields)) {
      _emit(
        ChatEventLevel.debug,
        OverlayOp.editReported,
        () => {'field': field.name, 'mode': mode},
      );
    }
    _unsaved.clear();
    _host.linkPartEdited(part);
  }

  void _emit(
    ChatEventLevel level,
    OverlayOp op,
    Map<String, Object> Function() fields,
  ) => ChatDiagnostics.current.emit(
    level,
    ChatEventCategory.overlay,
    op,
    correlation: _correlation?.call() ?? ChatCorrelation.none,
    fields: fields,
  );

  static String _pageName(LinkPreviewState page) => switch (page) {
    LinkPreviewState$Pending() => 'pending',
    LinkPreviewState$Loaded() => 'loaded',
    LinkPreviewState$None() => 'none',
  };
}
