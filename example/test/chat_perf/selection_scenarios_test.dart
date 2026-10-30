import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/corpus.dart';
import '../../integration_test/chat_perf/corpus_rich.dart';
import '../../integration_test/chat_perf/scenarios/selection_scenarios.dart';

void main() {
  test('the selection family registers its eight scenarios on the rich '
      'profile', () {
    expect(selectionScenarios.all.map((s) => s.id), [
      'sel.message_enter_exit',
      'sel.text_drag_extend',
      'sel.text_drag_autoscroll',
      'sel.menu_open',
      'sel.code_block_highlight',
      'sel.link_tap_highlight',
      'rich.markdown_fling',
      'rich.code_fling',
    ]);
    for (final s in selectionScenarios.all) {
      expect(s.profile, BenchProfile.rich, reason: s.id);
      expect(s.cold, isFalse);
    }
  });

  test('the fling scenarios measure the plain control first', () {
    final s = selectionScenarios.all.singleWhere(
      (s) => s.id == 'rich.code_fling',
    );
    expect(s.windows, ['plain_fling', 'fling']);
  });

  test('the rich profile designates fixed targets and regions', () {
    const rich = BenchCorpus(count: 5000, profile: BenchProfile.rich);
    for (final t in BenchTarget.values) {
      final m = rich.messageAt(t.id);
      expect(m.markdown, isTrue, reason: '$t');
      expect(m.text, richTextOf(t.id));
    }
    expect(rich.messageAt(BenchTarget.linkLine.id).text, contains('](http'));
    // The mobile copy bar needs at least 75 characters of code.
    final code = rich.messageAt(BenchTarget.fencedCode.id).text;
    expect(code, startsWith('```'));
    expect(code.length, greaterThanOrEqualTo(75));
    expect(rich.messageAt(kMarkdownRegion.$1).markdown, isTrue);
    expect(rich.messageAt(kCodeRegion.$2 - 1).text, contains('```'));
    expect(rich.messageAt(kPlainRegion.$1).markdown, isFalse);
  });

  test('the plain profile is untouched by the rich designations', () {
    const plain = BenchCorpus(count: 5000);
    const rich = BenchCorpus(count: 5000, profile: BenchProfile.rich);
    expect(plain.messageAt(1000).markdown, isFalse);
    expect(plain.messageAt(50).text, rich.messageAt(50).text);
    expect(plain.messageAt(4100).text, rich.messageAt(4100).text);
  });
}
