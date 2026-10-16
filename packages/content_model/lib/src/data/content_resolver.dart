import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/identity/content_key.dart';

/// Resolves bare [ContentKey]s into [ContentDescriptor]s.
///
/// The host implements it, because only the host can fetch what a key stands
/// for: a key found in message text, in recents, or in a deep link has no
/// facts attached until it is resolved. Resolution is batched so a screenful
/// of keys costs one request.
///
/// ## Results
///
/// [resolve] answers with a descriptor for every key it could resolve and
/// leaves out the rest: an unknown or deleted key is absent from the result,
/// not an error, and each returned descriptor's key equals the key it is
/// listed under. The result never holds keys that were not asked for. Repeated
/// keys in [keys] are resolved once. An empty request gives an empty result.
///
/// ## Failure and cancellation
///
/// The future fails when the batch as a whole could not be attempted, for
/// example with no connection; keys left out of a successful result were
/// attempted and are unknown. There is no cancellation: a caller that no
/// longer wants the result ignores it. Resolving again is always allowed.
abstract interface class ContentResolver {
  /// The descriptors of those [keys] that resolve.
  Future<Map<ContentKey, ContentDescriptor>> resolve(Iterable<ContentKey> keys);
}
