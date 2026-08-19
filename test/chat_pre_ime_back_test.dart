import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNative implements ChatPreImeBackNative {
  int acquireCount = 0;
  int releaseCount = 0;

  @override
  Future<void> acquire() async => acquireCount++;

  @override
  Future<void> release() async => releaseCount++;
}

void main() {
  tearDown(ChatPreImeBackBinding.debugReset);

  test(
    'nested claims: top handles back; below is untouched until pop',
    () async {
      final native = _FakeNative();
      ChatPreImeBackBinding.native = native;

      final handled = <String>[];
      final lower = ChatPreImeBackClaim.push(() async {
        handled.add('lower');
        return true;
      });
      final top = ChatPreImeBackClaim.push(() async {
        handled.add('top');
        return true;
      });

      expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
      expect(handled, ['top']);

      top.pop();
      expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
      expect(handled, ['top', 'lower']);

      lower.pop();
      expect(await ChatPreImeBackBinding.handleNativeBack(), isFalse);
      expect(handled, ['top', 'lower']);
    },
  );

  test('empty stack: no native acquire; release after last pop', () async {
    final native = _FakeNative();
    ChatPreImeBackBinding.native = native;

    expect(native.acquireCount, 0);
    expect(native.releaseCount, 0);

    final first = ChatPreImeBackClaim.push(() async => true);
    final second = ChatPreImeBackClaim.push(() async => true);
    expect(native.acquireCount, 1);
    expect(native.releaseCount, 0);

    second.pop();
    expect(native.acquireCount, 1);
    expect(native.releaseCount, 0);

    first.pop();
    expect(native.acquireCount, 1);
    expect(native.releaseCount, 1);
  });

  test('missing native adapter still delivers back to the top claim', () async {
    var topHandled = false;
    ChatPreImeBackClaim.push(() async {
      topHandled = true;
      return true;
    });

    expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
    expect(topHandled, isTrue);
  });
}
