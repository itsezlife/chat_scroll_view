/// The adapter over the platform channel the native code answers.
///
/// **Seam:** [SystemRichClipboard] over the `rich_clipboard` method channel,
/// answered here by a platform clipboard that holds plain text and HTML.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_clipboard/rich_clipboard.dart';

/// What a platform clipboard holds, and how the native code answers.
final class _PlatformClipboard {
  String? plain;
  String? html;
  List<Map<String, Object?>> media = [];

  /// The `media` flag of each read, in order.
  final reads = <bool>[];

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'write':
        final arguments = call.arguments as Map<Object?, Object?>;
        plain = arguments['plain'] as String?;
        html = arguments['html'] as String?;
        media = [];
        return null;
      case 'read':
        final withMedia =
            (call.arguments as Map<Object?, Object?>)['media']! as bool;
        reads.add(withMedia);
        final held = <String, Object?>{
          'plain': ?plain,
          'html': ?html,
          if (withMedia && media.isNotEmpty) 'media': media,
        };
        return held.isEmpty ? null : held;
    }
    throw MissingPluginException(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rich_clipboard');
  late _PlatformClipboard platform;

  setUp(() {
    platform = _PlatformClipboard();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, platform.handle);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  RichClipboardContract.run(
    () => RichClipboardHarness(
      clipboard: const SystemRichClipboard(),
      putPlainText: (text) async {
        platform
          ..plain = text
          ..html = null
          ..media = [];
      },
      putImage: (png) async {
        platform
          ..plain = null
          ..html = null
          ..media = [
            {'bytes': png, 'mimeType': 'image/png'},
          ];
      },
    ),
  );

  test('writes the plain text and the HTML of the text', () async {
    final text = RichText('bold', const [Entity(0, 4, EntityKind.bold)]);

    await const SystemRichClipboard().write(text);

    expect(platform.plain, 'bold');
    expect(platform.html, RichTextHtml.encode(text));
  });

  test('reads another app\'s HTML as rich text, with its plain text', () async {
    platform
      ..plain = 'from a page'
      ..html = '<p>from a <b>page</b></p>';

    expect(
      await const SystemRichClipboard().read(),
      ClipboardText(
        'from a page',
        rich: RichText('from a page', const [Entity(7, 4, EntityKind.bold)]),
      ),
    );
  });

  test('reads an empty clipboard as nothing', () async {
    expect(await const SystemRichClipboard().read(), isNull);
  });

  test(
    'takes the text from the HTML when the platform has no plain text',
    () async {
      platform.html = '<b>only html</b>';

      expect((await const SystemRichClipboard().read())!.plain, 'only html');
    },
  );

  test('reads images as data and copied files as paths', () async {
    platform.media = [
      {
        'bytes': Uint8List.fromList([1, 2]),
        'mimeType': 'image/gif',
        'name': 'a.gif',
      },
      {'path': '/tmp/report.pdf', 'mimeType': 'application/pdf'},
      {'path': '/tmp/unknown'},
    ];

    final media = (await const SystemRichClipboard().readWithMedia()).media;

    expect(media, hasLength(3));
    expect(
      media[0],
      isA<PastedMedia$Bytes>()
          .having((m) => m.mimeType, 'mimeType', 'image/gif')
          .having((m) => m.name, 'name', 'a.gif'),
    );
    expect(media.sublist(1), const [
      PastedMedia.file('/tmp/report.pdf', mimeType: 'application/pdf'),
      PastedMedia.file('/tmp/unknown'),
    ]);
  });

  test('reads text and media in one platform read, and media only when '
      'asked', () async {
    platform
      ..plain = 'a range'
      ..media = [
        {
          'bytes': Uint8List.fromList([1]),
          'mimeType': 'image/png',
        },
      ];

    final contents = await const SystemRichClipboard().readWithMedia();
    final text = await const SystemRichClipboard().read();

    expect(contents.text, const ClipboardText('a range'));
    expect(contents.media, hasLength(1));
    expect(text, const ClipboardText('a range'));
    expect(platform.reads, [true, false]);
  });
}
