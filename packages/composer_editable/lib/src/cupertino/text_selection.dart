// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: implementation_imports

import 'dart:math' as math;

import 'package:composer_editable/src/widget/text_selection.dart';
import 'package:flutter/foundation.dart' show ValueListenable, clampDouble;
import 'package:flutter/src/cupertino/localizations.dart';
import 'package:flutter/src/cupertino/text_selection_toolbar.dart';
import 'package:flutter/src/cupertino/text_selection_toolbar_button.dart';
import 'package:flutter/src/cupertino/theme.dart';
import 'package:flutter/widgets.dart';

// Read off from the output on iOS 12. This color does not vary with the
// application's theme color.
const double _kSelectionHandleOverlap = 1.5;
// Extracted from https://developer.apple.com/design/resources/.
const double _kSelectionHandleRadius = 6;

// Minimal padding from tip of the selection toolbar arrow to horizontal edges of the
// screen. Eyeballed value.
const double _kArrowScreenPadding = 26;

/// Draws a single text selection handle with a bar and a ball.
class _CupertinoTextSelectionHandlePainter extends CustomPainter {
  const _CupertinoTextSelectionHandlePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const halfStrokeWidth = 1.0;
    final paint = Paint()..color = color;
    final circle = Rect.fromCircle(
      center: const Offset(_kSelectionHandleRadius, _kSelectionHandleRadius),
      radius: _kSelectionHandleRadius,
    );
    final line = Rect.fromPoints(
      const Offset(
        _kSelectionHandleRadius - halfStrokeWidth,
        2 * _kSelectionHandleRadius - _kSelectionHandleOverlap,
      ),
      Offset(_kSelectionHandleRadius + halfStrokeWidth, size.height),
    );
    final path = Path()
      ..addOval(circle)
      // Draw line so it slightly overlaps the circle.
      ..addRect(line);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CupertinoTextSelectionHandlePainter oldPainter) =>
      color != oldPainter.color;
}

/// iOS Cupertino styled text selection handle controls.
///
/// Specifically does not manage the toolbar, which is left to
/// [ExtendedEditableText.contextMenuBuilder].
@Deprecated(
  'Use `ExtendedCupertinoTextSelectionControls`. '
  'This feature was deprecated after v3.3.0-0.5.pre.',
)
class ExtendedCupertinoTextSelectionHandleControls
    extends ExtendedCupertinoTextSelectionControls
    with ExtendedTextSelectionHandleControls {}

/// iOS Cupertino styled text selection controls.
///
/// The [extendedCupertinoTextSelectionControls] global variable has a
/// suitable instance of this class.
class ExtendedCupertinoTextSelectionControls
    extends ExtendedTextSelectionControls {
  /// Returns the size of the Cupertino handle.
  @override
  Size getHandleSize(double textLineHeight) => Size(
    _kSelectionHandleRadius * 2,
    textLineHeight + _kSelectionHandleRadius * 2 - _kSelectionHandleOverlap,
  );

  /// Builder for iOS-style copy/paste text selection toolbar.
  @Deprecated(
    'Use `contextMenuBuilder` instead. '
    'This feature was deprecated after v3.3.0-0.5.pre.',
  )
  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) => _CupertinoTextSelectionControlsToolbar(
    clipboardStatus: clipboardStatus,
    endpoints: endpoints,
    globalEditableRegion: globalEditableRegion,
    handleCut: canCut(delegate) ? () => handleCut(delegate) : null,
    handleCopy: canCopy(delegate) ? () => handleCopy(delegate) : null,
    handlePaste: canPaste(delegate) ? () => handlePaste(delegate) : null,
    handleSelectAll: canSelectAll(delegate)
        ? () => handleSelectAll(delegate)
        : null,
    selectionMidpoint: selectionMidpoint,
    textLineHeight: textLineHeight,
  );

  /// Builder for iOS text selection edges.
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    // iOS selection handles do not respond to taps.
    final Size desiredSize;
    final Widget handle;

    final Widget customPaint = CustomPaint(
      painter: _CupertinoTextSelectionHandlePainter(
        CupertinoTheme.of(context).selectionHandleColor,
      ),
    );

    // [buildHandle]'s widget is positioned at the selection cursor's bottom
    // baseline. We transform the handle such that the SizedBox is superimposed
    // on top of the text selection endpoints.
    switch (type) {
      case TextSelectionHandleType.left:
        desiredSize = getHandleSize(textLineHeight);
        handle = SizedBox.fromSize(size: desiredSize, child: customPaint);
        return handle;
      case TextSelectionHandleType.right:
        desiredSize = getHandleSize(textLineHeight);
        handle = SizedBox.fromSize(size: desiredSize, child: customPaint);
        return Transform(
          transform: Matrix4.identity()
            ..translateByDouble(
              desiredSize.width / 2,
              desiredSize.height / 2,
              0,
              1,
            )
            ..rotateZ(math.pi)
            ..translateByDouble(
              -desiredSize.width / 2,
              -desiredSize.height / 2,
              0,
              1,
            ),
          child: handle,
        );
      // iOS should draw an invisible box so the handle can still receive gestures
      // on collapsed selections.
      case TextSelectionHandleType.collapsed:
        return SizedBox.fromSize(size: getHandleSize(textLineHeight));
    }
  }

  /// Gets anchor for cupertino-style text selection handles.
  ///
  /// See [ExtendedTextSelectionControls.getHandleAnchor].
  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final handleSize = getHandleSize(textLineHeight);

    switch (type) {
      // The circle is at the top for the left handle, and the anchor point is
      // all the way at the bottom of the line.
      case TextSelectionHandleType.left:
        return Offset(handleSize.width / 2, handleSize.height);
      // The right handle is vertically flipped, and the anchor point is near
      // the top of the circle to give slight overlap.
      case TextSelectionHandleType.right:
        return Offset(
          handleSize.width / 2,
          handleSize.height -
              2 * _kSelectionHandleRadius +
              _kSelectionHandleOverlap,
        );
      // A collapsed handle anchors itself so that it's centered.
      case TextSelectionHandleType.collapsed:
        return Offset(
          handleSize.width / 2,
          textLineHeight + (handleSize.height - textLineHeight) / 2,
        );
    }
  }
}

// TODO(justinmc): Deprecate this after ExtendedTextSelectionControls.buildToolbar is
// deleted, when users should migrate back to extendedCupertinoTextSelectionControls.
// See https://github.com/flutter/flutter/pull/124262
/// Text selection handle controls that follow iOS design conventions.
final ExtendedTextSelectionControls
extendedCupertinoTextSelectionHandleControls =
    ExtendedCupertinoTextSelectionHandleControls();

/// Text selection controls that follow iOS design conventions.
final ExtendedTextSelectionControls extendedCupertinoTextSelectionControls =
    ExtendedCupertinoTextSelectionControls();

// Generates the child that's passed into CupertinoTextSelectionToolbar.
class _CupertinoTextSelectionControlsToolbar extends StatefulWidget {
  const _CupertinoTextSelectionControlsToolbar({
    required this.clipboardStatus,
    required this.endpoints,
    required this.globalEditableRegion,
    required this.handleCopy,
    required this.handleCut,
    required this.handlePaste,
    required this.handleSelectAll,
    required this.selectionMidpoint,
    required this.textLineHeight,
  });

  final ValueListenable<ClipboardStatus>? clipboardStatus;
  final List<TextSelectionPoint> endpoints;
  final Rect globalEditableRegion;
  final VoidCallback? handleCopy;
  final VoidCallback? handleCut;
  final VoidCallback? handlePaste;
  final VoidCallback? handleSelectAll;
  final Offset selectionMidpoint;
  final double textLineHeight;

  @override
  _CupertinoTextSelectionControlsToolbarState createState() =>
      _CupertinoTextSelectionControlsToolbarState();
}

class _CupertinoTextSelectionControlsToolbarState
    extends State<_CupertinoTextSelectionControlsToolbar> {
  void _onChangedClipboardStatus() {
    setState(() {
      // Inform the widget that the value of clipboardStatus has changed.
    });
  }

  @override
  void initState() {
    super.initState();
    widget.clipboardStatus?.addListener(_onChangedClipboardStatus);
  }

  @override
  void didUpdateWidget(_CupertinoTextSelectionControlsToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clipboardStatus != widget.clipboardStatus) {
      oldWidget.clipboardStatus?.removeListener(_onChangedClipboardStatus);
      widget.clipboardStatus?.addListener(_onChangedClipboardStatus);
    }
  }

  @override
  void dispose() {
    widget.clipboardStatus?.removeListener(_onChangedClipboardStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't render the menu until the state of the clipboard is known.
    if (widget.handlePaste != null &&
        widget.clipboardStatus?.value == ClipboardStatus.unknown) {
      return const SizedBox.shrink();
    }

    assert(
      debugCheckHasMediaQuery(context),
      'A MediaQuery ancestor is required.',
    );
    final mediaQueryPadding = MediaQuery.paddingOf(context);

    // The toolbar should appear below the TextField when there is not enough
    // space above the TextField to show it, assuming there's always enough
    // space at the bottom in this case.
    final anchorX = clampDouble(
      widget.selectionMidpoint.dx + widget.globalEditableRegion.left,
      _kArrowScreenPadding + mediaQueryPadding.left,
      MediaQuery.widthOf(context) -
          mediaQueryPadding.right -
          _kArrowScreenPadding,
    );

    final topAmountInEditableRegion =
        widget.endpoints.first.point.dy - widget.textLineHeight;
    final anchorTop =
        math.max(topAmountInEditableRegion, 0) +
        widget.globalEditableRegion.top;

    // The y-coordinate has to be calculated instead of directly quoting
    // selectionMidpoint.dy, since the caller
    // (ExtendedTextSelectionOverlay._buildToolbar) does not know whether the toolbar is
    // going to be facing up or down.
    final anchorAbove = Offset(anchorX, anchorTop);
    final anchorBelow = Offset(
      anchorX,
      widget.endpoints.last.point.dy + widget.globalEditableRegion.top,
    );

    final items = <Widget>[];
    final localizations = CupertinoLocalizations.of(context);
    final Widget onePhysicalPixelVerticalDivider = SizedBox(
      width: 1.0 / MediaQuery.devicePixelRatioOf(context),
    );

    void addToolbarButton(String text, VoidCallback onPressed) {
      if (items.isNotEmpty) {
        items.add(onePhysicalPixelVerticalDivider);
      }

      items.add(
        CupertinoTextSelectionToolbarButton.text(
          onPressed: onPressed,
          text: text,
        ),
      );
    }

    if (widget.handleCut != null) {
      addToolbarButton(localizations.cutButtonLabel, widget.handleCut!);
    }
    if (widget.handleCopy != null) {
      addToolbarButton(localizations.copyButtonLabel, widget.handleCopy!);
    }
    if (widget.handlePaste != null &&
        widget.clipboardStatus?.value == ClipboardStatus.pasteable) {
      addToolbarButton(localizations.pasteButtonLabel, widget.handlePaste!);
    }
    if (widget.handleSelectAll != null) {
      addToolbarButton(
        localizations.selectAllButtonLabel,
        widget.handleSelectAll!,
      );
    }

    // If there is no option available, build an empty widget.
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return CupertinoTextSelectionToolbar(
      anchorAbove: anchorAbove,
      anchorBelow: anchorBelow,
      children: items,
    );
  }
}
