/// The environment variables `cargo build` needs per target: the NDK linker
/// for Android, the deployment target for iOS.
///
/// Kept apart from the hook entry so it is tested as a pure function.
library;

import 'package:code_assets/code_assets.dart';

import 'android_ndk.dart';
import 'targets.dart';

/// The lowest API level the NDK wrappers offered when this was written; the
/// hook always passes the app's level, so this only covers a config without
/// one.
const _defaultAndroidApi = 21;

/// The flag that aligns every PT_LOAD segment to 16 KB, which Google Play
/// requires of 64-bit apps targeting Android 15 and later. Always on: a
/// library aligned to 16 KB also loads on a 4 KB device.
const _androidPageFlags = ['-C', 'link-arg=-Wl,-z,max-page-size=16384'];

/// The variables to add to the process environment for building [target].
///
/// [environment] is the process environment, read only for flags the app
/// already set. [ndk] is required for Android and ignored elsewhere.
Map<String, String> cargoBuildEnvironment({
  required LottieNativeTarget target,
  required Map<String, String> environment,
  AndroidNdk? ndk,
}) {
  final triple = target.rustTriple;
  switch (target.os) {
    case OS.android:
      if (ndk == null || triple == null) {
        throw ArgumentError.value(
          ndk,
          'ndk',
          'an Android build needs the NDK and a supported triple '
              '(triple: $triple)',
        );
      }
      return {
        cargoTargetVariable(triple, 'LINKER'): ndk.linker(
          triple,
          target.androidApi ?? _defaultAndroidApi,
        ),
        cargoTargetVariable(triple, 'AR'): ndk.ar,
        'CARGO_ENCODED_RUSTFLAGS': [
          ..._userRustFlags(environment),
          ..._androidPageFlags,
        ].join(_flagSeparator),
      };
    case OS.iOS:
      return {
        if (target.iosVersion case final version?)
          'IPHONEOS_DEPLOYMENT_TARGET': '$version.0',
      };
    default:
      return const {};
  }
}

/// Cargo's separator inside `CARGO_ENCODED_RUSTFLAGS`.
const _flagSeparator = '\x1f';

/// The flags the app already set, in cargo's own precedence: the encoded
/// variable beats `RUSTFLAGS`. Setting the encoded variable ourselves would
/// hide `RUSTFLAGS`, so its flags are carried over.
List<String> _userRustFlags(Map<String, String> environment) {
  final encoded = environment['CARGO_ENCODED_RUSTFLAGS'];
  if (encoded != null && encoded.isNotEmpty) {
    return encoded.split(_flagSeparator);
  }
  final plain = environment['RUSTFLAGS'];
  if (plain != null) {
    return plain
        .split(RegExp(r'\s+'))
        .where((flag) => flag.isNotEmpty)
        .toList();
  }
  return const [];
}
