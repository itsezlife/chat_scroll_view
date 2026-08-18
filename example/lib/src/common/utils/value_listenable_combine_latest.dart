import 'package:flutter/foundation.dart';

/// Merges several [ValueListenable]s into one sequence.
///
/// Whenever any source notifies, re-reads every source's current
/// [ValueListenable.value], runs the combiner, and notifies listeners when the
/// result changes.
///
/// Unlike stream `combineLatest`, sources always expose a current value, so
/// the combined result is available immediately (no wait for a first event
/// from each source).
///
/// **Notify policy:** skips notify when the new result is [identical] to the
/// previous one. Optional `test` runs only after that check fails — return
/// `true` to allow notify. Pass `(prev, next) => prev != next` when the
/// combiner allocates a new object each time (e.g. a record).
///
/// Subscribes to sources on the first [addListener] and unsubscribes when the
/// last listener is removed. Call [dispose] to detach early if needed.
///
/// ```dart
/// // Dynamic count — same element type
/// CombineLatestValueListenable(
///   [a, b, c],
///   (values) => values.join(),
/// );
///
/// // Fixed arity — distinct types
/// CombineLatestValueListenable.combine2(
///   left,
///   right,
///   (a, b) => (a: a, b: b),
///   (prev, next) => prev != next,
/// );
/// ```
final class CombineLatestValueListenable<T, R>
    with ChangeNotifier
    implements ValueListenable<R> {
  /// Creates a combined listenable from [sources].
  ///
  /// [combiner] receives an unmodifiable list of the latest values, in the
  /// same order as [sources].
  CombineLatestValueListenable(
    Iterable<ValueListenable<T>> sources,
    R Function(List<T> values) combiner, [
    bool Function(R previous, R next)? test,
  ]) : _sources = List<ValueListenable<T>>.of(sources, growable: false),
       _combiner = combiner,
       _test = test;

  /// Combines [sources] into a [List] of their latest values.
  static CombineLatestValueListenable<T, List<T>> list<T>(
    Iterable<ValueListenable<T>> sources, [
    bool Function(List<T> previous, List<T> next)? test,
  ]) => CombineLatestValueListenable<T, List<T>>(
    sources,
    (values) => values,
    test,
  );

  /// Combines two sources with a typed [combiner].
  static ValueListenable<R> combine2<A, B, R>(
    ValueListenable<A> a,
    ValueListenable<B> b,
    R Function(A a, B b) combiner, [
    bool Function(R previous, R next)? test,
  ]) => CombineLatestValueListenable<dynamic, R>(
    [a, b],
    (values) => combiner(values[0] as A, values[1] as B),
    test,
  );

  /// Combines three sources with a typed [combiner].
  static ValueListenable<R> combine3<A, B, C, R>(
    ValueListenable<A> a,
    ValueListenable<B> b,
    ValueListenable<C> c,
    R Function(A a, B b, C c) combiner, [
    bool Function(R previous, R next)? test,
  ]) => CombineLatestValueListenable<dynamic, R>(
    [a, b, c],
    (values) => combiner(
      values[0] as A,
      values[1] as B,
      values[2] as C,
    ),
    test,
  );

  /// Combines four sources with a typed [combiner].
  static ValueListenable<R> combine4<A, B, C, D, R>(
    ValueListenable<A> a,
    ValueListenable<B> b,
    ValueListenable<C> c,
    ValueListenable<D> d,
    R Function(A a, B b, C c, D d) combiner, [
    bool Function(R previous, R next)? test,
  ]) => CombineLatestValueListenable<dynamic, R>(
    [a, b, c, d],
    (values) => combiner(
      values[0] as A,
      values[1] as B,
      values[2] as C,
      values[3] as D,
    ),
    test,
  );

  /// Combines five sources with a typed [combiner].
  static ValueListenable<R> combine5<A, B, C, D, E, R>(
    ValueListenable<A> a,
    ValueListenable<B> b,
    ValueListenable<C> c,
    ValueListenable<D> d,
    ValueListenable<E> e,
    R Function(A a, B b, C c, D d, E e) combiner, [
    bool Function(R previous, R next)? test,
  ]) => CombineLatestValueListenable<dynamic, R>(
    [a, b, c, d, e],
    (values) => combiner(
      values[0] as A,
      values[1] as B,
      values[2] as C,
      values[3] as D,
      values[4] as E,
    ),
    test,
  );

  /// Combines six sources with a typed [combiner].
  static ValueListenable<R> combine6<A, B, C, D, E, F, R>(
    ValueListenable<A> a,
    ValueListenable<B> b,
    ValueListenable<C> c,
    ValueListenable<D> d,
    ValueListenable<E> e,
    ValueListenable<F> f,
    R Function(A a, B b, C c, D d, E e, F f) combiner, [
    bool Function(R previous, R next)? test,
  ]) => CombineLatestValueListenable<dynamic, R>(
    [a, b, c, d, e, f],
    (values) => combiner(
      values[0] as A,
      values[1] as B,
      values[2] as C,
      values[3] as D,
      values[4] as E,
      values[5] as F,
    ),
    test,
  );

  /// Combines seven sources with a typed [combiner].
  static ValueListenable<R> combine7<A, B, C, D, E, F, G, R>(
    ValueListenable<A> a,
    ValueListenable<B> b,
    ValueListenable<C> c,
    ValueListenable<D> d,
    ValueListenable<E> e,
    ValueListenable<F> f,
    ValueListenable<G> g,
    R Function(A a, B b, C c, D d, E e, F f, G g) combiner, [
    bool Function(R previous, R next)? test,
  ]) => CombineLatestValueListenable<dynamic, R>(
    [a, b, c, d, e, f, g],
    (values) => combiner(
      values[0] as A,
      values[1] as B,
      values[2] as C,
      values[3] as D,
      values[4] as E,
      values[5] as F,
      values[6] as G,
    ),
    test,
  );

  /// Combines eight sources with a typed [combiner].
  static ValueListenable<R> combine8<A, B, C, D, E, F, G, H, R>(
    ValueListenable<A> a,
    ValueListenable<B> b,
    ValueListenable<C> c,
    ValueListenable<D> d,
    ValueListenable<E> e,
    ValueListenable<F> f,
    ValueListenable<G> g,
    ValueListenable<H> h,
    R Function(A a, B b, C c, D d, E e, F f, G g, H h) combiner, [
    bool Function(R previous, R next)? test,
  ]) => CombineLatestValueListenable<dynamic, R>(
    [a, b, c, d, e, f, g, h],
    (values) => combiner(
      values[0] as A,
      values[1] as B,
      values[2] as C,
      values[3] as D,
      values[4] as E,
      values[5] as F,
      values[6] as G,
      values[7] as H,
    ),
    test,
  );

  /// Combines nine sources with a typed [combiner].
  static ValueListenable<R> combine9<A, B, C, D, E, F, G, H, I, R>(
    ValueListenable<A> a,
    ValueListenable<B> b,
    ValueListenable<C> c,
    ValueListenable<D> d,
    ValueListenable<E> e,
    ValueListenable<F> f,
    ValueListenable<G> g,
    ValueListenable<H> h,
    ValueListenable<I> i,
    R Function(A a, B b, C c, D d, E e, F f, G g, H h, I i) combiner, [
    bool Function(R previous, R next)? test,
  ]) => CombineLatestValueListenable<dynamic, R>(
    [a, b, c, d, e, f, g, h, i],
    (values) => combiner(
      values[0] as A,
      values[1] as B,
      values[2] as C,
      values[3] as D,
      values[4] as E,
      values[5] as F,
      values[6] as G,
      values[7] as H,
      values[8] as I,
    ),
    test,
  );

  final List<ValueListenable<T>> _sources;
  final R Function(List<T> values) _combiner;
  final bool Function(R previous, R next)? _test;
  var _subscribed = false;

  late R _$value = _combine();

  List<T> _snapshot() =>
      List<T>.unmodifiable([for (final source in _sources) source.value]);

  R _combine() => _combiner(_snapshot());

  @override
  R get value => _subscribed ? _$value : _$value = _combine();

  void _update() {
    final newValue = _combine();
    if (identical(_$value, newValue)) return;
    if (!(_test?.call(_$value, newValue) ?? true)) return;
    _$value = newValue;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!_subscribed) {
      _$value = _combine();
      for (final source in _sources) {
        source.addListener(_update);
      }
      _subscribed = true;
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners && _subscribed) {
      for (final source in _sources) {
        source.removeListener(_update);
      }
      _subscribed = false;
    }
  }

  @override
  void dispose() {
    if (_subscribed) {
      for (final source in _sources) {
        source.removeListener(_update);
      }
      _subscribed = false;
    }
    super.dispose();
  }
}
