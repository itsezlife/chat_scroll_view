import 'dart:ui' show Path, Rect;

import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/draft_options/draft_link_part.dart';
import 'package:chat_composer/src/draft_options/draft_options_host.dart';
import 'package:chat_composer/src/draft_options/draft_options_policy.dart';
import 'package:chat_composer/src/draft_options/overlay_op.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:listen/listen.dart' as listen;

/// The chosen link as the overlay marks it above the live preview: the
/// link's [index] among the text's links, its [contour] in the bubble's
/// coordinates and whether its page is still [pending] (a spinner shows).
@immutable
final class DraftLinkHighlight {
  /// The highlight of link [index], outlined by [contour].
  const DraftLinkHighlight({
    required this.index,
    required this.contour,
    required this.pending,
  });

  /// Which of the text's links, in text order.
  final int index;

  /// The outline of the link's text, from the bubble's inline hit.
  final Path contour;

  /// Whether the link's page is still being looked up.
  final bool pending;

  @override
  bool operator ==(Object other) =>
      other is DraftLinkHighlight &&
      other.index == index &&
      identical(other.contour, contour) &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(index, identityHashCode(contour), pending);

  @override
  String toString() =>
      'DraftLinkHighlight($index${pending ? ', pending' : ''})';
}

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

/// Why a link tap in the live preview chose nothing, as its
/// `linkTapIgnored` event names it.
enum DraftLinkTapIgnored {
  /// The text has one link and the policy chooses only among several.
  singleLink,

  /// The tapped link is not one of the text's links.
  notInText,

  /// The tapped link is the one previewed already.
  current,
}

/// A motion of the draft options overlay's presentation, as its `motion`
/// event names it.
enum DraftOptionsMotionPhase {
  /// The overlay coming in.
  open,

  /// The overlay going.
  close,

  /// The presentation following a changed preview.
  change,
}

/// What the draft options overlay says politely about its link's page, as
/// its `announced` event names it.
enum DraftOptionsAnnouncement {
  /// The page is being looked up: on an open on a pending page, and when a
  /// chosen link's lookup starts.
  loadingPreview,

  /// A page announced as loading has loaded.
  loaded,
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
///
/// ## Choosing another link
///
/// [tapLink] is the live preview's link tap. When the policy lets the tap
/// choose ([DraftOptionsPolicy.linkChoice]), the url is edited like any
/// other field, the host is asked for that link's page
/// ([DraftOptionsHost.chooseLink]) and [highlight] marks the link while the
/// lookup is pending; the page follows the lookup, and the highlight goes at
/// loaded or none (kept, settled, on loaded under
/// [DraftOptionsOverlayPolicy.keepsChosenLinkSelected]). A newer choice drops the
/// older lookup: its late answer changes nothing.
///
/// ## Announcements
///
/// [announcement] is what a screen reader should be told about the page, by
/// its transitions: [DraftOptionsAnnouncement.loadingPreview] when the page
/// becomes pending (or the overlay opens on a pending page) and
/// [DraftOptionsAnnouncement.loaded] when that page loads. A page that comes
/// to nothing says nothing more, and a page already loaded says nothing.
/// The skin speaks each value as it is set, from the chrome strings.
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
    List<Uri> links = const [],
    ComposerClock clock = ComposerClock.system,
    bool keyboardWasUp = false,
    ChatCorrelation Function()? correlation,
  }) : _host = host,
       _onClose = onClose,
       _clock = clock,
       _correlation = correlation,
       links = List.unmodifiable(links),
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
    if (page case LinkPreviewState$Pending()) {
      _announce(DraftOptionsAnnouncement.loadingPreview);
    }
  }

  /// The policy the session follows.
  final DraftOptionsPolicy policy;

  /// The part the overlay opened at.
  final DraftPart part;

  /// The strip's global rect the overlay opened from, where its
  /// presentation grows from the strip and back; null when it opened from
  /// elsewhere.
  final Rect? origin;

  /// The links of the draft's text, in text order: what a link tap may
  /// choose among. Events name a link by its index here, never its URL.
  final List<Uri> links;

  final DraftOptionsHost _host;
  final ValueChanged<DraftOptionsCloseTrigger> _onClose;
  final ComposerClock _clock;
  final ChatCorrelation Function()? _correlation;
  final ValueNotifier<DraftLinkPart> _value;
  final ValueNotifier<LinkPreviewState> _page;
  final ValueNotifier<DraftLinkHighlight?> _highlight = ValueNotifier(null);
  final ValueNotifier<DraftOptionsAnnouncement?> _announcement = ValueNotifier(
    null,
  );
  final DateTime _openedAt;
  // The chosen link's lookup while it is followed, and when it was tapped.
  listen.ValueListenable<LinkPreviewState>? _lookup;
  DateTime _tappedAt = DateTime(0);
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

  /// The chosen link's mark above the live preview, or null when none shows.
  ValueListenable<DraftLinkHighlight?> get highlight => _highlight;

  /// The latest announcement about the page, or null since the page came to
  /// nothing (or while nothing was announced); see the class's
  /// *Announcements*.
  ValueListenable<DraftOptionsAnnouncement?> get announcement => _announcement;

  /// Whether the session has closed: it takes no more edits.
  bool get isClosing => _closedBy != null;

  bool get _live => policy.apply == DraftOptionsApply.liveApply;

  // The web's menu has no preview, so nothing there is ever selected.
  bool get _keepsChosenLinkSelected => switch (policy) {
    DraftOptionsOverlayPolicy(:final keepsChosenLinkSelected) =>
      keepsChosenLinkSelected,
    DraftOptionsPolicy$Web() => false,
  };

  /// The link's page moved to [state].
  set pageState(LinkPreviewState state) => _setPage(state);

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

  /// A link of the preview's text was tapped: [url] as the text spells it,
  /// [contourPath] its outline in the bubble.
  ///
  /// Chooses it when it is one of [links], the policy allows a choice with
  /// this many links, and it is not the link previewed already; otherwise
  /// the tap is reported ignored. A tap on the previewed link marks it
  /// selected under [DraftOptionsOverlayPolicy.keepsChosenLinkSelected], and a
  /// burst of taps on one link asks the host once.
  void tapLink(String url, Path contourPath) {
    if (isClosing) return;
    final index = switch (Uri.tryParse(url)) {
      final uri? => links.indexOf(uri),
      null => -1,
    };
    final ignored = switch (index) {
      _
          when policy.linkChoice == DraftOptionsLinkChoice.severalLinks &&
              links.length < 2 =>
        DraftLinkTapIgnored.singleLink,
      < 0 => DraftLinkTapIgnored.notInText,
      _ when links[index] == _value.value.options.url =>
        DraftLinkTapIgnored.current,
      _ => null,
    };
    if (ignored case final why?) {
      if (why == DraftLinkTapIgnored.current &&
          _keepsChosenLinkSelected &&
          _highlight.value == null) {
        _highlight.value = DraftLinkHighlight(
          index: index,
          contour: contourPath,
          pending: false,
        );
      }
      _emit(
        ChatEventLevel.debug,
        OverlayOp.linkTapIgnored,
        () => {'why': why.name},
      );
      return;
    }
    final chosen = links[index];
    final count = links.length;
    _emit(
      ChatEventLevel.debug,
      OverlayOp.linkTapped,
      () => {'index': index, 'count': count},
    );
    _tappedAt = _clock.now();
    _unfollow();
    final current = _value.value;
    edit(
      current.copyWith(options: current.options.copyWith(url: chosen)),
      field: DraftOptionsField.link,
    );
    _highlight.value = DraftLinkHighlight(
      index: index,
      contour: contourPath,
      pending: true,
    );
    final lookup = _lookup = _host.chooseLink(chosen)..addListener(_onLookup);
    _follow(lookup.value);
  }

  /// Apply under live apply (closes), save under commit on save (reports
  /// the copy, then closes).
  void apply() {
    if (isClosing) return;
    if (_live) {
      close(DraftOptionsCloseTrigger.apply);
      return;
    }
    close(DraftOptionsCloseTrigger.save);
  }

  /// Cancel: under commit on save the copy is discarded; under live apply
  /// the edits were reported already and only the overlay closes.
  void cancel() => close(DraftOptionsCloseTrigger.cancel);

  /// Closes the session by [trigger]. Under commit on save a save and a
  /// remove report the copy (a removed preview is the user's choice, made
  /// at once); anything else discards it. Further calls do nothing.
  void close(DraftOptionsCloseTrigger trigger) {
    if (isClosing) return;
    final commits =
        trigger == DraftOptionsCloseTrigger.save ||
        trigger == DraftOptionsCloseTrigger.remove;
    if (!_live && commits && _unsaved.isNotEmpty) {
      _report(_value.value, _unsaved);
    }
    _closedBy = trigger;
    final committed = _live ? _edits > 0 : commits && _edits > 0;
    if (!_live && !commits && _unsaved.isNotEmpty) {
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

  /// The skin started the [phase] motion of the overlay's presentation,
  /// lasting [duration] at the chrome motion speed; [reduceMotion] when the
  /// speed collapsed it to its end state.
  void reportMotion(
    DraftOptionsMotionPhase phase,
    Duration duration, {
    required bool reduceMotion,
  }) => _emit(
    ChatEventLevel.trace,
    OverlayOp.motion,
    () => {
      'presentation': policy.presentation.name,
      'phase': phase.name,
      'durationMs': duration.inMilliseconds,
      'reduceMotion': reduceMotion,
    },
  );

  /// Reports the host's value with the preview removed as a denial
  /// ([DraftOptionsHost.previewDenied]): link previews were denied while the
  /// overlay was up, and it has closed. Emits `editReported` for `remove`.
  void reportRemoved() {
    final options = _reported.options;
    if (options.removed) return;
    final denied = _reported.copyWith(options: options.copyWith(removed: true));
    _reported = denied;
    _emitReported(DraftOptionsField.remove);
    _host.previewDenied(denied);
  }

  /// Lets go of the listenables; called by the session's owner once the
  /// overlay is gone.
  void dispose() {
    _unfollow();
    _value.dispose();
    _page.dispose();
    _highlight.dispose();
    _announcement.dispose();
  }

  // The page moves to [state]; a change of its kind is announced.
  void _setPage(LinkPreviewState state) {
    final was = _page.value;
    _page.value = state;
    switch ((was, state)) {
      case (LinkPreviewState$Pending(), LinkPreviewState$Pending()):
        break;
      case (_, LinkPreviewState$Pending()):
        _announce(DraftOptionsAnnouncement.loadingPreview);
      case (LinkPreviewState$Pending(), LinkPreviewState$Loaded()):
        _announce(DraftOptionsAnnouncement.loaded);
      case (_, LinkPreviewState$None()):
        _announcement.value = null;
      case _:
        break;
    }
  }

  void _announce(DraftOptionsAnnouncement kind) {
    // Never the same value twice in a row: a page only loads after it was
    // pending, and comes back to pending only from another state.
    _announcement.value = kind;
    _emit(ChatEventLevel.trace, OverlayOp.announced, () => {'kind': kind.name});
  }

  void _onLookup() {
    if (_lookup case final lookup?) _follow(lookup.value);
  }

  void _follow(LinkPreviewState state) {
    final ms = _clock.now().difference(_tappedAt).inMilliseconds;
    _emit(
      ChatEventLevel.debug,
      OverlayOp.linkState,
      () => {'state': _pageName(state), 'ms': ms},
    );
    _setPage(state);
    if (!state.isTerminal) return;
    _unfollow();
    _highlight.value = switch ((state, _highlight.value)) {
      (LinkPreviewState$Loaded(), final shown?) when _keepsChosenLinkSelected =>
        DraftLinkHighlight(
          index: shown.index,
          contour: shown.contour,
          pending: false,
        ),
      _ => null,
    };
  }

  void _unfollow() {
    _lookup?.removeListener(_onLookup);
    _lookup = null;
  }

  void _report(DraftLinkPart part, List<DraftOptionsField> fields) {
    _reported = part;
    List.of(fields).forEach(_emitReported);
    _unsaved.clear();
    _host.linkPartEdited(part);
  }

  void _emitReported(DraftOptionsField field) {
    final mode = _live || isClosing ? 'live' : 'onSave';
    _emit(
      ChatEventLevel.debug,
      OverlayOp.editReported,
      () => {'field': field.name, 'mode': mode},
    );
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
