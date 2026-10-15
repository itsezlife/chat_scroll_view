/// Element-wise equality for the list fields of the value types.
///
/// Dart lists compare by identity, so a value type holding one needs this to
/// stay a value. Internal: not exported from the package barrel.
abstract final class ValueEquality {
  /// Whether [a] and [b] have equal elements in the same order.
  static bool lists<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
