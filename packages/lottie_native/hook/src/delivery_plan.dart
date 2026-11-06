/// Where the native library comes from, decided as a list of steps the hook
/// tries in order. Every function here is pure; `hook/build.dart` does the
/// effects (download, cargo) and reads the answers.
///
/// The order, first match wins:
///
/// 1. `build_from_source` is on: compile.
/// 2. The manifest has a verified-by-hash artifact for this target and its
///    `sourceHash` is the hash of the current sources: download it, and if
///    that fails go to 3.
/// 3. Compile if this host can build the target and cargo exists; otherwise
///    no library at all.
library;

import 'prebuilt_manifest.dart';
import 'targets.dart';

/// The environment variable that turns [wantsBuildFromSource] on.
const buildFromSourceEnvironment = 'LOTTIE_NATIVE_BUILD_FROM_SOURCE';

/// Whether the app asked to compile the crate: the `build_from_source`
/// user-define (`true` or `'true'`), or the environment variable set to `1`.
///
/// Either source can switch it on; neither can switch the other off, so a
/// stray `0` in the environment cannot undo an app's pubspec.
bool wantsBuildFromSource({
  required Object? userDefine,
  required Map<String, String> environment,
}) =>
    userDefine == true ||
    userDefine == 'true' ||
    environment[buildFromSourceEnvironment] == '1';

/// Whether the manifest offers a library for this build.
sealed class PrebuiltMatch {
  const PrebuiltMatch();
}

/// [artifact] applies, to be downloaded from [url].
final class PrebuiltFound extends PrebuiltMatch {
  /// Creates the match.
  const PrebuiltFound(this.artifact, this.url);

  /// What to download and verify.
  final PrebuiltArtifact artifact;

  /// Where it is hosted.
  final Uri url;
}

/// No prebuilt applies; [reason] is a line for the build log. An empty
/// manifest is a normal reason, never an error.
final class PrebuiltMissing extends PrebuiltMatch {
  /// Creates the miss.
  const PrebuiltMissing(this.reason);

  /// Why nothing matched.
  final String reason;
}

/// Matches [target] against [manifest] (null when there is none).
///
/// [sourceHash] is the hash of the sources in the package now
/// (`computeSourceHash`): a manifest written for other sources describes
/// libraries that do not contain this code, so it must not apply.
PrebuiltMatch matchPrebuilt({
  required PrebuiltManifest? manifest,
  required String sourceHash,
  required LottieNativeTarget target,
}) {
  if (manifest == null) return const PrebuiltMissing('no prebuilts.json');
  final key = target.key;
  if (key == null) {
    return PrebuiltMissing('the manifest has no key for $target');
  }
  final artifact = manifest.artifactFor(key);
  if (artifact == null) {
    return PrebuiltMissing('the manifest lists no prebuilt for $key');
  }
  if (manifest.sourceHash != sourceHash) {
    return const PrebuiltMissing(
      'the prebuilt was built from other sources than these '
      '(sourceHash differs; run native/tool/source_hash.dart --write after '
      'publishing new libraries)',
    );
  }
  final url = manifest.urlOf(artifact);
  if (url == null) {
    return const PrebuiltMissing('the manifest has no baseUrl yet');
  }
  return PrebuiltFound(artifact, url);
}

/// One thing the hook can do to get a library.
sealed class DeliveryStep {
  const DeliveryStep();
}

/// Compile the crate with cargo.
final class CompileFromSource extends DeliveryStep {
  /// Creates the step.
  const CompileFromSource();
}

/// Download and verify [artifact]; on failure the hook goes on to the next
/// step.
final class UsePrebuilt extends DeliveryStep {
  /// Creates the step.
  const UsePrebuilt(this.artifact, this.url);

  /// What to download and verify.
  final PrebuiltArtifact artifact;

  /// Where it is hosted.
  final Uri url;
}

/// Emit no asset: the build succeeds, the probe reports `missingLibrary`.
final class NoLibrary extends DeliveryStep {
  /// Creates the step with the [reason] to warn about.
  const NoLibrary(this.reason);

  /// The warning for the build log.
  final String reason;
}

/// The steps for this build, in order; the last is never [UsePrebuilt].
///
/// [hostBuilds] is `LottieNativeTarget.buildableOn` for this host. [hasCargo]
/// only matters for the automatic fallback: an app that asked
/// for [buildFromSource] gets [CompileFromSource] regardless, so a missing
/// cargo fails loudly instead of quietly shipping no library.
List<DeliveryStep> planDelivery({
  required bool buildFromSource,
  required PrebuiltMatch match,
  required bool hasCargo,
  required bool hostBuilds,
  required LottieNativeTarget target,
}) {
  if (buildFromSource) return const [CompileFromSource()];

  final canCompile = hostBuilds && hasCargo;
  final last = canCompile
      ? const CompileFromSource()
      : NoLibrary(_noLibrary(match, target, hostBuilds));
  return [
    if (match case PrebuiltFound(:final artifact, :final url))
      UsePrebuilt(artifact, url),
    last,
  ];
}

String _noLibrary(
  PrebuiltMatch match,
  LottieNativeTarget target,
  bool hostBuilds,
) {
  // Without a host that can build it, the only route left is a prebuilt
  // library, so say that instead of leaving the app to guess.
  final why = !hostBuilds
      ? 'this host cannot build $target from source; publish or download a '
            'prebuilt library for it (README, "Native library delivery")'
      : 'cargo was not found, so it cannot compile from source';
  final prebuilt = switch (match) {
    PrebuiltFound() => 'the prebuilt library was not used',
    PrebuiltMissing(:final reason) => 'no prebuilt library: $reason',
  };
  return 'lottie_native has no native library for $target ($prebuilt; $why), '
      'so none is bundled and it is unavailable at run time '
      '(NativeLottieBinding.probe() reports missingLibrary).';
}
