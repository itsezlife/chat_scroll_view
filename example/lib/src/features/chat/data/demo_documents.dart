import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/document_embed.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// One document of [DemoDocuments]: a file in the app bundle, sent in a
/// message as a document.
@immutable
final class DemoDocument implements BundledItem {
  const DemoDocument._(this.id, this.name, this.mimeType, this.byteSize);

  /// The id a message names it by (`![name](file:id)`).
  final String id;

  /// The file name its row shows.
  final String name;

  /// Its media type.
  final String mimeType;

  /// Its size in bytes, as the server would say.
  final int byteSize;

  @override
  ContentKey get key => ContentKey.document('demo-doc:$id');

  /// What its row shows.
  ChatDocument get document => ChatDocument(
    key: key,
    name: name,
    mimeType: mimeType,
    byteSize: byteSize,
  );

  /// A drawing the host previews is described as one (a vector image under
  /// the document's key); any other document as a file the pipeline never
  /// decodes.
  @override
  ContentDescriptor get descriptor =>
      DemoDocuments.previews.descriptorOf(
        key,
        mimeType: mimeType,
        name: name,
        byteSize: byteSize,
      ) ??
      ContentDescriptor(
        key: key,
        semanticKind: SemanticKind.unknown,
        mediaForm: MediaForm.unknown,
        byteSize: byteSize,
        spokenName: name,
      );

  @override
  String get assetPath => 'assets/documents/$name';
}

/// The documents the demo's conversations send, standing in for files a
/// backend serves: bundled, so their bytes are already here, as a file the
/// user sent or downloaded is.
abstract final class DemoDocuments {
  /// The host's policy for SVG document previews: on, with the reference
  /// limits. A host that wants none passes null for its body host's
  /// `documentPreviews`, and every document keeps its file icon.
  static const SvgDocumentPreview previews = SvgDocumentPreview();

  /// The documents, by id.
  static const List<DemoDocument> all = [
    DemoDocument._('diagram', 'diagram.svg', 'image/svg+xml', 451),
    DemoDocument._('notes', 'notes.txt', 'text/plain', 74),
  ];

  static final Map<String, DemoDocument> _byId = {
    for (final document in all) document.id: document,
  };

  static final Map<ContentKey, DemoDocument> _byKey = {
    for (final document in all) document.key: document,
  };

  /// What a row of [id] shows, or null for an id that is not the demo's.
  static ChatDocument? document(String id) => _byId[id]?.document;

  /// The document of [key], or null for content that is not one.
  static DemoDocument? of(ContentKey key) => _byKey[key];

  /// The descriptor of every document, for the host's asset pipeline.
  static Iterable<ContentDescriptor> get descriptors =>
      all.map((document) => document.descriptor);

  /// The body of a message that sends [id] as a document.
  static String bodyOf(String id) {
    final document = _byId[id]!;
    return '![${document.name}](${DocumentEmbedResolver.scheme}:$id)';
  }
}
