import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

void main() {
  late NativeFramePageMemory memory;

  setUp(() => memory = NativeFramePageMemory());
  tearDown(() => memory.dispose());

  test('a page is zero-filled and a page long', () {
    final page = memory.page(0, side: 64);

    expect(page.length, 64 * 64 * 4);
    expect(page.every((byte) => byte == 0), isTrue);
  });

  test('a page keeps its address and its bytes between calls', () {
    final address = memory.addressOf(2, side: 64);
    memory.page(2, side: 64)[5] = 9;

    expect(memory.addressOf(2, side: 64), address);
    expect(memory.page(2, side: 64)[5], 9);
    expect(memory.addressOf(3, side: 64), isNot(address));
  });

  test('the view and the address name the same bytes', () {
    final address = memory.addressOf(0, side: 64);

    Pointer<Uint8>.fromAddress(address)[7] = 42;
    expect(memory.page(0, side: 64)[7], 42);

    memory.page(0, side: 64)[8] = 77;
    expect(Pointer<Uint8>.fromAddress(address)[8], 77);
  });

  test('a dropped page comes back blank', () {
    memory.page(1, side: 64)[0] = 200;

    memory.drop(1);

    expect(memory.page(1, side: 64)[0], 0);
  });

  test('dropping a page that was never made is harmless', () {
    memory.drop(5);
  });

  test('pages of one memory have sides of their own', () {
    memory
      ..page(0, side: 64)
      ..page(1, side: 256);

    expect(memory.sideOf(0), 64);
    expect(memory.sideOf(1), 256);
    expect(memory.page(1, side: 256).length, 256 * 256 * 4);
  });

  test('a live page asked for at another side is a state error', () {
    memory.page(0, side: 64);

    expect(() => memory.page(0, side: 128), throwsStateError);
    expect(() => memory.addressOf(0, side: 128), throwsStateError);
  });

  test('sideOf a page that does not exist is a state error', () {
    expect(() => memory.sideOf(9), throwsStateError);
  });

  test('a dropped page may come back at another side', () {
    memory.page(0, side: 64);

    memory.drop(0);

    expect(memory.page(0, side: 128).length, 128 * 128 * 4);
    expect(memory.sideOf(0), 128);
  });

  test('dispose is idempotent and later calls throw StateError', () {
    memory
      ..page(0, side: 64)
      ..dispose()
      ..dispose();

    expect(() => memory.page(0, side: 64), throwsStateError);
    expect(() => memory.addressOf(0, side: 64), throwsStateError);
  });
}
