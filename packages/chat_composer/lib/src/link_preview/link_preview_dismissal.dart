import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// What the cross on the composer's link preview strip turns off, and what
/// turns it on again.
enum LinkPreviewDismissalPolicy {
  /// The cross turns link preview search off for the whole field, until a
  /// deletion of more than one character, an insertion of more than two, an
  /// empty field or a send. The Android default.
  fieldUntilBigEdit,

  /// The cross disables the URL it showed; the text's other links still
  /// preview. The disabled set lasts until a send (and is kept in the
  /// draft). The iOS default.
  perUrl,

  /// The cross removes the preview until the text has no link at all, or a
  /// send. The desktop default.
  untilNoLinks;

  /// The default of [platform].
  ///
  /// The web is not desktop: a web composer takes the mobile form of the
  /// browser's family, [perUrl] for an iOS browser and [fieldUntilBigEdit]
  /// for any other. A host may pass one policy for every platform instead.
  static LinkPreviewDismissalPolicy forPlatform(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    if (isWeb)
      return platform == TargetPlatform.iOS ? perUrl : fieldUntilBigEdit;
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.fuchsia => fieldUntilBigEdit,
      TargetPlatform.iOS => perUrl,
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => untilNoLinks,
    };
  }
}

/// The operations of the `linkPreview` diagnostics events
/// [LinkPreviewDismissal] emits through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum LinkPreviewDismissalOp implements DiagnosticOp {
  /// The strip's cross was taken (info): the `policy` and the `scope`,
  /// `field` for a policy that turns the whole field off, else the
  /// disabled URL's host (never its path, query or fragment).
  dismissed,

  /// A dismissal ended (debug): the `policy` and the `trigger`, one of
  /// `bigEdit`, `empty`, `send` or `noLinks`. Not emitted when there was
  /// nothing to reset.
  dismissalReset,
}

/// What a [LinkPreviewDismissal] has turned off, in a form a draft keeps.
///
/// Composer-only: it is stored with the draft and never sent. Only the field
/// its [policy] reads is set: [dismissed] for [LinkPreviewDismissalPolicy.
/// fieldUntilBigEdit] and [LinkPreviewDismissalPolicy.untilNoLinks],
/// [disabledUrls] for [LinkPreviewDismissalPolicy.perUrl].
@immutable
final class LinkPreviewDismissalState {
  /// A state of [policy].
  LinkPreviewDismissalState({
    required this.policy,
    this.dismissed = false,
    Set<Uri> disabledUrls = const {},
  }) : disabledUrls = Set.unmodifiable(disabledUrls);

  /// Nothing turned off, under [policy].
  const LinkPreviewDismissalState.clear(this.policy)
    : dismissed = false,
      disabledUrls = const {};

  /// The policy the state belongs to; a dismissal of another policy ignores
  /// it.
  final LinkPreviewDismissalPolicy policy;

  /// Whether search is off for the field.
  final bool dismissed;

  /// The URLs the user dismissed one by one.
  final Set<Uri> disabledUrls;

  /// Whether nothing is turned off: a draft leaves out a clear state.
  bool get isClear => !dismissed && disabledUrls.isEmpty;

  /// The JSON form: `{ policy, dismissed?, urls? }`, each field written only
  /// when set.
  Map<String, Object?> toJson() => {
    'policy': policy.name,
    if (dismissed) 'dismissed': true,
    if (disabledUrls.isNotEmpty)
      'urls': [for (final url in disabledUrls) url.toString()],
  };

  /// Reads [json] as [toJson] wrote it, or null when it is not a state: not
  /// a map, or no known `policy`. A URL that is not an absolute string is
  /// skipped.
  static LinkPreviewDismissalState? fromJson(Object? json) {
    if (json case {'policy': final String name}) {
      final policy = LinkPreviewDismissalPolicy.values.asNameMap()[name];
      if (policy == null) return null;
      return LinkPreviewDismissalState(
        policy: policy,
        dismissed: json['dismissed'] == true,
        disabledUrls: {
          if (json['urls'] case final List<Object?> urls)
            for (final url in urls)
              if (url case final String text) ?_absolute(text),
        },
      );
    }
    return null;
  }

  static Uri? _absolute(String text) => switch (Uri.tryParse(text)) {
    final uri? when uri.isAbsolute => uri,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewDismissalState &&
      other.policy == policy &&
      other.dismissed == dismissed &&
      setEquals(other.disabledUrls, disabledUrls);

  @override
  int get hashCode =>
      Object.hash(policy, dismissed, Object.hashAllUnordered(disabledUrls));

  @override
  String toString() =>
      'LinkPreviewDismissalState(${policy.name}, dismissed: $dismissed, '
      '${disabledUrls.length} URLs)';
}

/// The dismissal of the composer's link preview: the strip's cross, its
/// [policy] and the state machine that decides when search comes back.
///
/// Headless: no widgets and no timers. The host's link preview watcher feeds
/// it every text edit ([edited]), the links of each reading of the text
/// ([linksRead]), the cross ([dismiss]) and a send ([sent]), and asks it
/// whether search is on ([searchEnabled]) and whether a URL may preview
/// ([allows]). Its [state] goes into the draft and comes back through
/// [restore] or the constructor.
///
/// Each input answers whether it changed what is turned off, so the watcher
/// knows when to read the text again or write the draft.
final class LinkPreviewDismissal {
  /// A dismissal under [policy], starting from [restored] when that is a
  /// state of the same policy. [correlation] gives the ids of its events
  /// (the chat).
  LinkPreviewDismissal({
    required this.policy,
    LinkPreviewDismissalState? restored,
    ChatCorrelation Function()? correlation,
  }) : _correlation = correlation {
    if (restored != null) restore(restored);
  }

  /// The rule this dismissal follows.
  final LinkPreviewDismissalPolicy policy;

  final ChatCorrelation Function()? _correlation;
  bool _dismissed = false;
  final Set<Uri> _disabled = {};

  /// Whether the watcher may look for a preview at all.
  bool get searchEnabled => !_dismissed;

  /// The URLs dismissed one by one ([LinkPreviewDismissalPolicy.perUrl]).
  Set<Uri> get disabledUrls => Set.unmodifiable(_disabled);

  /// Whether [url] may preview.
  bool allows(Uri url) => !_dismissed && !_disabled.contains(url);

  /// What is turned off now, for the draft.
  LinkPreviewDismissalState get state => LinkPreviewDismissalState(
    policy: policy,
    dismissed: _dismissed,
    disabledUrls: _disabled,
  );

  /// Takes [state] as the current one; a state of another policy clears.
  void restore(LinkPreviewDismissalState state) {
    _disabled.clear();
    _dismissed = false;
    if (state.policy != policy) return;
    _dismissed = state.dismissed;
    _disabled.addAll(state.disabledUrls);
  }

  /// The cross on the strip that showed [url].
  void dismiss(Uri url) {
    final String scope;
    switch (policy) {
      case LinkPreviewDismissalPolicy.perUrl:
        _disabled.add(url);
        scope = ChatEvent.clip(url.host);
      case LinkPreviewDismissalPolicy.fieldUntilBigEdit ||
          LinkPreviewDismissalPolicy.untilNoLinks:
        _dismissed = true;
        scope = 'field';
    }
    ChatDiagnostics.current.emit(
      ChatEventLevel.info,
      ChatEventCategory.linkPreview,
      LinkPreviewDismissalOp.dismissed,
      correlation: _correlation?.call() ?? ChatCorrelation.none,
      fields: () => {'policy': policy.name, 'scope': scope},
    );
  }

  /// One edit of the field's text, from [before] to [after]; true when it
  /// turned search on again.
  ///
  /// Only [LinkPreviewDismissalPolicy.fieldUntilBigEdit] reads edits. The
  /// sizes are measured in UTF-16 code units over the changed region (the
  /// text between the common prefix and suffix): more than one unit removed
  /// beyond what was inserted, or more than two inserted beyond what was
  /// removed, is a big edit. Typing a character, or replacing a word by one
  /// as long, is not.
  bool edited(String before, String after) {
    if (policy != LinkPreviewDismissalPolicy.fieldUntilBigEdit) return false;
    if (!_dismissed) return false;
    if (after.isEmpty) return _reset('empty');
    final (removed, inserted) = _changedRegion(before, after);
    if (removed > inserted + 1 || inserted - removed > 2) {
      return _reset('bigEdit');
    }
    return false;
  }

  /// The links a reading of the text found, in text order; true when it
  /// turned search on again.
  ///
  /// Only [LinkPreviewDismissalPolicy.untilNoLinks] reads them: a text with
  /// no link ends its dismissal.
  bool linksRead(List<Uri> links) {
    if (policy != LinkPreviewDismissalPolicy.untilNoLinks) return false;
    if (!_dismissed || links.isNotEmpty) return false;
    return _reset('noLinks');
  }

  /// The message was sent: every policy starts over. True when something was
  /// turned off.
  bool sent() {
    if (!_dismissed && _disabled.isEmpty) return false;
    return _reset('send');
  }

  bool _reset(String trigger) {
    _dismissed = false;
    _disabled.clear();
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.linkPreview,
      LinkPreviewDismissalOp.dismissalReset,
      correlation: _correlation?.call() ?? ChatCorrelation.none,
      fields: () => {'policy': policy.name, 'trigger': trigger},
    );
    return true;
  }

  /// How many code units an edit from [before] to [after] removed and
  /// inserted, outside their common prefix and suffix.
  static (int, int) _changedRegion(String before, String after) {
    final shorter = before.length < after.length ? before.length : after.length;
    var prefix = 0;
    while (prefix < shorter &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shorter - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }
    return (before.length - prefix - suffix, after.length - prefix - suffix);
  }
}
