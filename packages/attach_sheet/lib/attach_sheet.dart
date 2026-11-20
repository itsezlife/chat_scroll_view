/// The attach sheet: the mobile container a user picks media and files to
/// send from.
///
/// `AttachSheet.show` opens one over an `AttachSelection` from
/// `attach_model`, laid out and moved by an `AttachSheetPolicy`; the host
/// hears of it through an `AttachSheetHost`. Colours come from
/// `AttachTokens` and labels from `AttachStrings` in `chrome_foundation`.
library;

export 'src/box/attach_drop_overlay.dart';
export 'src/box/confirm_box.dart';
export 'src/box/confirm_box_controller.dart';
export 'src/debug/attach_log.dart';
export 'src/files/files_page.dart';
export 'src/files/intake_items.dart';
export 'src/gallery/attach_picker_selection.dart';
export 'src/gallery/gallery_page.dart';
export 'src/host/attach_caption_dock.dart';
export 'src/host/attach_discard_question.dart';
export 'src/host/attach_sheet_host.dart';
export 'src/page/attach_page.dart';
export 'src/page/attach_page_scope.dart' show AttachPageScope;
export 'src/panel/attach_interaction.dart';
export 'src/panel/attach_panel.dart';
export 'src/panel/attach_send_controller.dart';
export 'src/policy/attach_panel_style.dart';
export 'src/policy/attach_sheet_policy.dart';
export 'src/policy/attach_tab_bar_style.dart';
export 'src/policy/confirm_box_style.dart';
export 'src/prepare/attach_preparation.dart';
export 'src/sheet/attach_outcome.dart';
export 'src/sheet/attach_sheet.dart';
