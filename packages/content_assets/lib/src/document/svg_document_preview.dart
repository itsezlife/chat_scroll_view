import 'dart:math' as math;

import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mpx_core/mpx_core.dart';

/// When an SVG sent as a **document** shows a preview, and how it is drawn.
///
/// The message stays a document (a file the user can save or open); this
/// gives its row a picture of the drawing in place of the file icon. The
/// rules:
///
/// | Rule | Value |
/// | --- | --- |
/// | What counts as SVG | the type `image/svg+xml` (any case, with parameters), else a name ending in `.svg` |
/// | Bytes read | the document itself, held to the host's SVG decoder's limits and sanitizer; larger than [maxInputBytes] and it is not tried |
/// | Never downloaded for it | the preview is drawn only from bytes already here (cached, or the user's download of the file): [localOnly] answers manual for [downloadContext] |
/// | Size | the thumbnail's pixels, never more than [maxEdge] on an edge |
///
/// Behaviour without widgets: a host's document row attaches
/// [descriptorOf]'s content with [presetOf] and [downloadContext], through
/// the content views it already has (`ContentAssetView`). Whether previews
/// show at all is the host's policy: a host that wants none uses none of
/// this, and its rows keep their icons.
@immutable
final class SvgDocumentPreview {
  /// Creates the rules; the defaults are the reference limits.
  const SvgDocumentPreview({
    this.maxInputBytes = 1024 * 1024,
    this.maxEdge = 960,
  }) : assert(maxInputBytes > 0 && maxEdge > 0, 'Caps must be positive.');

  /// The largest document, in bytes, a preview is tried for. Keep it at or
  /// under the SVG decoder's own input cap: a larger one would fail there.
  final int maxInputBytes;

  /// The longest edge, in pixels, a preview is drawn at.
  final int maxEdge;

  /// The tag a preview attaches with. Pass the host's download policy
  /// through [localOnly], so the tag never downloads.
  static const AutoDownloadContext downloadContext = AutoDownloadContext(
    _SvgDocumentPreviewTag(),
  );

  /// Whether a document of [mimeType] named [name] is an SVG image. The type
  /// decides when it is given; the name only when there is none.
  static bool isSvg({String? mimeType, String? name}) {
    final type = mimeType?.split(';').first.trim().toLowerCase();
    if (type != null && type.isNotEmpty) return type == 'image/svg+xml';
    return name?.toLowerCase().endsWith('.svg') ?? false;
  }

  /// What the preview of [document] draws: the document as a vector image
  /// under its own key. Null when it is not SVG, or when its [byteSize] is
  /// known to pass [maxInputBytes].
  ContentDescriptor? descriptorOf(
    ContentKey document, {
    String? mimeType,
    String? name,
    int? byteSize,
  }) {
    if (!isSvg(mimeType: mimeType, name: name)) return null;
    if (byteSize != null && byteSize > maxInputBytes) return null;
    return ContentDescriptor(
      key: document,
      semanticKind: SemanticKind.unknown,
      mediaForm: MediaForm.vectorImage,
      byteSize: byteSize,
      spokenName: name,
    );
  }

  /// The preset of a square thumbnail [extent] logical pixels wide at
  /// [devicePixelRatio]: the drawing fills it (cropped like a photo's
  /// thumbnail), decoded at its pixels up to [maxEdge].
  AssetPreset presetOf({
    required double extent,
    required double devicePixelRatio,
  }) {
    final pixels = math.min((extent * devicePixelRatio).ceil(), maxEdge);
    return AssetPreset(
      size: Size.square(extent),
      spec: AssetSpec(pixelWidth: pixels, pixelHeight: pixels),
      profile: const AssetProfile(fit: AssetFit.cover),
    );
  }

  /// [policy], except that content attached with [downloadContext] never
  /// downloads by itself: a preview shows only what is already here. A user's
  /// download of the document still fetches it, and the preview follows.
  static AutoDownloadPolicy localOnly(AutoDownloadPolicy policy) =>
      _LocalOnly(policy);

  @override
  bool operator ==(Object other) =>
      other is SvgDocumentPreview &&
      other.maxInputBytes == maxInputBytes &&
      other.maxEdge == maxEdge;

  @override
  int get hashCode => Object.hash(maxInputBytes, maxEdge);

  @override
  String toString() =>
      'SvgDocumentPreview(input $maxInputBytes B, edge $maxEdge px)';
}

final class _SvgDocumentPreviewTag {
  const _SvgDocumentPreviewTag();

  @override
  String toString() => 'svgDocumentPreview';
}

final class _LocalOnly implements AutoDownloadPolicy {
  const _LocalOnly(this._policy);

  final AutoDownloadPolicy _policy;

  @override
  AutoDownload decide(
    MediaDescriptor descriptor,
    AutoDownloadContext? context,
  ) => context == SvgDocumentPreview.downloadContext
      ? AutoDownload.manual
      : _policy.decide(descriptor, context);

  @override
  AutoDownloadContext? get defaultContext => _policy.defaultContext;

  @override
  Listenable get changes => _policy.changes;
}
