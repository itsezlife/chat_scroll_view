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
/// The drop events carry no pointer position, so the zone a drop lands in
/// is not known: a drop with no photo or video goes as files, any other as
/// media (the box's own options change it).
class AttachDropOverlay extends StatelessWidget {
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

  void _dropped(List<IntakeFile> files) {
    if (files.isEmpty) return;
    if (boxOpen?.value ?? false) return onDrop(files, asFiles: null);
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
    source: source,
    onDrop: _dropped,
    maxFileBytes: maxFileBytes,
    onRefused: onRefused,
    builder: (context, offer) => Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: offer == null ? 0 : 1,
              duration: ChromeMotionScope.of(
                context,
              ).speed.scale(const Duration(milliseconds: 200)),
              child: offer == null ? const SizedBox.shrink() : _zones(context),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _zones(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final open = boxOpen?.value ?? false;
    Widget zone(String key, String label) => Expanded(
      child: Container(
        key: ValueKey(key),
        margin: const EdgeInsets.all(10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ChromeThemeScope.attachOf(context).background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: ChromeThemeScope.paletteOf(context).accent,
            width: 2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ChromeThemeScope.paletteOf(context).onSurface,
            fontSize: 17,
          ),
        ),
      ),
    );
    return Column(
      children: open
          ? [zone('attach-drop-add', strings.dropAdd)]
          : [
              zone('attach-drop-files', strings.dropAsFiles),
              zone('attach-drop-media', strings.dropAsMedia),
            ],
    );
  }
}
