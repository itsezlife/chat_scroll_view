import 'dart:async';

import 'package:meta/meta.dart';

/// One entry of a **pointer menu**: a row the user can choose or a separator.
sealed class PointerMenuEntry {
  const PointerMenuEntry();
}

/// A line between two groups of rows.
final class PointerMenuSeparator extends PointerMenuEntry {
  /// A separator.
  const PointerMenuSeparator();
}

/// A row: a label, an optional shortcut hint, and either an action or a
/// submenu.
///
/// A row that cannot be chosen is still shown, greyed, because the reference
/// menus keep their shape from one state to the next; it takes no hover, no
/// ripple, no click and is skipped by the arrow keys.
@immutable
final class PointerMenuItem extends PointerMenuEntry {
  /// A row identified by [id] showing [label].
  const PointerMenuItem({
    required this.id,
    required this.label,
    this.hint,
    this.enabled = true,
    this.onSelected,
    this.submenu,
  });

  /// What the row is, for a test and a semantics tree.
  final Object id;

  /// The visible label. An `&` before a letter marks it as the row's access
  /// mnemonic, drawn underlined, and `&&` is a literal ampersand
  /// ([PointerMenuLabel.parse]).
  final String label;

  /// The shortcut text drawn at the row's trailing edge, or null for none.
  final String? hint;

  /// Whether the row can be chosen at all, whatever it holds.
  final bool enabled;

  /// Runs when the row is chosen. The menu closes first, so the action sees
  /// the field it was opened over.
  final FutureOr<void> Function()? onSelected;

  /// The rows of the submenu this row opens, or null for a plain row.
  final List<PointerMenuEntry>? submenu;

  /// Whether the user can choose (or open) the row.
  bool get isEnabled => enabled && (onSelected != null || submenu != null);
}

/// A label split into its visible text and its mnemonic.
@immutable
final class PointerMenuLabel {
  const PointerMenuLabel._(this.text, this.mnemonic);

  /// Splits [raw] at its `&` marks, as the reference toolkit's menu item
  /// parser does: the first `&` before a character marks it, `&&` is one
  /// literal `&`, and any other `&` is dropped.
  factory PointerMenuLabel.parse(String raw) {
    final text = StringBuffer();
    int? mnemonic;
    var length = 0;
    for (var i = 0; i < raw.length; i++) {
      final unit = raw[i];
      if (unit != '&') {
        text.write(unit);
        length++;
        continue;
      }
      if (i + 1 < raw.length && raw[i + 1] == '&') {
        text.write('&');
        length++;
        i++;
      } else if (mnemonic == null && i + 1 < raw.length) {
        mnemonic = length;
      }
    }
    return PointerMenuLabel._(text.toString(), mnemonic);
  }

  /// The label as drawn and spoken, marks removed.
  final String text;

  /// The index in [text] of the access letter, or null for none.
  final int? mnemonic;
}

/// Which row the arrow keys land on.
abstract final class PointerMenuNavigation {
  /// The row after [from] (the one before it when [forward] is false) that can
  /// be chosen, wrapping at the ends; separators and rows that cannot be
  /// chosen are skipped.
  ///
  /// From nothing selected, forward lands on the first row that can be chosen
  /// and backward on the last. Null when no row can be chosen.
  static int? step(
    List<PointerMenuEntry> entries,
    int? from, {
    required bool forward,
  }) {
    final count = entries.length;
    if (count == 0) return null;
    final delta = forward ? 1 : -1;
    var index = from ?? (forward ? -1 : count);
    for (var visited = 0; visited < count; visited++) {
      index = (index + delta) % count;
      if (index < 0) index += count;
      if (isChoosable(entries[index])) return index;
    }
    return null;
  }

  /// The first row that can be chosen, or null.
  static int? firstEnabled(List<PointerMenuEntry> entries) =>
      step(entries, null, forward: true);

  /// Whether [entry] is a row that can be chosen.
  static bool isChoosable(PointerMenuEntry entry) =>
      entry is PointerMenuItem && entry.isEnabled;
}
