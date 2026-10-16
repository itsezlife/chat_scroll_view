import 'package:flutter/widgets.dart';

/// Edits a controller the way the platform text input does: it hands over a
/// whole new [TextEditingValue].
extension SimulatedInput on TextEditingController {
  /// Replaces [start]..[end] with [inserted] and puts the caret after it, as a
  /// key press, a paste or a selection replacement does.
  void replace(int start, int end, String inserted) {
    final next = text.replaceRange(start, end, inserted);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
  }

  /// Types [typed] at the caret, or over a range selection.
  void type(String typed) {
    final selection = value.selection;
    if (!selection.isValid) {
      replace(text.length, text.length, typed);
      return;
    }
    replace(selection.start, selection.end, typed);
  }

  /// Deletes the range as a platform delete key does: the caret ends at
  /// [start].
  void deleteRange(int start, int end) => replace(start, end, '');

  /// Starts or continues an IME composition: the text is [next] and the
  /// composing range is [composing].
  void compose(String next, TextRange composing, {int? caret}) {
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret ?? composing.end),
      composing: composing,
    );
  }

  /// Ends the composition with [next] as the final text.
  void commitComposition(String next, {int? caret}) {
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret ?? next.length),
    );
  }
}
