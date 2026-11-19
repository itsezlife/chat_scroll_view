import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  SendOptionVisibility visibility(
    AttachPolicy policy,
    List<AttachItem> items, {
    RichText caption = RichText.empty,
    SendOptions options = const SendOptions(),
    SendOptions initial = const SendOptions(),
    AttachLimits limits = const AttachLimits(),
  }) => SendOptionVisibility(
    items: items,
    caption: caption,
    options: options,
    initial: initial,
    policy: policy,
    limits: limits,
  );

  final photo = AttachItems.photo('p');
  final file = AttachItems.file('f');
  final spoilered = AttachItems.photo('s', spoiler: true);

  group('send as file', () {
    test('shows with media and when the limits allow it', () {
      expect(
        visibility(const AttachPolicy.android(), [photo]).sendAsFile,
        isTrue,
      );
      expect(
        visibility(const AttachPolicy.android(), [file]).sendAsFile,
        isFalse,
      );
      expect(
        visibility(
          const AttachPolicy.android(),
          [photo],
          limits: const AttachLimits(sendAsFileAllowed: false),
        ).sendAsFile,
        isFalse,
      );
    });

    test('hides with a spoiler on iOS only', () {
      expect(
        visibility(const AttachPolicy.ios(), [spoilered]).sendAsFile,
        isFalse,
      );
      expect(
        visibility(const AttachPolicy.android(), [spoilered]).sendAsFile,
        isTrue,
      );
    });
  });

  test('without grouping shows for more than one item', () {
    expect(
      visibility(const AttachPolicy.android(), [photo]).withoutGrouping,
      isFalse,
    );
    expect(
      visibility(const AttachPolicy.android(), [photo, file]).withoutGrouping,
      isTrue,
    );
    expect(
      visibility(
        const AttachPolicy.android(),
        [photo, file],
        limits: const AttachLimits(groupingAllowed: false),
      ).withoutGrouping,
      isFalse,
    );
  });

  group('high quality', () {
    test('mobile: every item an unedited photo', () {
      for (final policy in [
        const AttachPolicy.android(),
        const AttachPolicy.ios(),
      ]) {
        expect(visibility(policy, [photo]).highQuality, isTrue);
        expect(
          visibility(policy, [photo, AttachItems.video('v')]).highQuality,
          isFalse,
        );
        expect(
          visibility(policy, [
            photo.copyWith(edits: const ItemEdits(version: 1, recipe: 'crop')),
          ]).highQuality,
          isFalse,
        );
      }
    });

    test('desktop: some photo over 1280 sent as media', () {
      const desktop = AttachPolicy.desktop();
      final large = AttachItems.photo('l', width: 4000, height: 3000);
      final small = AttachItems.photo('s', width: 1280, height: 720);
      expect(
        visibility(desktop, [small, AttachItems.video('v'), large]).highQuality,
        isTrue,
      );
      expect(visibility(desktop, [small]).highQuality, isFalse);
      expect(
        visibility(desktop, [
          large,
        ], options: const SendOptions(asFiles: true)).highQuality,
        isFalse,
      );
    });

    test('web: never', () {
      expect(
        visibility(const AttachPolicy.web(), [photo]).highQuality,
        isFalse,
      );
    });
  });

  test('caption above shows with a caption on media only', () {
    const policy = AttachPolicy.ios();
    const caption = RichText.plain('x');
    expect(visibility(policy, [photo]).captionAbove, isFalse);
    expect(visibility(policy, [photo], caption: caption).captionAbove, isTrue);
    expect(
      visibility(policy, [photo, file], caption: caption).captionAbove,
      isFalse,
    );
    expect(
      visibility(
        policy,
        [photo],
        caption: caption,
        options: const SendOptions(asFiles: true),
      ).captionAbove,
      isFalse,
    );
  });

  test('spoiler shows for media when the limits allow it', () {
    const policy = AttachPolicy.android();
    expect(visibility(policy, [photo]).spoiler, isTrue);
    expect(visibility(policy, [file]).spoiler, isFalse);
    expect(
      visibility(policy, [
        photo,
      ], limits: const AttachLimits(spoilerAllowed: false)).spoiler,
      isFalse,
    );
  });

  group('the confirm box checkboxes', () {
    const desktop = AttachPolicy.desktop();

    test('group items needs two neighbours that can share a group', () {
      expect(visibility(desktop, [photo]).groupCheckbox, isFalse);
      expect(
        visibility(desktop, [photo, AttachItems.video('v')]).groupCheckbox,
        isTrue,
      );
      expect(visibility(desktop, [photo, file]).groupCheckbox, isTrue);
      expect(
        visibility(desktop, [photo, AttachItems.audio('a')]).groupCheckbox,
        isFalse,
      );
      expect(
        visibility(desktop, [
          photo,
          AttachItems.video('v'),
        ], limits: const AttachLimits(groupingAllowed: false)).groupCheckbox,
        isFalse,
      );
    });

    test('send as documents needs a photo or video', () {
      expect(visibility(desktop, [file, photo]).asDocumentsCheckbox, isTrue);
      expect(visibility(desktop, [file]).asDocumentsCheckbox, isFalse);
    });

    test(
      'in slow mode, send as documents needs exactly one photo or video',
      () {
        const slow = AttachLimits(groupingAllowed: false);
        expect(
          visibility(desktop, [photo], limits: slow).asDocumentsCheckbox,
          isTrue,
        );
        expect(
          visibility(desktop, [
            photo,
            AttachItems.photo('q'),
          ], limits: slow).asDocumentsCheckbox,
          isFalse,
        );
      },
    );

    test('remember shows only after a checkbox changed', () {
      expect(visibility(desktop, [photo, file]).remember, isFalse);
      expect(
        visibility(desktop, [
          photo,
          file,
        ], options: const SendOptions(grouped: false)).remember,
        isTrue,
      );
      expect(
        visibility(desktop, [
          photo,
          file,
        ], options: const SendOptions(silent: true)).remember,
        isFalse,
      );
    });
  });
}
