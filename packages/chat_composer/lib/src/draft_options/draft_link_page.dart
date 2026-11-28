import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/draft_options/draft_link_page_policy.dart';
import 'package:chat_composer/src/draft_options/draft_link_part.dart';
import 'package:chat_composer/src/draft_options/draft_options_session.dart';
import 'package:chat_composer/src/draft_options/overlay_op.dart';
import 'package:chat_composer/src/link_preview/link_preview_dismissal.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// A row of the link page.
enum DraftLinkRow {
  /// Moves the card above or below the text.
  position,

  /// Makes the page's media larger or smaller.
  size,

  /// Closes the overlay, the edits applied.
  apply,

  /// Drops the preview.
  remove,
}

/// What a row of the link page says, as the chrome strings name it.
enum DraftLinkLabel {
  /// The card is below the text; the tap moves it above.
  moveUp,

  /// The card is above the text; the tap moves it below.
  moveDown,

  /// The photo is small.
  enlargePhoto,

  /// The photo is large.
  shrinkPhoto,

  /// The video is small.
  enlargeVideo,

  /// The video is large.
  shrinkVideo,

  /// Closes, the changes applied.
  applyChanges,

  /// Drops the preview, worded as a refusal.
  doNotPreview,

  /// Drops the preview, worded as a removal.
  removePreview;

  /// This label in [strings].
  String of(DraftOptionsStrings strings) => switch (this) {
    moveUp => strings.moveUp,
    moveDown => strings.moveDown,
    enlargePhoto => strings.enlargePhoto,
    shrinkPhoto => strings.shrinkPhoto,
    enlargeVideo => strings.enlargeVideo,
    shrinkVideo => strings.shrinkVideo,
    applyChanges => strings.applyChanges,
    doNotPreview => strings.doNotPreview,
    removePreview => strings.removePreview,
  };
}

/// One row as the link page shows it now.
@immutable
final class DraftLinkRowState {
  /// A shown [row] saying [label] beside [icon]; [inert] when it takes no
  /// tap.
  const DraftLinkRowState({
    required this.row,
    required this.label,
    required this.icon,
    this.inert = false,
  });

  /// Which row.
  final DraftLinkRow row;

  /// What it says: the state its tap leads to, for a toggle.
  final DraftLinkLabel label;

  /// Its icon, the same state as [label].
  final ChromeIconId icon;

  /// Whether it is drawn faded and ignores a touch.
  final bool inert;

  @override
  bool operator ==(Object other) =>
      other is DraftLinkRowState &&
      other.row == row &&
      other.label == label &&
      other.icon == icon &&
      other.inert == inert;

  @override
  int get hashCode => Object.hash(row, label, icon, inert);

  @override
  String toString() =>
      'DraftLinkRowState(${row.name}, ${label.name}${inert ? ', inert' : ''})';
}

/// The kind of media a link's page shows.
enum DraftLinkMediaKind {
  /// No picture.
  none,

  /// A photo.
  photo,

  /// A playable picture: a video or an animation.
  video,
}

/// What the size row reads of a link's page: its media's [kind], whether
/// the small / large switch is offered for it ([shrinkable]) and whether it
/// shows [large] under the current options.
///
/// The size rule is the chat's media policy, which the composer does not
/// know; the host answers through a [DraftLinkMediaReader].
@immutable
final class DraftLinkMedia {
  /// Media facts of a page.
  const DraftLinkMedia({
    required this.kind,
    required this.shrinkable,
    required this.large,
  });

  /// A coarse reading for a host that gives no reader: a page's `media` is a
  /// video, else its photo a photo; either can shrink, and it shows large
  /// unless [options] ask for small. The chat's media policy knows better
  /// (a page too short of text never shows small, for one): a host passes
  /// its reading instead.
  factory DraftLinkMedia.of(LinkPreview page, LinkPreviewOptions options) {
    final kind = switch (page) {
      LinkPreview(media: _?) => DraftLinkMediaKind.video,
      LinkPreview(photo: _?) => DraftLinkMediaKind.photo,
      _ => DraftLinkMediaKind.none,
    };
    return DraftLinkMedia(
      kind: kind,
      shrinkable: kind != DraftLinkMediaKind.none,
      large:
          kind != DraftLinkMediaKind.none &&
          options.media != LinkPreviewMedia.small,
    );
  }

  /// A page with no media, or one not loaded yet.
  static const DraftLinkMedia none = DraftLinkMedia(
    kind: DraftLinkMediaKind.none,
    shrinkable: false,
    large: false,
  );

  /// The kind of the page's media.
  final DraftLinkMediaKind kind;

  /// Whether the media can be shown small or large: the size row's switch.
  final bool shrinkable;

  /// Whether the media shows large now.
  final bool large;

  @override
  bool operator ==(Object other) =>
      other is DraftLinkMedia &&
      other.kind == kind &&
      other.shrinkable == shrinkable &&
      other.large == large;

  @override
  int get hashCode => Object.hash(kind, shrinkable, large);
}

/// Reads [page]'s media under [options] the way the chat's media policy
/// sizes it.
typedef DraftLinkMediaReader =
    DraftLinkMedia Function(LinkPreview page, LinkPreviewOptions options);

/// The link page's rows over one [session]: which rows show, what they say,
/// and what a tap on each does.
///
/// Headless: no widgets. The overlay's skin draws [rows] and sends each tap
/// to [tap]; a host drawing its own page does the same. The rows follow the
/// session's value and page ([changes]).
///
/// - Position edits `invertMedia`.
/// - Size switches the media between large and small; on a page without
///   shrinkable media it is hidden or inert, as the policy says.
/// - Apply closes (live apply).
/// - Remove sets `removed`, applies [dismissal] to the previewed URL as the
///   strip's cross does, takes the next link the dismissal still allows
///   where the policy falls back, and closes with the edits reported.
///
/// A tap within the policy's row guard of the accepted one is dropped, and
/// no tap acts once the session is closing.
final class DraftLinkPage {
  /// The link page of [session]. [hasText] is whether the draft has text;
  /// [dismissal] is the composer's, the one the strip's cross applies;
  /// [mediaOf] the host's media reading, [DraftLinkMedia.of] when null.
  DraftLinkPage({
    required this.session,
    this.hasText = true,
    this.dismissal,
    DraftLinkMediaReader? mediaOf,
    ComposerClock clock = ComposerClock.system,
    ChatCorrelation Function()? correlation,
  }) : _mediaOf = mediaOf ?? DraftLinkMedia.of,
       _clock = clock,
       _correlation = correlation;

  /// The open the rows edit.
  final DraftOptionsSession session;

  /// Whether the draft has text beside its link preview.
  final bool hasText;

  /// What the remove row turns off, as the strip's cross does; null when the
  /// host keeps no dismissal.
  final LinkPreviewDismissal? dismissal;

  final DraftLinkMediaReader _mediaOf;
  final ComposerClock _clock;
  final ChatCorrelation Function()? _correlation;
  DateTime? _acceptedAt;

  /// The page's rules.
  DraftLinkPagePolicy get policy => session.policy.linkPage;

  /// Notifies when [rows] may have changed.
  Listenable get changes => Listenable.merge([session.value, session.page]);

  /// The media of the page as it stands.
  DraftLinkMedia get media => switch (session.page.value) {
    LinkPreviewState$Loaded(:final page) => _mediaOf(
      page,
      session.value.value.options,
    ),
    _ => DraftLinkMedia.none,
  };

  /// Whether a hint says a link of the preview can be chosen.
  bool get showsLinkHint => policy.linkHint && session.links.length > 1;

  /// The rows shown now, top to bottom.
  List<DraftLinkRowState> get rows {
    final policy = this.policy;
    final part = session.value.value;
    return [
      if (hasText || !policy.positionNeedsText)
        part.invertMedia
            ? const DraftLinkRowState(
                row: DraftLinkRow.position,
                label: DraftLinkLabel.moveDown,
                icon: ChromeIconId.moveDown,
              )
            : const DraftLinkRowState(
                row: DraftLinkRow.position,
                label: DraftLinkLabel.moveUp,
                icon: ChromeIconId.moveUp,
              ),
      ?_sizeRow(policy, media),
      if (policy.applyRow)
        const DraftLinkRowState(
          row: DraftLinkRow.apply,
          label: DraftLinkLabel.applyChanges,
          icon: ChromeIconId.confirm,
        ),
      DraftLinkRowState(
        row: DraftLinkRow.remove,
        label: switch (policy.removeLabel) {
          DraftLinkRemoveLabel.doNotPreview => DraftLinkLabel.doNotPreview,
          DraftLinkRemoveLabel.removePreview => DraftLinkLabel.removePreview,
        },
        icon: ChromeIconId.delete,
      ),
    ];
  }

  /// Whether [row] is drawn and takes taps now: shown and not inert.
  bool isLive(DraftLinkRow row) =>
      rows.any((shown) => shown.row == row && !shown.inert);

  /// A tap on [row].
  void tap(DraftLinkRow row) {
    final shown = rows.where((r) => r.row == row).firstOrNull;
    if (shown == null) return;
    if (shown.inert) {
      _emit(
        ChatEventLevel.debug,
        OverlayOp.rowInertTouch,
        () => {'row': row.name},
      );
      return;
    }
    final now = _clock.now();
    final sinceAccepted = switch (_acceptedAt) {
      final accepted? => now.difference(accepted),
      null => null,
    };
    final guarded = switch (sinceAccepted) {
      final since? => since < policy.rowGuard,
      null => false,
    };
    if (session.isClosing || guarded) {
      final ms = sinceAccepted?.inMilliseconds ?? 0;
      _emit(
        ChatEventLevel.debug,
        OverlayOp.rowDropped,
        () => {'row': row.name, 'ms': ms},
      );
      return;
    }
    _acceptedAt = now;
    final part = session.value.value;
    switch (row) {
      case DraftLinkRow.position:
        session.edit(
          part.copyWith(invertMedia: !part.invertMedia),
          field: DraftOptionsField.position,
        );
      case DraftLinkRow.size:
        session.edit(
          part.copyWith(
            options: part.options.copyWith(
              media: media.large
                  ? LinkPreviewMedia.small
                  : LinkPreviewMedia.large,
            ),
          ),
          field: DraftOptionsField.size,
        );
      case DraftLinkRow.apply:
        session.apply();
      case DraftLinkRow.remove:
        _remove(part);
    }
  }

  void _remove(DraftLinkPart part) {
    final url = part.options.url;
    session.edit(
      part.copyWith(options: part.options.copyWith(removed: true)),
      field: DraftOptionsField.remove,
    );
    dismissal?.dismiss(url);
    final next = policy.removeFallsBackToNextLink
        ? session.links
              .where((link) => link != url && (dismissal?.allows(link) ?? true))
              .firstOrNull
        : null;
    if (next != null) {
      session.edit(
        DraftLinkPart(
          options: LinkPreviewOptions(url: next),
          invertMedia: part.invertMedia,
        ),
        field: DraftOptionsField.link,
      );
    }
    final by = dismissal?.policy.name ?? 'none';
    _emit(
      ChatEventLevel.info,
      OverlayOp.removeApplied,
      () => {'dismissal': by, 'nextLink': next != null},
    );
    session.close(DraftOptionsCloseTrigger.remove);
  }

  DraftLinkRowState? _sizeRow(
    DraftLinkPagePolicy policy,
    DraftLinkMedia media,
  ) {
    final shown = switch (policy.sizeRow) {
      DraftLinkSizeRow.whenShrinkable => media.shrinkable,
      // Hidden only for a single link with no media at all: with several
      // links another may have media, so the row stays, inert.
      DraftLinkSizeRow.inertWithoutShrinkable =>
        media.kind != DraftLinkMediaKind.none || session.links.length > 1,
    };
    if (!shown) return null;
    final video = media.kind == DraftLinkMediaKind.video;
    final (label, icon) = switch ((media.large, video)) {
      (true, true) => (DraftLinkLabel.shrinkVideo, ChromeIconId.shrink),
      (true, false) => (DraftLinkLabel.shrinkPhoto, ChromeIconId.shrink),
      (false, true) => (DraftLinkLabel.enlargeVideo, ChromeIconId.enlarge),
      (false, false) => (DraftLinkLabel.enlargePhoto, ChromeIconId.enlarge),
    };
    return DraftLinkRowState(
      row: DraftLinkRow.size,
      label: label,
      icon: icon,
      inert: !media.shrinkable,
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
}
