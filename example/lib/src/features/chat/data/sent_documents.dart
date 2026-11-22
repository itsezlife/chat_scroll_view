import 'package:attach_model/attach_model.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_documents.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/document_embed.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:mpx_core/mpx_core.dart';

/// The files the user sent as documents in this session: what each row
/// shows, and their bytes, read where the file is.
///
/// Stands in for the backend a host uploads to. The sender holds the file,
/// so its bytes are here: an SVG document's preview draws from them at once,
/// as the reference draws one from a file it has locally.
final class SentDocuments {
  /// Creates the registry; [know] tells the host's asset pipeline what each
  /// sent document is.
  SentDocuments({required void Function(ContentDescriptor descriptor) know})
    : _know = know;

  final void Function(ContentDescriptor descriptor) _know;
  final Map<String, ({ChatDocument document, String path})> _sent = {};
  final Map<MediaKey, String> _paths = {};

  /// Registers [item] as a sent document and returns the id its row names
  /// (`![name](file:id)`), or null for an item that is no file on disk (a
  /// web blob, a library asset): it stays a line naming it.
  String? register(AttachItem item) {
    final path = switch (item.source) {
      AttachSource$File(:final path) => path,
      _ => null,
    };
    if (item.kind != AttachKind.file || path == null) return null;
    final id = item.id.value;
    final document = ChatDocument(
      key: ContentKey.document('sent-doc:$id'),
      name: item.facts.name ?? id,
      mimeType: item.facts.mimeType,
      byteSize: item.facts.byteSize,
    );
    _sent[id] = (document: document, path: path);
    _paths[document.key.mediaKey] = path;
    _know(
      DemoDocuments.previews.descriptorOf(
            document.key,
            mimeType: document.mimeType,
            name: document.name,
            byteSize: document.byteSize,
          ) ??
          ContentDescriptor(
            key: document.key,
            semanticKind: SemanticKind.unknown,
            mediaForm: MediaForm.unknown,
            byteSize: document.byteSize,
            spokenName: document.name,
          ),
    );
    return id;
  }

  /// What the row of [id] shows, or null for an id never sent.
  ChatDocument? document(String id) => _sent[id]?.document;

  /// A fetcher that serves the sent documents from their files, in place,
  /// and hands every other request to [otherwise].
  ContentFetcher route(ContentFetcher otherwise) =>
      _SentRoute(_paths, otherwise);
}

final class _SentRoute implements ContentFetcher {
  _SentRoute(this._paths, this._otherwise);

  final Map<MediaKey, String> _paths;
  final ContentFetcher _otherwise;

  @override
  Future<FetchedContent> fetch(FetchRequest request) async =>
      switch ((request.part, _paths[request.descriptor.key])) {
        (FetchPart.content, final path?) => FetchedContent.file(path),
        _ => await _otherwise.fetch(request),
      };

  // The sender's own file is never a download.
  @override
  bool needsDownload(MediaKey key) =>
      !_paths.containsKey(key) && _otherwise.needsDownload(key);
}
