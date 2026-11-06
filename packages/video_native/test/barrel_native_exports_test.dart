import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/video_native.dart';

/// On the VM the barrel still carries the FFI half of the API next to the
/// value types: a type it lost would fail to compile here.
void main() {
  test('the barrel exports the native types on the VM', () {
    final reachable = <Type>[
      VideoBinding,
      NativeVideoBinding,
      VideoInfo,
      VideoOpenResult,
      VideoFrameResult,
      VideoFrameStatus,
      VideoAvailability,
      VideoRejection,
    ];

    expect(reachable.toSet(), hasLength(reachable.length));
  });
}
