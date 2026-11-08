import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The fade of one surface's binding (ADR 022, "Readiness"): content that
/// arrives after the attach rises from transparent to opaque over [duration]
/// from the first frame it is drawn in; content there at the attach (a memory
/// hit) shows at once, so going back over loaded content never flickers.
///
/// It is the reference client's image fade (`ImageReceiver`: a bitmap that is
/// not a memory hit fades in over its thumbnail in
/// `DEFAULT_CROSSFADE_DURATION`). A glyph is never faded: it is text, not an
/// image that arrives.
///
/// Internal to the package: a surface keeps one per binding and reads
/// [opacityAt] when it paints.
@internal
final class AssetFade {
  /// The fade of the binding a surface just attached.
  AssetFade(this._binding)
    : _done = _binding.key is ContentKey$Unicode || _hasContent(_binding);

  /// How long arriving content takes to become opaque.
  static const Duration duration = Duration(milliseconds: 150);

  static bool _hasContent(AssetBinding binding) =>
      binding.readiness.stage.index >= AssetStage.firstFrame.index;

  final AssetBinding _binding;
  bool _done;
  Duration? _start;

  /// The opacity to draw the binding's content at in the frame at [frameTime]:
  /// 1 before it has content (what stands in is drawn as it is) and once the
  /// fade has run, otherwise rising from 0 over [duration] from the first
  /// call that saw content.
  double opacityAt(Duration frameTime) {
    if (_done || !_hasContent(_binding)) return 1;
    final start = _start ??= frameTime;
    final t = (frameTime - start).inMicroseconds / duration.inMicroseconds;
    if (t >= 1) _done = true;
    return t.clamp(0.0, 1.0);
  }
}
