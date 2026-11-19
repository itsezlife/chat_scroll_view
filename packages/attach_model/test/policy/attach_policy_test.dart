import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:test/test.dart';

void main() {
  group('forPlatform', () {
    test('maps each system to its family', () {
      expect(
        AttachPolicy.forPlatform(AttachHostPlatform.android, isWeb: false),
        isA<AttachPolicy$Android>(),
      );
      expect(
        AttachPolicy.forPlatform(AttachHostPlatform.iOS, isWeb: false),
        isA<AttachPolicy$IOS>(),
      );
      for (final desktop in [
        AttachHostPlatform.macOS,
        AttachHostPlatform.windows,
        AttachHostPlatform.linux,
        AttachHostPlatform.fuchsia,
      ]) {
        expect(
          AttachPolicy.forPlatform(desktop, isWeb: false),
          isA<AttachPolicy$Desktop>(),
        );
      }
    });

    test('a browser is the web family on every system', () {
      for (final platform in AttachHostPlatform.values) {
        expect(
          AttachPolicy.forPlatform(platform, isWeb: true),
          isA<AttachPolicy$Web>(),
        );
      }
    });
  });

  test('mobile caps the selection at 100, desktop and web do not', () {
    expect(const AttachPolicy.android().selectionCap, 100);
    expect(const AttachPolicy.ios().selectionCap, 100);
    expect(const AttachPolicy.desktop().selectionCap, isNull);
    expect(const AttachPolicy.web().selectionCap, isNull);
  });

  for (final policy in [
    const AttachPolicy.android(),
    const AttachPolicy.ios(),
    const AttachPolicy.desktop(),
    const AttachPolicy.web(),
  ]) {
    group('${policy.runtimeType}', () => AttachPolicyContract.run(policy));
  }
}
