/// Host-independent panel shell: an open registry of panel pages, the shell
/// controller that owns page and search state, the widgets that project it
/// (pager, type tabs, bottom bar, search field), one sealed panel event, page
/// scroll activity, the shared search helper, and focus and shortcuts.
///
/// Depends on `chrome_foundation` and `content_model` only. Concrete pages
/// live elsewhere and register as `PanelPage`s; the shell imports none.
library;

export 'src/controller/panel_search_state.dart';
export 'src/controller/panel_shell_controller.dart';
export 'src/event/panel_event.dart';
export 'src/input/panel_announcer.dart';
export 'src/input/panel_focus_policy.dart';
export 'src/input/panel_intents.dart';
export 'src/page/page_controller_registry.dart';
export 'src/page/panel_page.dart';
export 'src/page/panel_page_host.dart';
export 'src/scroll/bottom_bar_visibility.dart';
export 'src/scroll/page_scroll_activity.dart';
export 'src/search/debounced_search.dart';
export 'src/widgets/panel_arrangement.dart';
export 'src/widgets/panel_background_scope.dart';
export 'src/widgets/panel_search_field.dart';
export 'src/widgets/panel_search_state_icon.dart';
export 'src/widgets/panel_section_tabs.dart' show PanelSectionTabsBar;
export 'src/widgets/panel_shell.dart';
export 'src/widgets/panel_type_tabs.dart' show PanelTabDisplay;
