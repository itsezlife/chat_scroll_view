import 'package:bulletins/bulletins.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('duration chosen by the factory rule', () {
    test('text under 20 characters is short', () {
      expect(
        const Bulletin(message: 'Copied').effectiveDuration,
        BulletinDuration.short,
      );
    });

    test('text of 20 characters or more is long', () {
      expect(
        const Bulletin(message: 'Link copied to clipboard').effectiveDuration,
        BulletinDuration.long,
      );
    });

    test('the title counts toward the length', () {
      expect(
        const Bulletin(
          title: 'Stickers added',
          message: 'Cute cats',
        ).effectiveDuration,
        BulletinDuration.long,
      );
    });

    test('an undo bulletin is prolonged whatever its length', () {
      expect(
        Bulletin(
          message: 'Removed',
          action: BulletinAction.undo(onUndo: () {}),
        ).effectiveDuration,
        BulletinDuration.prolonged,
      );
    });

    test('a button bulletin follows the text rule', () {
      expect(
        Bulletin(
          message: 'Saved',
          action: BulletinAction.button(label: 'View', onPressed: () {}),
        ).effectiveDuration,
        BulletinDuration.short,
      );
    });

    test('a duration the caller names wins', () {
      expect(
        Bulletin(
          message: 'Removed',
          action: BulletinAction.undo(onUndo: () {}),
          duration: BulletinDuration.untilDismissed,
        ).effectiveDuration,
        BulletinDuration.untilDismissed,
      );
    });
  });

  group('spoken label', () {
    test('is the title and the message', () {
      expect(
        const Bulletin(title: 'Stickers removed', message: 'Cats').spokenLabel,
        'Stickers removed\nCats',
      );
    });

    test('is the message alone without a title', () {
      expect(const Bulletin(message: 'Copied').spokenLabel, 'Copied');
    });

    test('is the caller\'s when given', () {
      expect(
        const Bulletin(
          message: 'Copied',
          semanticsLabel: 'Text copied',
        ).spokenLabel,
        'Text copied',
      );
    });
  });

  test('exact durations compare by value', () {
    expect(
      const BulletinDuration.exactly(Duration(seconds: 4)),
      const BulletinDuration.exactly(Duration(seconds: 4)),
    );
    expect(
      const BulletinDuration.exactly(Duration(seconds: 4)),
      isNot(const BulletinDuration.exactly(Duration(seconds: 5))),
    );
  });
}
