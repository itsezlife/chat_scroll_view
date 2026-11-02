/// Every scenario's id and cold flag, in run order, as plain Dart.
///
/// The runner (`tool/chat_perf.dart`) is a `dart run` script: it cannot import
/// the scenarios, which reach `dart:ui`. It plans its launches from this index
/// instead; `scenario_index_test.dart` keeps it equal to the registry.
library;

typedef ScenarioIndexEntry = ({String id, bool cold});

/// The scenarios whose id matches [filter] (comma-separated globs, `*` any run
/// of characters, anchored; empty selects all), of the given [cold]ness.
List<ScenarioIndexEntry> selectScenarios(
  Iterable<ScenarioIndexEntry> index,
  String filter, {
  bool cold = false,
}) {
  final matches = scenarioGlobs(filter);
  return [
    for (final s in index)
      if (s.cold == cold && matches(s.id)) s,
  ];
}

/// A matcher for [filter]'s comma-separated globs; an empty filter matches all.
bool Function(String id) scenarioGlobs(String filter) {
  final patterns = [
    for (final part in filter.split(','))
      if (part.trim().isNotEmpty)
        RegExp('^${part.trim().split('*').map(RegExp.escape).join('.*')}\$'),
  ];
  return (id) => patterns.isEmpty || patterns.any((p) => p.hasMatch(id));
}

/// The ids that also run in the traced pass (`Scenario.traced`), in order.
/// `scenario_index_test.dart` keeps it equal to the registry.
const tracedScenarioIds = <String>[
  'scroll.drag_slow',
  'scroll.drag_fast',
  'scroll.fling_single',
  'scroll.fling_burst',
  'scroll.fling_reverse',
  'scroll.stop_on_touch',
  'scroll.overscroll_oldest',
  'scroll.scrollbar_drag',
  'nav.jump_near',
  'nav.jump_far',
  'nav.animate_near',
  'nav.animate_far',
  'nav.jump_to_newest',
  'nav.date_pill_during_fling',
  'churn.send_at_tail',
  'churn.send_away',
  'churn.incoming_burst_tail',
  'churn.incoming_while_away',
  'churn.edit_visible_tail',
  'churn.edit_visible_away',
  'churn.delete_visible',
  'churn.delete_anchor',
  'churn.delete_anchor_tall',
  'churn.unread_boundary',
];

const scenarioIndex = <ScenarioIndexEntry>[
  (id: 'scroll.drag_slow', cold: false),
  (id: 'scroll.drag_fast', cold: false),
  (id: 'scroll.fling_single', cold: false),
  (id: 'scroll.fling_burst', cold: false),
  (id: 'scroll.fling_reverse', cold: false),
  (id: 'scroll.stop_on_touch', cold: false),
  (id: 'scroll.overscroll_oldest', cold: false),
  (id: 'scroll.scrollbar_drag', cold: false),
  (id: 'scroll.first_scroll', cold: true),
  (id: 'scroll.first_scroll_warmed', cold: true),
  (id: 'nav.jump_near', cold: false),
  (id: 'nav.jump_far', cold: false),
  (id: 'nav.animate_near', cold: false),
  (id: 'nav.animate_far', cold: false),
  (id: 'nav.jump_to_newest', cold: false),
  (id: 'nav.date_pill_during_fling', cold: false),
  (id: 'scale.fling', cold: false),
  (id: 'scale.jump_far', cold: false),
  (id: 'scale.animate_far', cold: false),
  (id: 'scroll.real.drag_slow', cold: false),
  (id: 'scroll.real.fling_single', cold: false),
  (id: 'scroll.real.fling_burst', cold: false),
  (id: 'churn.send_at_tail', cold: false),
  (id: 'churn.send_away', cold: false),
  (id: 'churn.incoming_burst_tail', cold: false),
  (id: 'churn.incoming_while_away', cold: false),
  (id: 'churn.incoming_while_away_fling', cold: false),
  (id: 'churn.edit_visible_tail', cold: false),
  (id: 'churn.edit_visible_away', cold: false),
  (id: 'churn.delete_visible', cold: false),
  (id: 'churn.delete_anchor', cold: false),
  (id: 'churn.delete_anchor_tall', cold: false),
  (id: 'churn.chunk_load_up', cold: false),
  (id: 'churn.unread_boundary', cold: false),
  (id: 'churn.first_open', cold: true),
  (id: 'kbd.synthetic_open_tail', cold: false),
  (id: 'kbd.synthetic_close_tail', cold: false),
  (id: 'kbd.synthetic_open_mid_history', cold: false),
  (id: 'kbd.synthetic_open_mid_fling', cold: false),
  (id: 'kbd.synthetic_handoff', cold: false),
  (id: 'kbd.open_tail', cold: false),
  (id: 'kbd.close_tail', cold: false),
  (id: 'kbd.open_mid_history', cold: false),
  (id: 'kbd.open_mid_fling', cold: false),
  (id: 'kbd.open_during_animate', cold: false),
  (id: 'kbd.composer_growth', cold: false),
  (id: 'panel.open_over_chat', cold: false),
  (id: 'panel.keyboard_handoff', cold: false),
  (id: 'kbd.interactive_dismiss', cold: false),
  (id: 'sel.message_enter_exit', cold: false),
  (id: 'sel.text_drag_extend', cold: false),
  (id: 'sel.text_drag_autoscroll', cold: false),
  (id: 'sel.menu_open', cold: false),
  (id: 'sel.code_block_highlight', cold: false),
  (id: 'sel.link_tap_highlight', cold: false),
  (id: 'rich.markdown_fling', cold: false),
  (id: 'rich.code_fling', cold: false),
];
