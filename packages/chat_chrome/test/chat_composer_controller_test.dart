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
    final busy = composer.select((s) => s.isProcessing);
    void onBusy() => count++;
    busy.addListener(onBusy);
    composer.setBusy(true, message: 'Sending');
    composer.setBusy(true, message: 'Sending');
    expect(count, 1);
    expect(composer.state.isProcessing, isTrue);
    busy.removeListener(onBusy);
  });

  test('setBusy maps to processing / idle with the given message', () {
    composer.setBusy(true, message: 'Saving edit');
    expect(composer.state, isA<ChatComposerState$Processing>());
    expect(composer.state.message, 'Saving edit');

    composer.setBusy(false, message: 'Finished editing');
    expect(composer.state, isA<ChatComposerState$Idle>());
    expect(composer.state.message, 'Finished editing');
  });

  test('commands keep processing while busy', () {
    composer.setBusy(true, message: 'Sending');
    composer.setEmojiIconState(ChatEnterEmojiIconState.keyboard);
    composer.beginReply(id: 1, title: 'A', subtitle: 'b');
    composer.clear();

    expect(composer.state.isProcessing, isTrue);
    expect(composer.emojiIconState, ChatEnterEmojiIconState.keyboard);
    expect(composer.mode, const ChatComposerMode.idle());
  });

  test('commands outside busy never emit processing', () {
    final seen = <bool>[];
    void onState() => seen.add(composer.state.isProcessing);
    composer.addListener(onState);
    composer.setEmojiIconState(ChatEnterEmojiIconState.keyboard);
    composer.beginEdit(id: 1, preview: 'x');
    composer.cancelMode();
    composer.setEnabled(false);
    composer.removeListener(onState);

    expect(seen, isNotEmpty);
    expect(seen, everyElement(isFalse));
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
