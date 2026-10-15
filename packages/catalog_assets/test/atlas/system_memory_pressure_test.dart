import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tells its listeners when the platform reports memory pressure', (
    tester,
  ) async {
    final pressure = SystemMemoryPressure();
    addTearDown(pressure.dispose);
    var told = 0;
    pressure.addListener(() => told++);

    tester.binding.handleMemoryPressure();

    expect(told, 1);
  });

  testWidgets('a disposed signal is no longer told', (tester) async {
    final pressure = SystemMemoryPressure();
    var told = 0;
    pressure
      ..addListener(() => told++)
      ..dispose();

    tester.binding.handleMemoryPressure();

    expect(told, 0);
  });

  testWidgets('releases the pages of a residency it is given', (tester) async {
    final pressure = SystemMemoryPressure();
    addTearDown(pressure.dispose);
    final residency = GlyphPageResidency(memoryPressure: pressure);
    addTearDown(residency.dispose);

    tester.binding.handleMemoryPressure();

    expect(residency.residentPages, isEmpty);
  });
}
