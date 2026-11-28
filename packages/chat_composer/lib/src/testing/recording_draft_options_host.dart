import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// A [DraftOptionsHost] that keeps every report, for tests of what the
/// draft options overlay hands its host.
///
/// A chosen link is looked up through [resolver], alone, the way a host
/// re-asks its own; without one the lookup stays pending.
final class RecordingDraftOptionsHost implements DraftOptionsHost {
  /// A host looking chosen links up through [resolver].
  RecordingDraftOptionsHost({this.resolver});

  /// Where a chosen link is looked up; null leaves every lookup pending.
  final LinkPreviewResolver? resolver;

  final List<DraftLinkPart> _edits = [];
  final List<Uri> _chosen = [];

  /// Every link part reported, oldest first.
  List<DraftLinkPart> get edits => List.unmodifiable(_edits);

  /// Every link chosen, oldest first.
  List<Uri> get chosenLinks => List.unmodifiable(_chosen);

  @override
  void linkPartEdited(DraftLinkPart part) => _edits.add(part);

  @override
  listen.ValueListenable<LinkPreviewState> chooseLink(Uri url) {
    _chosen.add(url);
    return switch (resolver) {
      final resolver? => resolver.resolve([url]),
      null => LinkPreviewCompleter().request,
    };
  }
}
