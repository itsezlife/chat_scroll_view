import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

void main() {
  late Pointer<Uint8> memory;
  late LottieFrameRegion region;

  setUp(() {
    memory = calloc<Uint8>(4 * 4 * 4);
    region = LottieFrameRegion(
      target: memory,
      width: 4,
      height: 4,
      strideBytes: 16,
    );
  });
  tearDown(() => calloc.free(memory));

  test('compressFails makes a valid region answer null', () {
    final codec = FakeLottieFrameCodec()..compressFails = true;

    expect(codec.compress(region), isNull);
  });

  test('decompressFails makes valid data answer false', () {
    final packed = FakeLottieFrameCodec().compress(region)!;
    final codec = FakeLottieFrameCodec()..decompressFails = true;

    expect(codec.decompress(packed, region), isFalse);
  });

  test('a stream starts with a header, then the tight pixels', () {
    memory.asTypedList(64).setAll(0, List.generate(64, (i) => i));

    final packed = FakeLottieFrameCodec().compress(region)!;

    expect(packed.length, 6 + 64);
    expect(packed.sublist(6), Uint8List.fromList(List.generate(64, (i) => i)));
  });
}
