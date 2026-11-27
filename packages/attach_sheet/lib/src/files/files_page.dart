import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/files/intake_items.dart';
import 'package:attach_sheet/src/gallery/gallery_page.dart';
import 'package:attach_sheet/src/limits/attach_denied_page.dart';
import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/page/attach_page_scope.dart';
import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:attach_sheet/src/panel/selection_listenable.dart';
import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mpx_library/mpx_library.dart';

/// Where the Files page's recent files come from: the host's (the files the
/// user sent before, a downloads folder).
abstract interface class RecentFilesSource {
  /// The recent files, newest first.
  Future<List<IntakeFile>> load();
}

/// The stock **Files page**: "Choose from gallery" (the gallery as files),
/// "Choose from files" (the system file dialog), and the host's recent
/// files. Picks join the open's attach selection as files or audio, checked
/// against the attach limits.
abstract final class FilesPage {
  /// The Files page over [intake]; [library] enables "Choose from
  /// gallery", [recent] the recent files section.
  static AttachPage create({
    required FileIntake intake,
    required String label,
    required Widget icon,
    MediaLibrary? library,
    RecentFilesSource? recent,
    IntakeItems? items,
  }) {
    final known = items ?? IntakeItems();
    return AttachPage(
      id: AttachPageId.files,
      label: label,
      icon: icon,
      builder: (context, scope) => _FilesView(
        scope: scope,
        intake: intake,
        library: library,
        recent: recent,
        items: known,
      ),
    );
  }
}

/// Adds [files] to [panel]'s selection as files or audio; each refusal
/// goes to the host.
void _addFiles(
  AttachSendController panel,
  IntakeItems items,
  Iterable<IntakeFile> files,
) {
  for (final file in files) {
    final item = items.itemOf(file, asMedia: false);
    if (panel.selection.contains(item.id)) continue;
    if (panel.selection.toggle(item) case AttachToggle$Refused(:final reason)) {
      panel.refused(item, reason);
    }
  }
}

class _FilesView extends StatefulWidget {
  const _FilesView({
    required this.scope,
    required this.intake,
    required this.library,
    required this.recent,
    required this.items,
  });

  final AttachPageScope scope;
  final FileIntake intake;
  final MediaLibrary? library;
  final RecentFilesSource? recent;
  final IntakeItems items;

  @override
  State<_FilesView> createState() => _FilesViewState();
}

class _FilesViewState extends State<_FilesView> {
  late final Future<List<IntakeFile>>? _$recent = widget.recent?.load();

  AttachSendController get _panel => widget.scope.panel;

  Future<void> _pickFiles() async {
    final files = await widget.intake.pickFiles(
      multiple: !_panel.selection.limits.singleSelect,
    );
    if (!mounted) return;
    _addFiles(_panel, widget.items, files);
  }

  Future<void> _pickFromGallery() async {
    final library = widget.library;
    if (library == null) return;
    final send = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        pageBuilder: (context, _, _) => ChromeTextRoot(
          child: _GalleryAsFiles(library: library, panel: _panel),
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (send ?? false) _panel.send((o) => o.copyWith(asFiles: true));
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final gate = _panel.capabilities;
    return ListenableBuilder(
      // The chat's rights by group: a slow mode tick does not reach here.
      listenable: Listenable.merge([
        SelectionListenable(_panel.selection),
        ?gate?.sending,
      ]),
      builder: (context, _) => switch (gate) {
        // Files denied: the tab stays, its content is the denial text.
        final gate? when gate.denies(AttachKind.file) => AttachDeniedPage(
          key: const ValueKey('attach-files-denied'),
          text: gate.denialText(
            AttachKind.file,
            form: switch (_panel.policy.deniedForm) {
              AttachDeniedForm.text => 'filesPage',
              AttachDeniedForm.emptyState => 'filesEmptyState',
            },
          ),
          form: _panel.policy.deniedForm,
          controller: widget.scope.scrollController,
        ),
        _ => _content(context, strings, palette),
      },
    );
  }

  Widget _content(
    BuildContext context,
    AttachStrings strings,
    ChromePalette palette,
  ) => ListView(
    controller: widget.scope.scrollController,
    padding: const EdgeInsets.only(top: 16, bottom: 120),
    children: [
      if (widget.library != null)
        _ActionRow(
          key: const ValueKey('attach-files-gallery'),
          label: strings.chooseFromGallery,
          palette: palette,
          onTap: () => unawaited(_pickFromGallery()),
        ),
      _ActionRow(
        key: const ValueKey('attach-files-dialog'),
        label: strings.chooseFromFiles,
        palette: palette,
        onTap: () => unawaited(_pickFiles()),
      ),
      for (final item in _panel.selection.items)
        if (widget.items.fileOf(item.id) != null)
          // A pick of a kind the chat denied since is marked: the send
          // is refused while it is there.
          Opacity(
            key: ValueKey('attach-files-picked-${item.id}'),
            opacity: _panel.capabilities?.isDeniedPick(item) ?? false ? 0.5 : 1,
            child: _FileRow(
              name: item.facts.name ?? '',
              size: item.facts.byteSize,
              order: _panel.selection.orderOf(item.id),
              palette: palette,
              onTap: () => _panel.selection.remove(item.id),
            ),
          ),
      if (_$recent case final recent?)
        FutureBuilder<List<IntakeFile>>(
          future: recent,
          builder: (context, snapshot) => _Recent(
            header: strings.recentFiles,
            files: snapshot.data,
            palette: palette,
            orderOf: (file) => _panel.selection.orderOf(
              widget.items.itemOf(file, asMedia: false).id,
            ),
            onTap: (file) {
              final item = widget.items.itemOf(file, asMedia: false);
              if (_panel.selection.contains(item.id)) {
                _panel.selection.remove(item.id);
              } else {
                _addFiles(_panel, widget.items, [file]);
              }
            },
          ),
        ),
    ],
  );
}

class _Recent extends StatelessWidget {
  const _Recent({
    required this.header,
    required this.files,
    required this.palette,
    required this.orderOf,
    required this.onTap,
  });

  /// Rows of placeholder while the source loads.
  static const int loadingRows = 11;

  final String header;
  final List<IntakeFile>? files;
  final ChromePalette palette;
  final int? Function(IntakeFile file) orderOf;
  final ValueChanged<IntakeFile> onTap;

  @override
  Widget build(BuildContext context) {
    final files = this.files;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            header,
            style: ChromeTypography.of(
              context,
            ).copyWith(color: palette.onSurfaceMuted, fontSize: 13),
          ),
        ),
        if (files == null)
          for (var i = 0; i < loadingRows; i++)
            Container(
              key: ValueKey('attach-files-shimmer-$i'),
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: palette.surfaceDim,
                borderRadius: BorderRadius.circular(8),
              ),
            )
        else
          for (final file in files)
            _FileRow(
              key: ValueKey('attach-files-recent-${file.name}'),
              name: file.name,
              size: file.size,
              order: orderOf(file),
              palette: palette,
              onTap: () => onTap(file),
            ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.palette,
    required this.onTap,
    super.key,
  });

  final String label;
  final ChromePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          label,
          style: ChromeTypography.of(
            context,
          ).copyWith(color: palette.accent, fontSize: 16),
        ),
      ),
    ),
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.size,
    required this.order,
    required this.palette,
    required this.onTap,
    super.key,
  });

  final String name;
  final int? size;
  final int? order;
  final ChromePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: order != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: order == null ? null : palette.accent,
                border: Border.all(color: palette.accent, width: 1.5),
              ),
              child: order == null
                  ? null
                  : Text(
                      '$order',
                      style: ChromeTypography.of(
                        context,
                      ).copyWith(color: palette.onAccent, fontSize: 12),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ChromeTypography.of(
                  context,
                ).copyWith(color: palette.onSurface, fontSize: 15),
              ),
            ),
            if (size case final size?)
              Text(
                _sizeOf(size),
                style: ChromeTypography.of(
                  context,
                ).copyWith(color: palette.onSurfaceMuted, fontSize: 13),
              ),
          ],
        ),
      ),
    ),
  );

  static String _sizeOf(int bytes) => switch (bytes) {
    < 1024 => '$bytes B',
    < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
    _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
  };
}

/// The gallery as files, over the sheet: picks join the same selection and
/// Send closes it and sends everything as files.
class _GalleryAsFiles extends StatelessWidget {
  const _GalleryAsFiles({required this.library, required this.panel});

  final MediaLibrary library;
  final AttachSendController panel;

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final strings = ChromeStringsScope.attachOf(context);
    return ColoredBox(
      color: tokens.background,
      child: Column(
        children: [
          Expanded(
            child: GalleryView(
              library: library,
              panel: panel,
              showsOverflow: false,
            ),
          ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                GestureDetector(
                  key: const ValueKey('attach-files-gallery-back'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(false),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      strings.cancelAction,
                      style: ChromeTypography.of(
                        context,
                      ).copyWith(color: palette.accent, fontSize: 16),
                    ),
                  ),
                ),
                const Spacer(),
                ListenableBuilder(
                  listenable: SelectionListenable(panel.selection),
                  builder: (context, _) => GestureDetector(
                    key: const ValueKey('attach-files-gallery-send'),
                    behavior: HitTestBehavior.opaque,
                    onTap: panel.selection.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(true),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${strings.sendAction} (${panel.selection.length})',
                        style: ChromeTypography.of(context).copyWith(
                          color: panel.selection.isEmpty
                              ? palette.onSurfaceMuted
                              : palette.accent,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
