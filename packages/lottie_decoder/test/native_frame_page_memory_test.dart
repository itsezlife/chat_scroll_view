import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

void main() {
  late NativeFramePageMemory memory;

  setUp(() => memory = NativeFramePageMemory(pageSide: 64));
  tearDown(() => memory.dispose());

  test('a page is zero-filled and a page long', () {
    final page = memory.page(0);

    expect(page.length, 64 * 64 * 4);
    expect(page.every((byte) => byte == 0), isTrue);
  });

  test('a page keeps its address and its bytes between calls', () {
    final address = memory.addressOf(2);
    memory.page(2)[5] = 9;

    expect(memory.addressOf(2), address);
    expect(memory.page(2)[5], 9);
    expect(memory.addressOf(3), isNot(address));
  });

  test('the view and the address name the same bytes', () {
    final address = memory.addressOf(0);

    Pointer<Uint8>.fromAddress(address)[7] = 42;
    expect(memory.page(0)[7], 42);

    memory.page(0)[8] = 77;
    expect(Pointer<Uint8>.fromAddress(address)[8], 77);
  });

  test('a dropped page comes back blank', () {
    memory.page(1)[0] = 200;

    memory.drop(1);

    expect(memory.page(1)[0], 0);
  });

  test('dropping a page that was never made is harmless', () {
    memory.drop(5);
  });

  test('dispose is idempotent and later calls throw StateError', () {
    memory
      ..page(0)
      ..dispose()
      ..dispose();

    expect(() => memory.page(0), throwsStateError);
    expect(() => memory.addressOf(0), throwsStateError);
  });
}
