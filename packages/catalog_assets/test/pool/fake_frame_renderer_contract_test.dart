import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';

void main() {
  FrameRendererContract.run(() {
    final renderer = FakeFrameRenderer();
    return FrameRendererHarness(
      renderer: renderer,
      memory: ListFramePageMemory(),
      job: (slot, frame) => FrameJob(
        slot: slot,
        frame: frame,
        width: 48,
        height: 48,
        source: 'ok',
      ),
      unrenderable: (slot) => FrameJob(
        slot: slot,
        frame: 0,
        width: 48,
        height: 48,
        source: FakeFrameRenderer.rejected,
      ),
    );
  });
}
