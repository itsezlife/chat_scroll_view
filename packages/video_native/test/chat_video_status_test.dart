import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/src/native/chat_video_symbols.dart';

/// The numbers in `chat_video.h` and in `ChatVideoStatus` are written twice
/// by hand; this reads the header so they cannot drift apart.
void main() {
  final header = File('native/include/chat_video.h').readAsStringSync();

  int headerValue(String name) {
    final match = RegExp(
      'CHAT_VIDEO_$name\\s*=\\s*(-?\\d+)',
    ).firstMatch(header);
    if (match == null) fail('chat_video.h has no CHAT_VIDEO_$name');
    return int.parse(match.group(1)!);
  }

  test('ChatVideoStatus carries the header numbers', () {
    expect(ChatVideoStatus.endOfStream, headerValue('END_OF_STREAM'));
    expect(ChatVideoStatus.ok, headerValue('OK'));
    expect(ChatVideoStatus.invalidArgument, headerValue('INVALID_ARGUMENT'));
    expect(ChatVideoStatus.tooLarge, headerValue('TOO_LARGE'));
    expect(ChatVideoStatus.malformed, headerValue('MALFORMED'));
    expect(ChatVideoStatus.limitExceeded, headerValue('LIMIT_EXCEEDED'));
    expect(ChatVideoStatus.unsupported, headerValue('UNSUPPORTED'));
    expect(ChatVideoStatus.internal, headerValue('INTERNAL'));
    expect(ChatVideoStatus.badSize, headerValue('BAD_SIZE'));
    expect(ChatVideoStatus.decodeFailed, headerValue('DECODE_FAILED'));
  });

  test('the header lists no status the binding lacks', () {
    final statusEnum = RegExp(
      r'enum \{\s*CHAT_VIDEO_END_OF_STREAM.*?\};',
      dotAll: true,
    ).firstMatch(header)!.group(0)!;
    final names = RegExp(r'CHAT_VIDEO_([A-Z_]+)\s*=').allMatches(statusEnum);

    expect(names, hasLength(10));
  });

  test('the ABI version is the one the binding expects', () {
    expect(chatVideoExpectedAbiVersion, headerValue('ABI_VERSION'));
  });
}
