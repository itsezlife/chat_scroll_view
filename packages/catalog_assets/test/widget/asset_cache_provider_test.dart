import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

AssetCacheScope _scope() {
  final scope = AssetCacheScope(
    clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
  );
  addTearDown(scope.dispose);
  return scope;
}

void main() {
  testWidgets('gives descendants the scope the host created', (tester) async {
    final scope = _scope();
    AssetCacheScope? found;

    await tester.pumpWidget(
      AssetCacheProvider(
        scope: scope,
        child: Builder(
          builder: (context) {
            found = AssetCacheProvider.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(found, same(scope));
  });

  testWidgets('maybeOf is null without a provider', (tester) async {
    AssetCacheScope? found = _scope();

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          found = AssetCacheProvider.maybeOf(context);
          return const SizedBox();
        },
      ),
    );

    expect(found, isNull);
  });

  testWidgets('of explains what is missing without a provider', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          AssetCacheProvider.of(context);
          return const SizedBox();
        },
      ),
    );

    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect(error.toString(), contains('AssetCacheProvider'));
  });

  testWidgets('rebuilds dependents when the scope is replaced only', (
    tester,
  ) async {
    final first = _scope();
    final second = _scope();
    _Probe.builds = 0;
    Widget app(AssetCacheScope scope) =>
        AssetCacheProvider(scope: scope, child: const _Probe());

    await tester.pumpWidget(app(first));
    await tester.pumpWidget(app(first));
    expect(_Probe.builds, 1);

    await tester.pumpWidget(app(second));
    expect(_Probe.builds, 2);
  });

  testWidgets('does not dispose the scope it was handed', (tester) async {
    final scope = _scope();

    await tester.pumpWidget(
      AssetCacheProvider(scope: scope, child: const SizedBox()),
    );
    await tester.pumpWidget(const SizedBox());

    expect(
      () => scope.attach(
        const ContentKey.document('1'),
        const AssetSpec(pixelWidth: 1, pixelHeight: 1),
        const AssetProfile(),
      ),
      returnsNormally,
    );
  });
}

class _Probe extends StatelessWidget {
  const _Probe();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    AssetCacheProvider.of(context);
    builds++;
    return const SizedBox();
  }
}
