/// The composer's keyboard intent: what a surface over the composer asks of
/// the keyboard, for the host to carry out.
///
/// **Seam:** `ComposerController.keyboardIntent`, `setKeyboardIntent`,
/// `reopenKeyboard` and `requestKeyboard` (observed through
/// `keyboardRequests`).
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ComposerController composer;
  late int requests;

  setUp(() {
    composer = ComposerController();
    requests = 0;
    composer.keyboardRequests.addListener(() => requests++);
  });
  tearDown(() => composer.dispose());

  test('keeps the keyboard by default', () {
    expect(composer.keyboardIntent.value, ComposerKeyboardIntent.keep);
  });

  test('publishes each intent it is given', () {
    final seen = <ComposerKeyboardIntent>[];
    composer.keyboardIntent.addListener(
      () => seen.add(composer.keyboardIntent.value),
    );

    composer
      ..setKeyboardIntent(ComposerKeyboardIntent.hold)
      ..setKeyboardIntent(ComposerKeyboardIntent.hold)
      ..setKeyboardIntent(ComposerKeyboardIntent.hide)
      ..setKeyboardIntent(ComposerKeyboardIntent.keep);

    expect(seen, [
      ComposerKeyboardIntent.hold,
      ComposerKeyboardIntent.hide,
      ComposerKeyboardIntent.keep,
    ]);
  });

  test('a keyboard request while held does nothing', () {
    composer
      ..setKeyboardIntent(ComposerKeyboardIntent.hold)
      ..requestKeyboard();

    expect(requests, 0);
  });

  test('reopenKeyboard raises a held keyboard and lets requests through '
      'while the hold goes on', () {
    composer
      ..setKeyboardIntent(ComposerKeyboardIntent.hold)
      ..reopenKeyboard();

    expect(requests, 1);
    expect(composer.keyboardIntent.value, ComposerKeyboardIntent.hold);

    composer.requestKeyboard();
    expect(requests, 2);
  });

  test('a new hold drops requests again', () {
    composer
      ..setKeyboardIntent(ComposerKeyboardIntent.hold)
      ..reopenKeyboard()
      ..setKeyboardIntent(ComposerKeyboardIntent.keep)
      ..setKeyboardIntent(ComposerKeyboardIntent.hold)
      ..requestKeyboard();

    expect(requests, 1);
  });

  test('requests pass under keep and hide', () {
    composer.requestKeyboard();
    composer
      ..setKeyboardIntent(ComposerKeyboardIntent.hide)
      ..requestKeyboard();

    expect(requests, 2);
  });

  test('reopenKeyboard outside a hold is a plain request', () {
    composer.reopenKeyboard();

    expect(requests, 1);
  });

  test('is inert after dispose', () {
    final other = ComposerController()..dispose();

    expect(
      () => other
        ..setKeyboardIntent(ComposerKeyboardIntent.hold)
        ..reopenKeyboard(),
      returnsNormally,
    );
  });
}
