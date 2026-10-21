import 'package:content_model/src/rich_text/detection/detection_policy.dart';
import 'package:content_model/src/rich_text/detection/link_scanner.dart';
import 'package:content_model/src/rich_text/detection/tag_scanner.dart';
import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:content_model/src/rich_text/rich_text.dart';

/// Turns bare URLs, emails, `@name` and `#tag` in a [RichText] into entities,
/// with the reference client's rules, under a host's [DetectionPolicy].
///
/// One pure function for every caller: the composer's send path runs it on the
/// text before encoding, the receive path runs it once on a body that carries
/// no link-class entity, a link-preview listener runs it with
/// [DetectionPolicy.urlsOnly], and a server port can run the same code. It is
/// **host-invoked**, synchronous, linear in the text and meant for the moment
/// a message is made or loaded, never for a paint or a keystroke: the viewport
/// does not detect.
///
/// ## What becomes what
///
/// | Text | Entity |
/// | --- | --- |
/// | `https://a.b/c`, `a.com`, `www.a.com/x` | [EntityKind.link] to the URL, with the URL as its text; a URL typed without a scheme is linked to [DetectionPolicy.implicitScheme] |
/// | `user@a.com` | [EntityKind.link] to `mailto:user@a.com` |
/// | `@name` | [EntityKind.username] |
/// | `#tag` | [EntityKind.hashtag] |
///
/// Never made: `bot_command`, `cashtag`, `phone` and `bank_card`, which have no
/// [EntityKind]. A host that wants phone links writes `link("tel:...")` under
/// its own policy. A resolved user is [EntityKind.mention], which a picker
/// makes; detection never does.
///
/// ## What it leaves alone
///
/// A match that overlaps code, a code block, an existing link, mention,
/// username, hashtag or inline content is not made: nothing is detected inside
/// them, and a URL that runs into an atom is not detected at all. Other
/// styles, a spoiler among them, do not block, and the new entity sits beside
/// them.
///
/// ## Budget
///
/// At most [maxMatches] entities are made per text, and a text over
/// [maxLength] characters is returned as it came (the reference client's caps). The entities earlier detection already left count
/// against the [maxMatches]: that is what makes [apply] idempotent when a text
/// has more matches than the cap.
///
/// ## Edit
///
/// [strip] is the inverse for loading a message into an editor: it takes back
/// what [apply] made, so saving can detect again over what the user left.
abstract final class EntityDetection {
  /// The most entities one text gets (the reference client's cap).
  static const int maxMatches = 100;

  /// The longest text detection looks at, in UTF-16 code units; a longer one
  /// is returned unchanged (the reference client skips texts of 20 480
  /// characters or more).
  static const int maxLength = 20480;

  /// [text] with the URLs, emails, usernames and hashtags [policy] asks for
  /// made into entities.
  ///
  /// Returns [text] itself when there is nothing to add. Running it again
  /// changes nothing: `apply(apply(x)) == apply(x)`.
  static RichText apply(
    RichText text, [
    DetectionPolicy policy = const DetectionPolicy(),
  ]) {
    if (!policy.detectsAnything || text.isEmpty || text.length > maxLength) {
      return text;
    }
    final candidates = _candidates(text.plain, policy);
    if (candidates.isEmpty) return text;
    final free = _clearOf(_blockedSpans(text), candidates);
    final kept = _longestWins(free);
    final budget = maxMatches - _detectedCount(text, policy);
    if (kept.isEmpty || budget <= 0) return text;
    return RichText(text.plain, [
      ...text.entities,
      ...kept.length > budget ? kept.sublist(0, budget) : kept,
    ]);
  }

  /// [text] without the entities [apply] under [policy] would add back.
  ///
  /// That is a link whose text is its own URL, or a bare host that [apply]
  /// links to `https://host`, or an email linked to `mailto:` and itself; a
  /// username `@name`; a hashtag `#tag`. A link the user made, whose text says
  /// something else, stays, and so does a link whose target differs from what
  /// its text would be linked to. So for a body made by [apply],
  /// `strip(apply(x)) == x`.
  ///
  /// Pass the policy that detected: one that detects less strips less.
  static RichText strip(
    RichText text, [
    DetectionPolicy policy = const DetectionPolicy(),
  ]) {
    final kept = [
      for (final entity in text.entities)
        if (!_isDetected(text, entity, policy)) entity,
    ];
    return kept.length == text.entities.length
        ? text
        : RichText(text.plain, kept);
  }

  // --- Candidates ---

  static List<Entity> _candidates(String plain, DetectionPolicy policy) {
    final all = [
      if (policy.urls) ...LinkScanner.scan(plain, policy),
      if (policy.usernames || policy.hashtags)
        ...TagScanner.scan(
          plain,
          usernames: policy.usernames,
          hashtags: policy.hashtags,
        ),
    ]..sort(_byStartThenLongest);
    return all;
  }

  static int _byStartThenLongest(Entity a, Entity b) =>
      a.offset != b.offset ? a.offset - b.offset : b.length - a.length;

  /// The spans no detected entity may touch, merged and in order.
  static List<({int start, int end})> _blockedSpans(RichText text) {
    final spans = <({int start, int end})>[];
    for (final entity in text.entities) {
      if (!_blocks(entity.kind)) continue;
      if (spans.isNotEmpty && entity.offset <= spans.last.end) {
        if (entity.end > spans.last.end) {
          spans[spans.length - 1] = (start: spans.last.start, end: entity.end);
        }
      } else {
        spans.add((start: entity.offset, end: entity.end));
      }
    }
    return spans;
  }

  static bool _blocks(EntityKind kind) => switch (kind) {
    EntityKind$Style(:final style) => style == EntityStyle.code,
    EntityKind$CodeBlock() ||
    EntityKind$Link() ||
    EntityKind$Mention() ||
    EntityKind$Username() ||
    EntityKind$Hashtag() ||
    EntityKind$InlineContent() => true,
    EntityKind$List() => false,
  };

  /// The [candidates] (sorted by start) that touch none of the [blocked]
  /// spans (merged, in order).
  static List<Entity> _clearOf(
    List<({int start, int end})> blocked,
    List<Entity> candidates,
  ) {
    final clear = <Entity>[];
    var next = 0;
    for (final candidate in candidates) {
      while (next < blocked.length && blocked[next].end <= candidate.offset) {
        next++;
      }
      if (next < blocked.length && blocked[next].start < candidate.end) {
        continue;
      }
      clear.add(candidate);
    }
    return clear;
  }

  /// Of overlapping candidates (sorted by start, longer first) the longest
  /// stays (as the reference client prunes).
  static List<Entity> _longestWins(List<Entity> candidates) {
    final kept = <Entity>[];
    for (final candidate in candidates) {
      if (kept.isEmpty || candidate.offset >= kept.last.end) {
        kept.add(candidate);
      } else if (candidate.length > kept.last.length) {
        kept[kept.length - 1] = candidate;
      }
    }
    return kept;
  }

  // --- What an earlier detection left ---

  static int _detectedCount(RichText text, DetectionPolicy policy) {
    var count = 0;
    for (final entity in text.entities) {
      if (_isDetected(text, entity, policy)) count++;
    }
    return count;
  }

  /// Whether [entity] is what detection under [policy] makes of its own text:
  /// scanning that text alone finds exactly it, over all of it.
  static bool _isDetected(
    RichText text,
    Entity entity,
    DetectionPolicy policy,
  ) {
    switch (entity.kind) {
      case EntityKind$Link() || EntityKind$Username() || EntityKind$Hashtag():
        final label = text.textOf(entity);
        final found = _longestWins(_candidates(label, policy));
        return found.length == 1 &&
            found.single.offset == 0 &&
            found.single.length == label.length &&
            found.single.kind == entity.kind;
      case EntityKind$Style() ||
          EntityKind$Mention() ||
          EntityKind$InlineContent() ||
          EntityKind$CodeBlock() ||
          EntityKind$List():
        return false;
    }
  }
}
