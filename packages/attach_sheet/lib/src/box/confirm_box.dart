import 'dart:async';
import 'dart:math' as math;

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/box/confirm_box_controller.dart';
import 'package:attach_sheet/src/panel/attach_panel.dart';
import 'package:attach_sheet/src/policy/attach_panel_style.dart';
import 'package:attach_sheet/src/policy/confirm_box_style.dart';
import 'package:attach_sheet/src/sheet/attach_outcome.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';

/// Draws a send group's media in the box: the host's album layout (the
/// chat's message mosaic) for [items] laid out [width] wide.
typedef GroupPreviewBuilder =
    Widget Function(BuildContext context, List<AttachItem> items, double width);

/// Draws one item's picture in the box; the host's (from the intake file).
typedef ItemThumbnailBuilder =
    Widget Function(BuildContext context, AttachItem item);

/// The **confirm box**: the desktop and web modal every intake route leads
/// to, with the family's previews, options, reorder, per-item actions,
/// caption, send menu and keys.
abstract final class ConfirmBox {
  /// Shows the box of [controller] and completes with its outcome: a send,
  /// or a cancel with the caption to give back to the composer.
  static Future<AttachOutcome> show(
    BuildContext context, {
    required ConfirmBoxController controller,
    GroupPreviewBuilder? groupPreview,
    ItemThumbnailBuilder? thumbnail,
  }) async {
    final style = controller.style;
    final speed = ChromeMotionScope.of(context).speed;
    final outcome = await Navigator.of(context).push<AttachOutcome>(
      PageRouteBuilder<AttachOutcome>(
        opaque: false,
        barrierDismissible: style.dismissesOnOutsideTap,
        barrierColor: Color.fromRGBO(0, 0, 0, style.dimOpacity),
        transitionDuration: speed.scale(style.open.duration),
        reverseTransitionDuration: speed.scale(style.close.duration),
        transitionsBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: style.open.curve,
            reverseCurve: style.close.curve,
          );
          final rise = speed.isInstant ? 0.0 : style.rise;
          return FadeTransition(
            opacity: curved,
            child: AnimatedBuilder(
              animation: curved,
              child: child,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, rise * (1 - curved.value)),
                child: child,
              ),
            ),
          );
        },
        pageBuilder: (context, _, _) => ConfirmBoxView(
          controller: controller,
          groupPreview: groupPreview,
          thumbnail: thumbnail,
        ),
      ),
    );
    return outcome ??
        AttachOutcome.cancelled(controller.panel.caption.richText);
  }
}

/// The box itself, for [ConfirmBox.show] (and tests).
class ConfirmBoxView extends StatefulWidget {
  /// The box of [controller].
  const ConfirmBoxView({
    required this.controller,
    this.groupPreview,
    this.thumbnail,
    super.key,
  });

  /// The box's state.
  final ConfirmBoxController controller;

  /// The host's media group layout; null for a plain thumbnail strip.
  final GroupPreviewBuilder? groupPreview;

  /// The host's item pictures; null for a placeholder by kind.
  final ItemThumbnailBuilder? thumbnail;

  @override
  State<ConfirmBoxView> createState() => _ConfirmBoxViewState();
}

class _ConfirmBoxViewState extends State<ConfirmBoxView> {
  final FocusNode _$keys = FocusNode(debugLabel: 'ConfirmBox');

  ConfirmBoxController get _box => widget.controller;
  ConfirmBoxStyle get _style => _box.style;

  @override
  void initState() {
    super.initState();
    _box.sendHandler = _sent;
    _box.selection.changes.addListener(_selectionChanged);
    _box.panel.options.addListener(_rebuild);
    _box.remember.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _box.panel.caption.focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _box.sendHandler = null;
    _box.selection.changes.removeListener(_selectionChanged);
    _box.panel.options.removeListener(_rebuild);
    _box.remember.removeListener(_rebuild);
    _$keys.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _selectionChanged() {
    if (!mounted) return;
    // Deleting the last item closes the box and returns the caption.
    if (_box.selection.isEmpty) {
      _cancel();
      return;
    }
    setState(() {});
  }

  void _sent(SendRequest request) {
    _box.remembered(request.options);
    Navigator.of(context).pop(AttachOutcome.send(request));
  }

  void _cancel() => Navigator.of(
    context,
  ).pop(AttachOutcome.cancelled(_box.panel.caption.richText));

  bool get _composing {
    final value = _box.panel.caption.text.value;
    return value.composing.isValid && !value.composing.isCollapsed;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        !keys.isShiftPressed) {
      // Never while an input method is composing.
      if (_composing) return KeyEventResult.ignored;
      _box.panel.send();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyO &&
        (keys.isControlPressed || keys.isMetaPressed)) {
      unawaited(_box.pickAndAdd());
      return KeyEventResult.handled;
    }
    if (_style.printableKeyFocusesCaption &&
        !_box.panel.caption.focusNode.hasFocus &&
        (event.character?.trim().isNotEmpty ?? false) &&
        !keys.isControlPressed &&
        !keys.isMetaPressed) {
      _box.panel.caption.focusNode.requestFocus();
    }
    return KeyEventResult.ignored;
  }

  String _title(AttachStrings strings) {
    final items = _box.selection.items;
    final n = items.length;
    final asFiles = _box.panel.options.value.asFiles;
    final allMedia = !asFiles && items.every((i) => i.kind.isMedia);
    final allPhotos =
        !asFiles && items.every((i) => i.kind == AttachKind.photo);
    final allVideos =
        !asFiles && items.every((i) => i.kind == AttachKind.video);
    switch (_style.titles) {
      case ConfirmBoxTitles.selected:
        if (n == 1) {
          return switch (asFiles ? AttachKind.file : items.single.kind) {
            AttachKind.photo => strings.sendPhoto,
            AttachKind.video || AttachKind.animation => strings.sendVideo,
            AttachKind.audio || AttachKind.file => strings.sendFile,
          };
        }
        return allMedia ? strings.photosSelected(n) : strings.filesSelected(n);
      case ConfirmBoxTitles.sendCount:
        if (n == 1 && !asFiles && items.single.kind == AttachKind.animation) {
          return strings.sendGif;
        }
        if (n == 1) {
          return allPhotos
              ? strings.sendPhoto
              : allVideos
              ? strings.sendVideo
              : strings.sendFile;
        }
        if (allPhotos) return strings.sendPhotos(n);
        if (allVideos) return strings.sendVideos(n);
        return strings.sendFiles(n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final tokens = ChromeThemeScope.attachOf(context);
    final size = MediaQuery.sizeOf(context);
    final maxHeight = math.min(
      _style.maxHeight ?? double.infinity,
      size.height - 48,
    );
    return Focus(
      focusNode: _$keys,
      onKeyEvent: _key,
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            key: const ValueKey('confirm-box'),
            width: math.min(_style.width, size.width - 16),
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: tokens.background,
              borderRadius: BorderRadius.circular(_style.radius),
              boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 24)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(strings, palette),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: (_style.width - _style.previewWidth) / 2,
                    ),
                    child: _Blocks(
                      box: _box,
                      groupPreview: widget.groupPreview,
                      thumbnail: widget.thumbnail,
                    ),
                  ),
                ),
                if (_style.options == ConfirmBoxOptions.checkboxes)
                  _Checkboxes(box: _box, strings: strings, palette: palette),
                AttachCaptionBar(controller: _box.panel),
                if (_style.options == ConfirmBoxOptions.checkboxes)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _TextButton(
                      key: const ValueKey('confirm-box-cancel'),
                      label: strings.cancelAction,
                      palette: palette,
                      onTap: _cancel,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AttachStrings strings, ChromePalette palette) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _title(strings),
            key: const ValueKey('confirm-box-title'),
            style: TextStyle(
              color: palette.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_style.options == ConfirmBoxOptions.moreMenu)
          GestureDetector(
            key: const ValueKey('confirm-box-more'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _openMore(strings),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.more_vert, color: palette.iconIdle),
            ),
          ),
      ],
    ),
  );

  void _openMore(AttachStrings strings) {
    final box = _box;
    final options = box.panel.options.value;
    final shown = box.visibility;
    final hasMedia = box.selection.items.any((i) => i.kind.isMedia);
    final many = box.selection.length > 1;
    final groupable =
        box.selection.length > 1 &&
        box.selection.limits.groupingAllowed &&
        !box.selection.items.any((i) => i.kind == AttachKind.animation);
    final anchor =
        (context.findRenderObject()! as RenderBox).localToGlobal(Offset.zero) &
        const Size(1, 1);
    unawaited(
      AttachMenu.show(
        context,
        anchor: anchor.translate(_style.width - 8, 40),
        entries: [
          AttachMenuEntry(
            id: 'more-add',
            label: strings.addItems,
            onSelected: (_) => box.pickAndAdd(),
          ),
          if (hasMedia && options.asFiles)
            AttachMenuEntry(
              id: 'more-as-media',
              label: strings.sendAsMedia,
              onSelected: (_) async => box.asFiles = false,
            )
          else if (shown.sendAsFile)
            AttachMenuEntry(
              id: 'more-as-files',
              label: many ? strings.sendAsFiles : strings.sendAsFile,
              onSelected: (_) async => box.asFiles = true,
            ),
          if (groupable)
            AttachMenuEntry(
              id: options.grouped ? 'more-ungroup' : 'more-group',
              label: options.grouped ? strings.ungroupAll : strings.groupAll,
              onSelected: (_) async => box.grouped = !options.grouped,
            ),
          if (shown.spoiler)
            AttachMenuEntry(
              id: 'more-spoiler',
              label: box.panel.allSpoilered
                  ? strings.disableSpoiler
                  : strings.enableSpoiler,
              onSelected: (_) async =>
                  box.panel.runOverflow(AttachOverflowItem.spoiler),
            ),
          if (shown.captionAbove)
            AttachMenuEntry(
              id: 'more-caption',
              label: options.captionAbove
                  ? strings.captionBelow
                  : strings.captionAbove,
              onSelected: (_) async =>
                  box.panel.runOverflow(AttachOverflowItem.captionAbove),
            ),
        ],
      ),
    );
  }
}

class _Checkboxes extends StatelessWidget {
  const _Checkboxes({
    required this.box,
    required this.strings,
    required this.palette,
  });

  final ConfirmBoxController box;
  final AttachStrings strings;
  final ChromePalette palette;

  @override
  Widget build(BuildContext context) {
    final shown = box.visibility;
    final options = box.panel.options.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shown.groupCheckbox)
            _Check(
              key: const ValueKey('confirm-box-group'),
              label: strings.groupItems,
              value: options.grouped,
              palette: palette,
              onChanged: (v) => box.grouped = v,
            ),
          if (shown.asDocumentsCheckbox)
            _Check(
              key: const ValueKey('confirm-box-as-documents'),
              label: strings.sendAsDocuments,
              value: options.asFiles,
              palette: palette,
              onChanged: (v) => box.asFiles = v,
            ),
          if (shown.remember)
            _Check(
              key: const ValueKey('confirm-box-remember'),
              label: strings.remember,
              value: box.remember.value,
              palette: palette,
              onChanged: (v) => box.remember.value = v,
            ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.value,
    required this.palette,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ChromePalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value ? palette.accent : null,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: palette.accent, width: 1.5),
              ),
              child: value
                  ? Icon(Icons.check, size: 14, color: palette.onAccent)
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(color: palette.onSurface, fontSize: 14),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    required this.palette,
    required this.onTap,
    super.key,
  });

  final String label;
  final ChromePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 20, 14),
      child: Text(label, style: TextStyle(color: palette.accent, fontSize: 15)),
    ),
  );
}

/// The previews: the send plan's groups as the box draws them.
class _Blocks extends StatelessWidget {
  const _Blocks({
    required this.box,
    required this.groupPreview,
    required this.thumbnail,
  });

  final ConfirmBoxController box;
  final GroupPreviewBuilder? groupPreview;
  final ItemThumbnailBuilder? thumbnail;

  @override
  Widget build(BuildContext context) {
    final style = box.style;
    final plan = planSend(
      SendRequest(
        items: box.selection.items,
        caption: RichText.empty,
        options: box.panel.options.value,
      ),
      box.selection.policy,
      box.selection.limits,
    );
    final sends = switch (plan) {
      SendPlan$Ready(:final sends) => sends,
      SendPlan$Rejected() => const <PlannedSend>[],
    };
    final children = <Widget>[];
    for (final send in sends) {
      if (children.isNotEmpty)
        children.add(SizedBox(height: style.blockSpacing));
      switch (send) {
        case PlannedSend$Group(:final items, form: SendForm.media):
          children.add(
            groupPreview?.call(context, items, style.previewWidth) ??
                _Strip(box: box, items: items, thumbnail: thumbnail),
          );
        case PlannedSend$Single(:final item, form: SendForm.media):
          final cap = math.min(
            style.singleMediaMaxHeight.widthShare * style.previewWidth,
            style.singleMediaMaxHeight.cap,
          );
          children.add(
            _ItemFrame(
              box: box,
              item: item,
              child: SizedBox(
                key: ValueKey('confirm-box-single-${item.id}'),
                width: style.previewWidth,
                height: cap,
                child: _thumb(context, thumbnail, item),
              ),
            ),
          );
        case PlannedSend$Group(:final items):
          for (final item in items) {
            children.add(_FileRow(box: box, item: item, thumbnail: thumbnail));
          }
        case PlannedSend$Single(:final item):
          children.add(_FileRow(box: box, item: item, thumbnail: thumbnail));
        case PlannedSend$Text():
          break;
      }
    }
    return Column(
      key: const ValueKey('confirm-box-blocks'),
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

Widget _thumb(
  BuildContext context,
  ItemThumbnailBuilder? builder,
  AttachItem item,
) {
  if (builder != null) return builder(context, item);
  final palette = ChromeThemeScope.paletteOf(context);
  return ColoredBox(
    color: palette.surfaceDim,
    child: Center(
      child: Icon(switch (item.kind) {
        AttachKind.photo => Icons.image_outlined,
        AttachKind.video || AttachKind.animation => Icons.movie_outlined,
        AttachKind.audio => Icons.music_note_outlined,
        AttachKind.file => Icons.insert_drive_file_outlined,
      }, color: palette.iconIdle),
    ),
  );
}

/// A media group without the host's layout: a strip of square thumbs, which
/// reorder by drag where the family allows.
class _Strip extends StatefulWidget {
  const _Strip({
    required this.box,
    required this.items,
    required this.thumbnail,
  });

  final ConfirmBoxController box;
  final List<AttachItem> items;
  final ItemThumbnailBuilder? thumbnail;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  int? _from;
  double _dx = 0;
  int? _settling;

  static const double _gap = 2;

  double get _extent {
    final width = widget.box.style.previewWidth;
    final n = math.min(widget.items.length, 5);
    return (width - _gap * (n - 1)) / n;
  }

  int _target(int from) => (from + (_dx / (_extent + _gap)).round()).clamp(
    0,
    widget.items.length - 1,
  );

  @override
  Widget build(BuildContext context) {
    final reorder = widget.box.policy.boxReorder;
    final extent = _extent;
    final rows = (widget.items.length / 5).ceil();
    final from = _from;
    final to = from == null ? null : _target(from);
    double leftOf(int slot) => (slot % 5) * (extent + _gap);
    double topOf(int slot) => (slot ~/ 5) * (extent + _gap);
    int slotOf(int index) {
      if (from == null || to == null || index == from) return index;
      if (from < to && index > from && index <= to) return index - 1;
      if (from > to && index < from && index >= to) return index + 1;
      return index;
    }

    return SizedBox(
      key: const ValueKey('confirm-box-strip'),
      width: widget.box.style.previewWidth,
      height: rows * extent + (rows - 1) * _gap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < widget.items.length; i++)
            if (i == from)
              Positioned(
                left: leftOf(i) + _dx,
                top: topOf(i),
                width: extent,
                height: extent,
                child: _thumbAt(i, reorder, dragging: true),
              )
            else
              AnimatedPositioned(
                duration: _settling == i
                    ? (reorder?.settle.duration ?? Duration.zero)
                    : (reorder?.neighbours.duration ?? Duration.zero),
                curve: reorder?.neighbours.curve ?? Curves.linear,
                left: leftOf(slotOf(i)),
                top: topOf(slotOf(i)),
                width: extent,
                height: extent,
                child: _thumbAt(i, reorder, dragging: false),
              ),
        ],
      ),
    );
  }

  Widget _thumbAt(int i, ConfirmBoxReorder? reorder, {required bool dragging}) {
    final item = widget.items[i];
    final shrink = dragging ? (reorder?.shrink ?? 0) : 0.0;
    Widget thumb = _ItemFrame(
      box: widget.box,
      item: item,
      child: AnimatedPadding(
        duration: reorder?.lift.duration ?? Duration.zero,
        curve: reorder?.lift.curve ?? Curves.linear,
        padding: EdgeInsets.all(shrink),
        child: SizedBox.expand(
          key: ValueKey('confirm-box-thumb-${item.id}'),
          child: _thumb(context, widget.thumbnail, item),
        ),
      ),
    );
    if (reorder != null && widget.box.style.reorders) {
      thumb = GestureDetector(
        onHorizontalDragStart: (_) => setState(() {
          _from = i;
          _dx = 0;
        }),
        onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
        onHorizontalDragEnd: (_) => _drop(),
        onHorizontalDragCancel: _drop,
        child: thumb,
      );
    }
    return thumb;
  }

  void _drop() {
    final from = _from;
    if (from == null) return;
    final to = _target(from);
    setState(() {
      _from = null;
      _dx = 0;
      _settling = to;
    });
    if (to == from) return;
    // The strip is one group; move by the items' places in the selection.
    final selection = widget.box.selection;
    final ids = [for (final item in selection.items) item.id];
    selection.reorder(
      ids.indexOf(widget.items[from].id),
      ids.indexOf(widget.items[to].id),
    );
  }
}

/// A preview with its actions: the family's pill (delete; the editor is not
/// in v1) and, on desktop, a right-click menu.
class _ItemFrame extends StatefulWidget {
  const _ItemFrame({
    required this.box,
    required this.item,
    required this.child,
  });

  final ConfirmBoxController box;
  final AttachItem item;
  final Widget child;

  @override
  State<_ItemFrame> createState() => _ItemFrameState();
}

class _ItemFrameState extends State<_ItemFrame> {
  bool _hover = false;

  ConfirmBoxController get _box => widget.box;

  void _delete() => _box.selection.remove(widget.item.id);

  void _menu(Offset at) {
    final strings = ChromeStringsScope.attachOf(context);
    final item = widget.item;
    unawaited(
      AttachMenu.show(
        context,
        anchor: at & const Size(1, 1),
        entries: [
          AttachMenuEntry(
            id: 'item-delete',
            label: strings.deleteItem,
            onSelected: (_) async => _delete(),
          ),
          AttachMenuEntry(
            id: 'item-replace',
            label: strings.replaceItem,
            onSelected: (_) => _box.replace(item.id),
          ),
          if (item.kind.isMedia && _box.selection.limits.spoilerAllowed)
            AttachMenuEntry(
              id: 'item-spoiler',
              label: item.spoiler
                  ? strings.disableSpoiler
                  : strings.enableSpoiler,
              onSelected: (_) async => _box.selection.update(
                item.id,
                (i) => i.copyWith(spoiler: !i.spoiler),
              ),
            ),
          if (item.kind.isMedia && _box.selection.limits.timerAllowed)
            AttachMenuEntry(
              id: 'item-timer',
              label: strings.setTimer,
              onSelected: (context) async {
                final timer = await _box.host.pickTimer(context);
                if (timer == null) return;
                _box.selection.update(item.id, (i) => i.copyWith(timer: timer));
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final style = _box.style;
    final pill = switch (style.itemActions) {
      ConfirmBoxItemActions.pillAndMenu => true,
      ConfirmBoxItemActions.hoverPill => _hover,
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapUp: style.itemActions == ConfirmBoxItemActions.pillAndMenu
            ? (d) => _menu(d.globalPosition)
            : null,
        child: Stack(
          children: [
            widget.child,
            if (pill)
              PositionedDirectional(
                top: 5,
                end: 5,
                child: LayoutBuilder(
                  builder: (context, _) => Container(
                    height: 26,
                    decoration: BoxDecoration(
                      color: palette.shadow,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (style.itemActions ==
                                ConfirmBoxItemActions.hoverPill &&
                            widget.item.kind.isMedia)
                          _PillButton(
                            key: ValueKey(
                              'confirm-box-spoiler-${widget.item.id}',
                            ),
                            icon: Icons.blur_on,
                            onTap: () => _box.selection.update(
                              widget.item.id,
                              (i) => i.copyWith(spoiler: !i.spoiler),
                            ),
                          ),
                        _PillButton(
                          key: ValueKey('confirm-box-delete-${widget.item.id}'),
                          icon: Icons.delete_outline,
                          onTap: _delete,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.onTap, super.key});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: 24,
      height: 26,
      child: Icon(icon, size: 16, color: const Color(0xFFFFFFFF)),
    ),
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.box,
    required this.item,
    required this.thumbnail,
  });

  final ConfirmBoxController box;
  final AttachItem item;
  final ItemThumbnailBuilder? thumbnail;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final style = box.style;
    return SizedBox(
      key: ValueKey('confirm-box-row-${item.id}'),
      height: style.fileRowHeight,
      child: _ItemFrame(
        box: box,
        item: item,
        child: Row(
          children: [
            SizedBox.square(
              dimension: style.fileThumb,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _thumb(context, thumbnail, item),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.facts.name ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.onSurface, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
