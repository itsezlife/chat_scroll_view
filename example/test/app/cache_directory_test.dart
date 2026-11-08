/// Where the app keeps its caches on each platform: the folders every disk
/// tier is given (the Lottie frames, Giphy's stills and clips).
library;

import 'package:chat_scroll_view_example/src/app/environment_specific/cache_directory_vm.dart'
    as vm;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(r'$appCacheDirectory', () {
    const paths = MethodChannel('chat_scroll_view_example/paths');

    void answer(Object? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, (call) async => handler(call));
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(paths, null),
      );
    }

    test('is in the cache folder the Android activity names', () async {
      answer((call) => call.method == 'cacheDir' ? '/data/app/cache' : null);

      expect(
        await vm.$appCacheDirectory(
          'lottie_frames',
          operatingSystem: 'android',
        ),
        '/data/app/cache/lottie_frames',
      );
    });

    test('is none on Android when the activity does not answer', () async {
      expect(
        await vm.$appCacheDirectory(
          'lottie_frames',
          operatingSystem: 'android',
        ),
        isNull,
      );
    });

    test("is in the iOS app container's Library/Caches", () async {
      expect(
        await vm.$appCacheDirectory(
          'lottie_frames',
          operatingSystem: 'ios',
          environment: {'HOME': '/var/mobile/Containers/Data/Application/X'},
        ),
        '/var/mobile/Containers/Data/Application/X/Library/Caches/'
        'lottie_frames',
      );
      expect(
        await vm.$appCacheDirectory(
          'lottie_frames',
          operatingSystem: 'ios',
          environment: {},
        ),
        isNull,
        reason: 'no HOME',
      );
    });

    test('is the user cache folder on a desktop', () async {
      expect(
        await vm.$appCacheDirectory(
          'lottie_frames',
          operatingSystem: 'macos',
          environment: {'HOME': '/Users/me'},
        ),
        '/Users/me/Library/Caches/chat_scroll_view_example/lottie_frames',
      );
    });
  });

  group(r'$userCacheDirectory', () {
    test('is under the user cache folder of macOS', () {
      expect(
        vm.$userCacheDirectory(
          'lottie_frames',
          operatingSystem: 'macos',
          environment: {'HOME': '/Users/me'},
        ),
        '/Users/me/Library/Caches/chat_scroll_view_example/lottie_frames',
      );
    });

    test('follows XDG_CACHE_HOME on Linux, else ~/.cache', () {
      expect(
        vm.$userCacheDirectory(
          'lottie_frames',
          operatingSystem: 'linux',
          environment: {'XDG_CACHE_HOME': '/x', 'HOME': '/home/me'},
        ),
        '/x/chat_scroll_view_example/lottie_frames',
      );
      expect(
        vm.$userCacheDirectory(
          'lottie_frames',
          operatingSystem: 'linux',
          environment: {'HOME': '/home/me'},
        ),
        '/home/me/.cache/chat_scroll_view_example/lottie_frames',
      );
    });

    test('is under LOCALAPPDATA on Windows', () {
      expect(
        vm.$userCacheDirectory(
          'lottie_frames',
          operatingSystem: 'windows',
          environment: {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
        ),
        r'C:\Users\me\AppData\Local\chat_scroll_view_example\lottie_frames',
      );
    });

    test('is none where the platform names its folder itself', () {
      for (final os in ['android', 'ios', 'fuchsia']) {
        expect(
          vm.$userCacheDirectory(
            'lottie_frames',
            operatingSystem: os,
            environment: {'HOME': '/home/me'},
          ),
          isNull,
          reason: os,
        );
      }
      expect(
        vm.$userCacheDirectory(
          'lottie_frames',
          operatingSystem: 'macos',
          environment: {},
        ),
        isNull,
        reason: 'no HOME',
      );
    });
  });
}
