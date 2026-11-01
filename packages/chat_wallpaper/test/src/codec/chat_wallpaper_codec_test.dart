import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _codec = ChatWallpaperCodec();

const _solid = ChatWallpaper.solid(Color(0xFF0A1B2C));
const _linear = ChatWallpaper.linear(
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  rotation: WallpaperRotation.deg135,
);
const _freeform3 = ChatWallpaper.freeform(
  Color(0xFF2D4836),
  Color(0xFF172B19),
  Color(0xFF364331),
);
const _freeform4 = ChatWallpaper.freeform(
  Color(0xFFDBDDBB),
  Color(0xFF6BA587),
  Color(0xFFD5D88D),
  Color(0xFF88B884),
);

void main() {
  group('ChatWallpaperCodec encode', () {
    test('writes a solid wallpaper as rrggbb', () {
      expect(_codec.encode(_solid), '0a1b2c');
    });

    test('writes a linear wallpaper with its rotation', () {
      expect(_codec.encode(_linear), 'ffffff-000000?rotation=135');
    });

    test('writes the default rotation too', () {
      expect(
        _codec.encode(
          const ChatWallpaper.linear(Color(0xFF123456), Color(0xFF654321)),
        ),
        '123456-654321?rotation=0',
      );
    });

    test('writes three- and four-colour freeform wallpapers with ~', () {
      expect(_codec.encode(_freeform3), '2d4836~172b19~364331');
      expect(_codec.encode(_freeform4), 'dbddbb~6ba587~d5d88d~88b884');
    });

    test('ignores alpha', () {
      expect(
        _codec.encode(const ChatWallpaper.solid(Color(0x330A1B2C))),
        '0a1b2c',
      );
    });
  });

  group('ChatWallpaperCodec round-trip', () {
    test('restores every kind', () {
      for (final wallpaper in [_solid, _linear, _freeform3, _freeform4]) {
        expect(_codec.decode(_codec.encode(wallpaper)), wallpaper);
      }
    });

    test('restores every rotation', () {
      for (final rotation in WallpaperRotation.values) {
        final wallpaper = ChatWallpaper.linear(
          const Color(0xFF111111),
          const Color(0xFF222222),
          rotation: rotation,
        );

        expect(_codec.decode(_codec.encode(wallpaper)), wallpaper);
      }
    });
  });

  group('ChatWallpaperCodec decode leniency', () {
    test('accepts uppercase hex', () {
      expect(_codec.decode('0A1B2C'), _solid);
      expect(_codec.decode('DBDDBB~6BA587~D5D88D~88B884'), _freeform4);
    });

    test('accepts either separator', () {
      expect(_codec.decode('ffffff~000000?rotation=135'), _linear);
      expect(_codec.decode('2d4836-172b19-364331'), _freeform3);
      expect(_codec.decode('dbddbb-6ba587~d5d88d-88b884'), _freeform4);
    });

    test('treats a missing rotation as 0°', () {
      expect(
        _codec.decode('ffffff-000000'),
        const ChatWallpaper.linear(Color(0xFFFFFFFF), Color(0xFF000000)),
      );
    });

    test('snaps an unaligned rotation to the nearest 45°', () {
      expect(_codec.decode('ffffff-000000?rotation=130'), _linear);
      expect(
        _codec.decode('ffffff-000000?rotation=350'),
        const ChatWallpaper.linear(Color(0xFFFFFFFF), Color(0xFF000000)),
      );
    });

    test('wraps a rotation outside [0, 360)', () {
      expect(_codec.decode('ffffff-000000?rotation=495'), _linear);
      expect(
        _codec.decode('ffffff-000000?rotation=-45'),
        const ChatWallpaper.linear(
          Color(0xFFFFFFFF),
          Color(0xFF000000),
          rotation: WallpaperRotation.deg315,
        ),
      );
    });

    test('decodes lenient input back to canonical output', () {
      expect(
        _codec.encode(_codec.decode('FFFFFF~000000?rotation=130')),
        'ffffff-000000?rotation=135',
      );
    });
  });

  group('ChatWallpaperCodec decode rejects', () {
    void expectRejected(String input) => expect(
      () => _codec.decode(input),
      throwsFormatException,
      reason: 'input: "$input"',
    );

    test('empty input', () => expectRejected(''));

    test('bad hex', () {
      expectRejected('0a1b2g');
      expectRejected('0a1b2');
      expectRejected('0a1b2c3');
      expectRejected('+a1b2c');
      expectRejected('ffffff-00000g');
    });

    test(
      'five colours',
      () => expectRejected('111111~222222~333333~444444~555555'),
    );

    test('a trailing or leading separator', () {
      expectRejected('0a1b2c-');
      expectRejected('2d4836~172b19~364331~');
      expectRejected('-0a1b2c');
    });

    test('a non-numeric rotation', () {
      expectRejected('ffffff-000000?rotation=abc');
      expectRejected('ffffff-000000?rotation=');
      expectRejected('ffffff-000000?rotation=45.5');
      expectRejected('ffffff-000000?rotation= 45');
      expectRejected('ffffff-000000?rotation=99999999999999999999');
    });

    test('a query other than rotation', () {
      expectRejected('ffffff-000000?');
      expectRejected('ffffff-000000?angle=45');
      expectRejected('ffffff-000000?rotation=45&mode=motion');
    });

    test('a rotation on a solid or freeform wallpaper', () {
      expectRejected('0a1b2c?rotation=0');
      expectRejected('2d4836~172b19~364331?rotation=45');
    });
  });

  group('ChatWallpaperCodec patterns', () {
    const doodles = WallpaperPattern('doodles');
    const mask = WallpaperPattern(
      'Wave_2-b',
      intensity: 40,
      blend: WallpaperPatternBlend.mask,
    );

    const patternedFreeform = ChatWallpaper.patterned(
      ChatWallpaper$Freeform(
        Color(0xFFDBDDBB),
        Color(0xFF6BA587),
        Color(0xFFD5D88D),
        Color(0xFF88B884),
      ),
      doodles,
    );
    const patternedLinear = ChatWallpaper.patterned(
      ChatWallpaper$Linear(
        Color(0xFFFFFFFF),
        Color(0xFF000000),
        rotation: WallpaperRotation.deg135,
      ),
      doodles,
    );
    const maskedSolid = ChatWallpaper.patterned(
      ChatWallpaper$Solid(Color(0xFF0A1B2C)),
      mask,
    );

    void expectRejected(String input) => expect(
      () => _codec.decode(input),
      throwsFormatException,
      reason: 'input: "$input"',
    );

    group('encode', () {
      test('writes the slug, the intensity and the fill colours', () {
        expect(
          _codec.encode(patternedFreeform),
          'doodles?intensity=50&bg_color=dbddbb~6ba587~d5d88d~88b884',
        );
      });

      test('writes a linear fill with its rotation last', () {
        expect(
          _codec.encode(patternedLinear),
          'doodles?intensity=50&bg_color=ffffff-000000&rotation=135',
        );
      });

      test('writes the mask blend as a negative intensity', () {
        expect(
          _codec.encode(maskedSolid),
          'Wave_2-b?intensity=-40&bg_color=0a1b2c',
        );
      });

      test('writes a zero soft-light intensity', () {
        expect(
          _codec.encode(
            const ChatWallpaper.patterned(
              ChatWallpaper$Solid(Color(0xFF0A1B2C)),
              WallpaperPattern('a', intensity: 0),
            ),
          ),
          'a?intensity=0&bg_color=0a1b2c',
        );
      });

      test('refuses a slug the decoder could not read back', () {
        for (final slug in ['', 'two words', 'a?b', 'a&b']) {
          expect(
            () => _codec.encode(
              ChatWallpaper.patterned(
                const ChatWallpaper$Solid(Color(0xFF000000)),
                WallpaperPattern(slug),
              ),
            ),
            throwsArgumentError,
            reason: 'slug: "$slug"',
          );
        }
      });
    });

    test('round-trips every fill kind under both blends', () {
      const fills = <ChatWallpaper$ColorFill>[
        ChatWallpaper$Solid(Color(0xFF0A1B2C)),
        ChatWallpaper$Linear(
          Color(0xFFFFFFFF),
          Color(0xFF000000),
          rotation: WallpaperRotation.deg270,
        ),
        ChatWallpaper$Freeform(
          Color(0xFF2D4836),
          Color(0xFF172B19),
          Color(0xFF364331),
        ),
        ChatWallpaper$Freeform(
          Color(0xFFDBDDBB),
          Color(0xFF6BA587),
          Color(0xFFD5D88D),
          Color(0xFF88B884),
        ),
      ];
      for (final fill in fills) {
        for (final pattern in [
          doodles,
          mask,
          const WallpaperPattern('a', intensity: 0),
        ]) {
          final wallpaper = ChatWallpaper.patterned(fill, pattern);

          expect(_codec.decode(_codec.encode(wallpaper)), wallpaper);
        }
      }
    });

    group('decode leniency', () {
      test('accepts parameters in any order', () {
        expect(
          _codec.decode(
            'doodles?rotation=135&bg_color=ffffff-000000&intensity=50',
          ),
          patternedLinear,
        );
      });

      test('reads a missing intensity as the default soft light', () {
        expect(
          _codec.decode('doodles?bg_color=dbddbb~6ba587~d5d88d~88b884'),
          patternedFreeform,
        );
      });

      test('reads -0 as a zero soft-light intensity', () {
        expect(
          _codec.decode('a?intensity=-0&bg_color=0a1b2c'),
          const ChatWallpaper.patterned(
            ChatWallpaper$Solid(Color(0xFF0A1B2C)),
            WallpaperPattern('a', intensity: 0),
          ),
        );
      });

      test('reads the fill colours as leniently as the colour form', () {
        expect(
          _codec.decode(
            'doodles?intensity=50&bg_color=FFFFFF~000000&rotation=130',
          ),
          patternedLinear,
        );
        expect(
          _codec.decode('doodles?intensity=50&bg_color=ffffff-000000'),
          isA<ChatWallpaper$Patterned>(),
        );
        expect(
          _codec.encode(
            _codec.decode('doodles?bg_color=DBDDBB-6BA587-D5D88D-88B884'),
          ),
          'doodles?intensity=50&bg_color=dbddbb~6ba587~d5d88d~88b884',
        );
      });
    });

    group('decode rejects', () {
      test('a pattern without fill colours', () {
        expectRejected('doodles?intensity=50');
        expectRejected('doodles?intensity=50&bg_color=');
      });

      test('a malformed slug', () {
        expectRejected('?intensity=50&bg_color=0a1b2c');
        expectRejected('doo dles?intensity=50&bg_color=0a1b2c');
        expectRejected('doo.dles?intensity=50&bg_color=0a1b2c');
      });

      test('an intensity out of range or not an integer', () {
        expectRejected('doodles?intensity=101&bg_color=0a1b2c');
        expectRejected('doodles?intensity=-101&bg_color=0a1b2c');
        expectRejected('doodles?intensity=50.5&bg_color=0a1b2c');
        expectRejected('doodles?intensity=&bg_color=0a1b2c');
        expectRejected('doodles?intensity=+50&bg_color=0a1b2c');
      });

      test('a repeated, unknown or malformed parameter', () {
        expectRejected('doodles?intensity=50&intensity=60&bg_color=0a1b2c');
        expectRejected('doodles?intensity=50&bg_color=0a1b2c&mode=motion');
        expectRejected('doodles?intensity=50&bg_color=0a1b2c&');
        expectRejected('doodles?intensity&bg_color=0a1b2c');
      });

      test('bad fill colours', () {
        expectRejected('doodles?bg_color=0a1b2g');
        expectRejected('doodles?bg_color=111111~222222~333333~444444~555555');
        expectRejected('doodles?bg_color=0a1b2c-');
      });

      test('a rotation on a solid or freeform fill', () {
        expectRejected('doodles?bg_color=0a1b2c&rotation=0');
        expectRejected('doodles?bg_color=2d4836~172b19~364331&rotation=45');
      });

      test('pattern parameters on the colour form', () {
        expectRejected('ffffff-000000?rotation=45&intensity=50');
      });
    });
  });
}
