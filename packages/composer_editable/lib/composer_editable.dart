/// The composer's editable: Flutter's `EditableText` and Material `TextField`
/// with Telegram composer selection parity.
///
/// A leaf package. The selection types that the copied sources would otherwise
/// declare under Flutter's own names (`TextSelectionControls`,
/// `SelectionOverlay`, ...) carry an `Extended` prefix, so importing this
/// library next to `package:flutter/material.dart` never hides or shadows a
/// Flutter name, and an `ExtendedTextSelectionControls` can not be handed to a
/// stock field by mistake.
library;

export 'src/cupertino/desktop_text_selection.dart'
    show
        ExtendedCupertinoDesktopTextSelectionControls,
        extendedCupertinoDesktopTextSelectionControls,
        extendedCupertinoDesktopTextSelectionHandleControls;
export 'src/cupertino/text_selection.dart'
    show
        ExtendedCupertinoTextSelectionControls,
        ExtendedCupertinoTextSelectionHandleControls,
        extendedCupertinoTextSelectionControls,
        extendedCupertinoTextSelectionHandleControls;
export 'src/material/desktop_text_selection.dart'
    show
        ExtendedDesktopTextSelectionControls,
        extendedDesktopTextSelectionControls,
        extendedDesktopTextSelectionHandleControls;
export 'src/material/text_field.dart' show ExtendedTextField;
export 'src/material/text_selection.dart'
    show
        ExtendedMaterialTextSelectionControls,
        ExtendedMaterialTextSelectionHandleControls,
        extendedMaterialTextSelectionControls,
        extendedMaterialTextSelectionHandleControls;
export 'src/widget/editable_text.dart'
    show
        ExtendedClipboardTextBuilder,
        ExtendedEditableText,
        ExtendedEditableTextContextMenuBuilder,
        ExtendedEditableTextState,
        ExtendedPasteTextTransformer;
export 'src/widget/padded_viewport_offset.dart' show PaddedViewportOffset;
export 'src/widget/render_editable.dart'
    show ExtendedRenderEditable, gutterClipRect;
export 'src/widget/secondary_click.dart'
    show ExtendedSecondaryClick, ExtendedSecondaryClickPhase;
export 'src/widget/system_context_menu.dart' show ExtendedSystemContextMenu;
export 'src/widget/text_selection.dart'
    show
        ExtendedClipboardStatusNotifier,
        ExtendedEmptyTextSelectionControls,
        ExtendedSelectionOverlay,
        ExtendedTextSelectionControls,
        ExtendedTextSelectionGestureDetector,
        ExtendedTextSelectionGestureDetectorBuilder,
        ExtendedTextSelectionGestureDetectorBuilderDelegate,
        ExtendedTextSelectionHandleControls,
        ExtendedTextSelectionOverlay,
        HandleDragChrome,
        HandleDragChromePhase,
        OvershootCurve,
        computeHandleDragChrome,
        debugLogExtendedTextSelectionHandles,
        extendedEmptyTextSelectionControls,
        isInterruptedCharacter,
        kAospMagnifierSettleMs,
        kHandleSettleDuration,
        kTelegramHandleMotionDuration,
        magnifierInfoSettled,
        pointerLineMagnifierTarget,
        settleTForElapsed,
        smoothMagnifierInfo,
        snapExtentForHandleDrag;
