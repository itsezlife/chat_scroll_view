import 'package:content_model/content_model.dart';

/// The demo's link preview resolver until a real one is wired: the page of
/// the first candidate is what its address says, and nothing more.
///
/// It fetches nothing, so it reveals nothing about the user to the linked
/// site; a host with a backend that has the pages, or that has decided to
/// fetch them itself, passes its own resolver.
final class AddressLinkPreviewResolver implements LinkPreviewResolver {
  /// The resolver.
  const AddressLinkPreviewResolver();

  @override
  LinkPreviewRequest resolve(List<Uri> candidates) {
    final completer = LinkPreviewCompleter();
    completer.complete(switch (candidates) {
      [final first, ...] => LinkPreview(url: first),
      [] => null,
    });
    return completer.request;
  }
}
