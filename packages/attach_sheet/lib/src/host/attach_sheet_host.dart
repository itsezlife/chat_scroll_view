import 'package:attach_sheet/src/host/attach_discard_question.dart';
import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:flutter/widgets.dart';

/// What the host knew when it opened the sheet.
@immutable
final class AttachSheetOpening {
  /// An opening; [keyboardWasUp] when the host's keyboard was showing, and
  /// the attach button's [anchor] in the sheet's coordinates.
  const AttachSheetOpening({this.keyboardWasUp = false, this.anchor});

  /// Whether the keyboard was up when the attach button was pressed. The
  /// host parks it before opening; the sheet may ask for it back after it
  /// closes ([AttachSheetPolicy.keyboardReopenDelay]).
  final bool keyboardWasUp;

  /// The attach button's rect, which a card on a wide screen points at;
  /// null to centre the card at the bottom.
  final Rect? anchor;
}

/// The **attach sheet host** seam: what the sheet tells its host and asks
/// of it.
///
/// Not sealed and every member has a default, so a host overrides only what
/// it needs: [opened] and [closed] to park its input method and panel
/// presentation while the sheet is up, [restoreKeyboard] to raise the
/// keyboard again, and [confirmDiscard] to ask the discard question in its
/// own dialog.
base class AttachSheetHost {
  /// A host that does nothing on open and close and asks the stock
  /// question.
  const AttachSheetHost();

  /// The sheet started to open.
  void opened(AttachSheetOpening opening) {}

  /// The sheet finished closing.
  void closed(AttachSheetOpening opening) {}

  /// Raise the keyboard again: the sheet closed and the policy brings back
  /// a keyboard that was up at open.
  void restoreKeyboard() {}

  /// Ask whether to drop a non-empty selection, in [wording]; true drops it
  /// and closes the sheet. The default shows [AttachDiscardQuestion].
  Future<bool> confirmDiscard(
    BuildContext context,
    AttachDiscardWording wording,
  ) => AttachDiscardQuestion.show(context, wording);
}
