import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatComposerController composer;

  setUp(() {
    composer = ChatComposerController();
  });

  tearDown(() {
    composer.dispose();
  });

  test('beginEdit commits mode and notifies select', () {
    ChatComposerMode? seen;
    final modeListenable = composer.select((s) => s.data.mode);
    void onMode() => seen = modeListenable.value;
    modeListenable.addListener(onMode);

    composer.beginEdit(id: 7, preview: 'hello');

    expect(composer.mode.isEditing, isTrue);
    expect(
      composer.mode,
      const ChatComposerMode$Editing(id: 7, preview: 'hello'),
    );
    expect(seen, const ChatComposerMode$Editing(id: 7, preview: 'hello'));
    modeListenable.removeListener(onMode);
  });

  test('beginReply commits mode without clearing text', () {
    composer.text.text = 'draft';
    composer.beginReply(id: 3, title: 'Ada', subtitle: 'hi');

    expect(composer.mode.isReplying, isTrue);
    expect(composer.text.text, 'draft');
    expect(
      composer.mode,
      const ChatComposerMode$Replying(id: 3, title: 'Ada', subtitle: 'hi'),
    );
  });

  test('cancelMode returns to idle without clearing text', () {
    composer.text.text = 'draft';
    composer.beginReply(id: 1, title: 'A', subtitle: 'b');
    composer.cancelMode();

    expect(composer.mode, const ChatComposerMode.idle());
    expect(composer.text.text, 'draft');
  });

  test('clear resets text and mode', () {
    composer.text.text = 'draft';
    composer.beginEdit(id: 1, preview: 'x');
    composer.clear();

    expect(composer.text.text, isEmpty);
    expect(composer.mode, const ChatComposerMode.idle());
  });

  test('same-value setBusy is silent for busy select', () {
    var count = 0;
    final busy = composer.select((s) => s.data.busy);
    busy.addListener(() => count++);
    composer.setBusy(true);
    composer.setBusy(true);
    expect(count, 1);
    expect(composer.data.busy, isTrue);
    busy.removeListener(() => count++);
  });

  test('insertText and backspace mutate caret', () {
    composer.insertText('ab');
    expect(composer.text.text, 'ab');
    composer.backspace();
    expect(composer.text.text, 'a');
  });

  test('disabled refuses beginEdit / insertText', () {
    composer.setEnabled(false);
    composer.beginEdit(id: 1, preview: 'x');
    composer.insertText('nope');
    expect(composer.mode, const ChatComposerMode.idle());
    expect(composer.text.text, isEmpty);
  });

  test('dispose is idempotent and silences commands', () {
    composer.dispose();
    composer.beginEdit(id: 1, preview: 'x');
    composer.insertText('x');
    expect(composer.isDisposed, isTrue);
    composer.dispose();
  });

  test('bindEnterProjection routes requestKeyboard', () {
    var calls = 0;
    composer.bindEnterProjection(onRequestKeyboard: () => calls++);
    composer.requestKeyboard();
    expect(calls, 1);
  });

  test('external text ownership is not disposed by controller', () {
    final text = TextEditingController(text: 'kept');
    final owned = ChatComposerController(text: text, ownsText: false);
    owned.dispose();
    expect(text.text, 'kept');
    text.dispose();
  });

  test('enabled select does not notify on unrelated emoji change', () {
    var count = 0;
    final enabled = composer.select((s) => s.data.enabled);
    enabled.addListener(() => count++);
    composer.setEmojiIconState(ChatEnterEmojiIconState.keyboard);
    expect(count, 0);
    composer.setEnabled(false);
    expect(count, 1);
    enabled.removeListener(() => count++);
  });
}
