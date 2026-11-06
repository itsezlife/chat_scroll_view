import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ListFramePageMemory memory;

  setUp(() => memory = ListFramePageMemory());

  test('a page is made on first use at the side asked, blank', () {
    final page = memory.page(0, side: 128);

    expect(page.length, 128 * 128 * 4);
    expect(page.every((byte) => byte == 0), isTrue);
    expect(memory.sideOf(0), 128);
  });

  test('pages of one memory have sides of their own', () {
    memory
      ..page(0, side: 128)
      ..page(1, side: 1024);

    expect(memory.sideOf(0), 128);
    expect(memory.sideOf(1), 1024);
    expect(memory.page(1, side: 1024).length, 1024 * 1024 * 4);
  });

  test('a live page keeps its bytes between calls at the same side', () {
    memory.page(0, side: 64)[5] = 9;

    expect(memory.page(0, side: 64)[5], 9);
  });

  test('a live page asked for at another side is a state error', () {
    memory.page(0, side: 64);

    expect(() => memory.page(0, side: 128), throwsStateError);
  });

  test('sideOf a page that does not exist is a state error', () {
    expect(() => memory.sideOf(3), throwsStateError);
  });

  test('a dropped page comes back blank and may change side', () {
    memory.page(0, side: 64)[0] = 200;

    memory.drop(0);
    expect(() => memory.sideOf(0), throwsStateError);
    final again = memory.page(0, side: 128);

    expect(again[0], 0);
    expect(memory.sideOf(0), 128);
  });

  test('dropping a page that was never made is harmless', () {
    memory.drop(5);
  });

  test('a side without pixels is an argument error', () {
    expect(() => memory.page(0, side: 0), throwsArgumentError);
  });
}
