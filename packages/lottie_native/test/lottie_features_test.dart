import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';

void main() {
  test('the flags carry the bit values of the wrapper header', () {
    expect(LottieFeatures.effects.bits, 1);
    expect(LottieFeatures.expressions.bits, 2);
    expect(LottieFeatures.imageLayers.bits, 4);
    expect(LottieFeatures.textLayers.bits, 8);
  });

  test('none is empty and contains nothing', () {
    expect(LottieFeatures.none.isEmpty, isTrue);
    expect(LottieFeatures.none.contains(LottieFeatures.effects), isFalse);
  });

  test('a combination contains each of its flags and no other', () {
    final used = LottieFeatures.effects | LottieFeatures.textLayers;

    expect(used.bits, 9);
    expect(used.isEmpty, isFalse);
    expect(used.contains(LottieFeatures.effects), isTrue);
    expect(used.contains(LottieFeatures.textLayers), isTrue);
    expect(used.contains(LottieFeatures.expressions), isFalse);
  });

  test('contains asks for every bit of the argument', () {
    const used = LottieFeatures.effects;

    expect(
      used.contains(LottieFeatures.effects | LottieFeatures.textLayers),
      isFalse,
    );
  });
}
