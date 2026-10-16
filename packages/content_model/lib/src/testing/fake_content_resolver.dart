import 'package:content_model/content_model.dart';

/// An in-memory [ContentResolver] for tests, resolving a fixed set of
/// descriptors.
///
/// Follows the whole seam contract. [requests] records each batch it was
/// asked for, so a test can check that a consumer batches; [failure] makes
/// every call fail, as a lost connection would.
final class FakeContentResolver implements ContentResolver {
  /// Creates a resolver that knows [descriptors].
  FakeContentResolver(Iterable<ContentDescriptor> descriptors)
    : _known = {for (final d in descriptors) d.key: d};

  final Map<ContentKey, ContentDescriptor> _known;
  final _requests = <List<ContentKey>>[];

  /// When non-null, [resolve] fails with it.
  Exception? failure;

  /// The keys of each [resolve] call, in call order, repeats included.
  List<List<ContentKey>> get requests => List.unmodifiable(_requests);

  @override
  Future<Map<ContentKey, ContentDescriptor>> resolve(
    Iterable<ContentKey> keys,
  ) async {
    _requests.add(List.unmodifiable(keys));
    final failure = this.failure;
    if (failure != null) throw failure;
    return {for (final key in keys) key: ?_known[key]};
  }
}
