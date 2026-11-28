import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:meta/meta.dart';

/// The one guard around a host-replaceable cell builder or chrome slot: a
/// build that throws is reported as `media` / `cellFailed` (error) with the
/// [MediaBuilder] and the error's type, the error goes to Flutter's error
/// reporting, and the fallback shows in its place.
@internal
abstract final class MediaBuildGuard {
  /// What [build] builds for [item]; on a throw, [fallback].
  static Widget run(
    MediaBuilder builder, {
    required MediaItem item,
    required ChatCorrelation correlation,
    required Widget Function() build,
    required Widget fallback,
  }) {
    try {
      return build();
    } on Object catch (error, stackTrace) {
      report(
        builder,
        itemId: item.id,
        item: item,
        correlation: correlation,
        errorType: error.runtimeType.toString(),
      );
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'message_media',
          context: ErrorDescription('while building a media ${builder.name}'),
        ),
      );
      return fallback;
    }
  }

  /// Reports [builder] failing for the item [itemId] ([item] where the view
  /// has it: a missing item has none) with [errorType].
  static void report(
    MediaBuilder builder, {
    required MediaItemId itemId,
    required ChatCorrelation correlation,
    required String errorType,
    MediaItem? item,
  }) => ChatDiagnostics.current.emit(
    ChatEventLevel.error,
    ChatEventCategory.media,
    MediaOp.cellFailed,
    correlation: ChatCorrelation(
      chatId: correlation.chatId,
      scrollId: correlation.scrollId,
      clientMessageId: correlation.clientMessageId,
      mediaItemId: itemId.toString(),
      mediaKey: item?.descriptor.key.mediaKey.encoded,
    ),
    fields: () => {'builder': builder, 'errorType': ChatEvent.clip(errorType)},
  );
}
