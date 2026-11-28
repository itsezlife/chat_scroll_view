import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChromeWidthClass.fromSize', () {
    ChromeWidthClass at(double width, [double height = 800]) =>
        ChromeWidthClass.fromSize(Size(width, height));

    test('600 is compact, 601 medium', () {
      expect(at(0), ChromeWidthClass.compact);
      expect(at(600), ChromeWidthClass.compact);
      expect(at(601), ChromeWidthClass.medium);
    });

    test('925 is medium, 926 expanded', () {
      expect(at(925), ChromeWidthClass.medium);
      expect(at(926), ChromeWidthClass.expanded);
      expect(at(1920), ChromeWidthClass.expanded);
    });

    test('a landscape phone follows its width by default', () {
      expect(at(950, 450), ChromeWidthClass.expanded);
      expect(at(800, 400), ChromeWidthClass.medium);
    });

    test('a landscape phone is compact when the host opts in', () {
      ChromeWidthClass phone(double width, double height) =>
          ChromeWidthClass.fromSize(
            Size(width, height),
            landscapePhoneIsCompact: true,
          );

      expect(phone(950, 450), ChromeWidthClass.compact);
      expect(phone(800, 400), ChromeWidthClass.compact);
      // Past either bound the window is no phone: its width decides.
      expect(phone(951, 450), ChromeWidthClass.expanded);
      expect(phone(950, 451), ChromeWidthClass.expanded);
      expect(phone(800, 451), ChromeWidthClass.medium);
    });

    test('the class reads as compact or not', () {
      expect(ChromeWidthClass.compact.isCompact, isTrue);
      expect(ChromeWidthClass.medium.isCompact, isFalse);
      expect(ChromeWidthClass.expanded.isCompact, isFalse);
    });
  });

  group('ChromeWidthClass.of', () {
    Future<List<ChromeWidthClass>> pumpReader(
      WidgetTester tester, {
      required Size size,
      bool? landscapePhoneIsCompact,
      List<ChromeWidthClass>? seen,
    }) async {
      final log = seen ?? <ChromeWidthClass>[];
      Widget reader = Builder(
        builder: (context) {
          log.add(ChromeWidthClass.of(context));
          return const SizedBox();
        },
      );
      if (landscapePhoneIsCompact != null) {
        reader = ChromeWidthClassScope(
          landscapePhoneIsCompact: landscapePhoneIsCompact,
          child: reader,
        );
      }
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: reader,
        ),
      );
      return log;
    }

    testWidgets('follows the window across a resize', (tester) async {
      final seen = <ChromeWidthClass>[];
      for (final width in <double>[600, 601, 925, 926, 600]) {
        await pumpReader(tester, size: Size(width, 800), seen: seen);
      }

      expect(seen, [
        ChromeWidthClass.compact,
        ChromeWidthClass.medium,
        ChromeWidthClass.medium,
        ChromeWidthClass.expanded,
        ChromeWidthClass.compact,
      ]);
    });

    testWidgets('a reader rebuilds when the window crosses a bound', (
      tester,
    ) async {
      final seen = <ChromeWidthClass>[];
      final size = ValueNotifier(const Size(700, 800));
      addTearDown(size.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: size,
          builder: (context, value, _) => MediaQuery(
            data: MediaQueryData(size: value),
            child: const _Reader(),
          ),
        ),
      );
      final reader = tester.state<_ReaderState>(find.byType(_Reader));
      seen.add(reader.widthClass);

      size.value = const Size(500, 800);
      await tester.pump();
      seen.add(reader.widthClass);

      expect(seen, [ChromeWidthClass.medium, ChromeWidthClass.compact]);
    });

    testWidgets('a landscape phone is compact only under the opt-in', (
      tester,
    ) async {
      const phone = Size(900, 400);
      expect(await pumpReader(tester, size: phone), [ChromeWidthClass.medium]);
      expect(
        await pumpReader(tester, size: phone, landscapePhoneIsCompact: false),
        [ChromeWidthClass.medium],
      );
      expect(
        await pumpReader(tester, size: phone, landscapePhoneIsCompact: true),
        [ChromeWidthClass.compact],
      );
    });
  });
}

class _Reader extends StatefulWidget {
  const _Reader();

  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  late ChromeWidthClass widthClass;

  @override
  Widget build(BuildContext context) {
    widthClass = ChromeWidthClass.of(context);
    return const SizedBox();
  }
}
