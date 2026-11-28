import 'package:chat_composer/chat_composer.dart';

/// A [DraftOptionsHost] that keeps every report, for tests of what the
/// draft options overlay hands its host.
final class RecordingDraftOptionsHost implements DraftOptionsHost {
  final List<DraftLinkPart> _edits = [];

  /// Every link part reported, oldest first.
  List<DraftLinkPart> get edits => List.unmodifiable(_edits);

  @override
  void linkPartEdited(DraftLinkPart part) => _edits.add(part);
}
