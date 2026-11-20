import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mpx_library/mpx_library.dart';

/// Called with a drop's files and the choice it made: as files (true), as
/// media (false), or added to the open box (null).
typedef AttachDropped =
    void Function(List<IntakeFile> files, {required bool? asFiles});

/// The **drop zones** over the host's chat region, on `mpx_library`'s drop
/// region: while files are dragged over it, two labelled zones (top "as
/// files", bottom "as media"), or one "Add items" zone while a confirm box
/// is open, fading in over 200 ms.
///
/// The zone under the pointer lights up and decides the drop; a drop that
/// arrives with no position goes as files when it has no photo or video,
/// else as media.
class AttachDropOverlay extends StatefulWidget {
  /// Zones over [child], fed by [source].
  const AttachDropOverlay({
    required this.source,
    required this.policy,
    required this.onDrop,
    required this.child,
    this.boxOpen,
    this.maxFileBytes,
    this.onRefused,
    super.key,
  });

  /// The platform's drop events.
  final DropSource source;

  /// The family's values (the confirm box's radius).
  final AttachSheetPolicy policy;

  /// Called on a drop.
  final AttachDropped onDrop;

  /// The chat region.
  final Widget child;

  /// Whether a confirm box is open (one "Add items" zone).
  final ValueListenable<bool>? boxOpen;

  /// The largest file a drop takes; larger ones are refused.
  final int? maxFileBytes;

  /// Called for each refused file.
  final void Function(DropRefusal reason, IntakeFile? file)? onRefused;

  @override
  State<AttachDropOverlay> createState() => _AttachDropOverlayState();
}

class _AttachDropOverlayState extends State<AttachDropOverlay> {
  /// Whether a point [dy] down a region [height] tall is in the top zone.
  static bool _inTop(double dy, double height) => dy < height / 2;

  // The region's height at the last layout, to place a drop's position.
  double _height = 0;

  void _dropped(IntakeDrop drop) {
    final files = drop.files;
    if (files.isEmpty) return;
    final onDrop = widget.onDrop;
    if (widget.boxOpen?.value ?? false) return onDrop(files, asFiles: null);
    if (drop.position case final at? when _height > 0) {
      return onDrop(files, asFiles: _inTop(at.dy, _height));
    }
    // No position: a drop with no photo or video goes as files.
    final media = files.any(
      (f) => switch (IntakeKind.classify(mimeType: f.mimeType, name: f.name)) {
        IntakeKind.photo || IntakeKind.video || IntakeKind.animation => true,
        IntakeKind.audio || IntakeKind.file => false,
      },
    );
    onDrop(files, asFiles: !media);
  }

  @override
  Widget build(BuildContext context) => IntakeDropRegion(
    source: widget.source,
    onDrop: _dropped,
    maxFileBytes: widget.maxFileBytes,
    onRefused: widget.onRefused,
    builder: (context, hover) => LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        final top = switch (hover?.position) {
          final at? => _inTop(at.dy, constraints.maxHeight),
          null => null,
        };
        return Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: hover == null ? 0 : 1,
                  duration: _fade(context),
                  child: hover == null
                      ? const SizedBox.shrink()
                      : _zones(context, top),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  static Duration _fade(BuildContext context) => ChromeMotionScope.of(
    context,
  ).speed.scale(const Duration(milliseconds: 200));

  Widget _zones(BuildContext context, bool? top) {
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final background = ChromeThemeScope.attachOf(context).background;
    final open = widget.boxOpen?.value ?? false;
    Widget zone(String key, String label, {required bool hovered}) => Expanded(
      child: AnimatedContainer(
        key: ValueKey(key),
        duration: _fade(context),
        margin: const EdgeInsets.all(10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? palette.surfaceSelected : background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.accent, width: hovered ? 3 : 2),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: ChromeTypography.of(
            context,
          ).copyWith(color: palette.onSurface, fontSize: 17),
        ),
      ),
    );
    return Column(
      children: open
          ? [zone('attach-drop-add', strings.dropAdd, hovered: true)]
          : [
              zone(
                'attach-drop-files',
                strings.dropAsFiles,
                hovered: top ?? false,
              ),
              zone(
                'attach-drop-media',
                strings.dropAsMedia,
                hovered: top == false,
              ),
            ],
    );
  }
}
