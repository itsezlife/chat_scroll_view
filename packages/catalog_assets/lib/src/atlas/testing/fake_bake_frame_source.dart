import 'package:catalog_assets/src/atlas/bake_frame_source.dart';

/// A [BakeFrameSource] whose frames a test delivers with [pump].
final class FakeBakeFrameSource implements BakeFrameSource {
  /// Creates a source reporting [budget] as the vsync interval.
  FakeBakeFrameSource({this.budget = const Duration(microseconds: 16667)});

  /// Vsync interval reported with every frame.
  final Duration budget;

  final List<BakeFrameCallback> _pending = <BakeFrameCallback>[];

  /// Whether any request is waiting for a frame.
  bool get hasPendingRequest => _pending.isNotEmpty;

  /// Requests made so far, delivered or not.
  int requested = 0;

  @override
  BakeFrameCancel requestFrame(BakeFrameCallback onFrame) {
    requested++;
    _pending.add(onFrame);
    return () => _pending.remove(onFrame);
  }

  /// Delivers one frame to every request made before this call, reporting
  /// [cost] as the engine's latest measurement (null: nothing new).
  void pump({Duration? cost}) {
    final due = List<BakeFrameCallback>.of(_pending);
    _pending.clear();
    for (final callback in due) {
      callback(BakeFrame(budget: budget, cost: cost));
    }
  }
}
