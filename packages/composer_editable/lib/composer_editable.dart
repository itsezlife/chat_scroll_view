/// Extended TextField / EditableText fork for app-wide use.
library;

export 'src/material/text_field.dart';
export 'src/material/text_selection.dart'
    show
        MaterialTextSelectionControls,
        MaterialTextSelectionHandleControls,
        materialTextSelectionControls,
        materialTextSelectionHandleControls;
export 'src/widget/editable_text.dart'
    show
        ExtendedEditableText,
        ExtendedEditableTextState,
        ExtendedEditableTextContextMenuBuilder,
        ExtendedClipboardTextBuilder,
        ExtendedPasteTextTransformer,
        SelectionChangedCallback,
        AppPrivateCommandCallback;
export 'src/widget/padded_viewport_offset.dart' show PaddedViewportOffset;
export 'src/widget/render_editable.dart'
    show ExtendedRenderEditable, gutterClipRect;
export 'src/widget/text_selection.dart'
    show
        debugLogExtendedTextSelectionHandles,
        OvershootCurve,
        kTelegramHandleMotionDuration,
        kHandleSettleDuration,
        kAospMagnifierSettleMs,
        settleTForElapsed,
        HandleDragChromePhase,
        HandleDragChrome,
        pointerLineMagnifierTarget,
        computeHandleDragChrome,
        smoothMagnifierInfo,
        magnifierInfoSettled,
        isInterruptedCharacter,
        snapExtentForHandleDrag;
