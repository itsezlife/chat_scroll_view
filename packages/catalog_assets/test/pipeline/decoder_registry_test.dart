import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DecoderRegistry', () {
    test('finds the decoder registered for a media form', () {
      final decoder = FakeDecoder();
      final registry = DecoderRegistry()..register(MediaForm.still, decoder);

      expect(registry.decoderFor(MediaForm.still), same(decoder));
      expect(registry.decoderFor(MediaForm.video), isNull);
    });

    test('refuses a second decoder for the same form', () {
      final registry = DecoderRegistry()
        ..register(MediaForm.still, FakeDecoder());

      expect(
        () => registry.register(MediaForm.still, FakeDecoder()),
        throwsStateError,
      );
    });

    test('refuses forms that are not decoded', () {
      final registry = DecoderRegistry();

      expect(
        () => registry.register(MediaForm.glyph, FakeDecoder()),
        throwsArgumentError,
      );
      expect(
        () => registry.register(MediaForm.unknown, FakeDecoder()),
        throwsArgumentError,
      );
    });
  });
}
