import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart';

/// The operations of the `capabilities` diagnostics events the picker
/// emits through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names
/// are stable, since logs filter by them. The `denied` and
/// `denialTextMissing` events of the picker's attempts and texts are
/// `chat_capabilities`' own (`CapabilitiesOp`), emitted by its
/// `CapabilityFeedback`.
enum AttachOp implements DiagnosticOp {
  /// The picker's limits were derived from a chat's value (debug): the
  /// allowed attach kinds, grouping, single select, the caption, file and
  /// album limits and one-send mode.
  limitsDerived,

  /// The picker entered or left one-send mode (debug): `on`, and the album
  /// cap one send unit holds.
  pickerOneSend,
}

/// Where the picker draws a denial text in place, named in the
/// `denialTextMissing` event when the host gives none.
enum AttachDenialForm implements DenialForm {
  /// The gallery page that replaces the grid when photos and videos are
  /// both denied.
  galleryPage,

  /// The files page's content replaced by the text.
  filesPage,

  /// The files page's empty state with the text.
  filesEmptyState,
}
