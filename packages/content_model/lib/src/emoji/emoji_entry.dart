import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/value_equality.dart';
import 'package:meta/meta.dart';

/// One of the five skin tones an emoji modifier can apply.
///
/// A name, not a position: nothing stores or computes with an index, so the
/// tone of an emoji is never an integer that can drift out of step with the
/// data.
enum SkinTone {
  /// The lightest tone.
  light,

  /// A medium-light tone.
  mediumLight,

  /// The medium tone.
  medium,

  /// A medium-dark tone.
  mediumDark,

  /// The darkest tone.
  dark,
}

/// The gender a person emoji is spelled with, through a ZWJ suffix or a
/// gendered person code point.
///
/// The absence of a gender (an empty [EmojiModifiers.genders]) is the
/// person-neutral form.
enum EmojiGender {
  /// The woman form.
  woman,

  /// The man form.
  man,
}

/// The set of modifiers that turns an [EmojiEntry]'s base into one variant.
///
/// A variant is described by its whole combination: the [tones] and [genders]
/// of the people it shows, one entry per person. Equal combinations are equal values, so a
/// combination is the lookup key into an entry ([EmojiEntry.keyFor]).
@immutable
final class EmojiModifiers {
  /// Creates a combination of [tones] and [genders].
  ///
  /// Both lists are copied into unmodifiable lists.
  EmojiModifiers({
    List<SkinTone> tones = const <SkinTone>[],
    List<EmojiGender> genders = const <EmojiGender>[],
  }) : tones = List<SkinTone>.unmodifiable(tones),
       genders = List<EmojiGender>.unmodifiable(genders);

  /// The empty combination: the base form of an entry.
  static final EmojiModifiers none = EmojiModifiers();

  /// The tones in the order their people appear in the sequence.
  ///
  /// Empty when the variant has no tone; one tone when it has one modifier
  /// (a single person, or a pair that shares it); several when each person has
  /// their own. The order is significant: a pair with a light then a dark
  /// person is a different variant from a dark then a light one. Unmodifiable.
  final List<SkinTone> tones;

  /// The genders in the order their people appear in the sequence: empty for
  /// the person-neutral form, one for a single gendered person, several for a
  /// group (a couple of a woman and a man differs from a man and a woman).
  /// Unmodifiable.
  final List<EmojiGender> genders;

  @override
  bool operator ==(Object other) =>
      other is EmojiModifiers &&
      ValueEquality.lists(other.genders, genders) &&
      ValueEquality.lists(other.tones, tones);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(genders), Object.hashAll(tones));

  @override
  String toString() =>
      'EmojiModifiers(${[...tones.map((t) => t.name), ...genders.map((g) => g.name)].join(', ')})';
}

/// One variant of an [EmojiEntry]: the unicode key it is sent as and the
/// modifiers that produce it.
@immutable
final class EmojiVariant {
  /// Creates the variant sent as [key] and tagged with [modifiers].
  const EmojiVariant(this.key, this.modifiers);

  /// The variant's own key: the exact sequence shown or sent for it.
  final ContentKey$Unicode key;

  /// The combination of modifiers this variant stands for.
  final EmojiModifiers modifiers;

  @override
  bool operator ==(Object other) =>
      other is EmojiVariant && other.key == key && other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(key, modifiers);

  @override
  String toString() => 'EmojiVariant($key, $modifiers)';
}

/// An emoji and every variant of it: skin tones, genders and their
/// combinations.
///
/// The base and each variant are unicode keys of their own; an entry only
/// links them. A variant is never computed by appending a modifier to the
/// base, because spellings differ (a tone replaces the FE0F selector, and a
/// gender suffix follows the tone), so the data states each sequence and this
/// entry preserves it. The tone a user prefers is stored as the chosen
/// variant's key, never as an index.
///
/// Whether an emoji takes a tone is [hasToneVariants]: derived from the
/// variants this entry holds, with no separate flag that could disagree with
/// them.
///
/// Keys are matched exactly. The FE0F form of a base and its unqualified
/// spelling are different keys, and [modifiersOf] knows only the spelling the
/// entry was built with; bridging spellings is the job of whoever builds
/// entries from data.
@immutable
final class EmojiEntry {
  /// Creates the entry for [base] with [variants], in display order.
  ///
  /// [variants] is copied into an unmodifiable list. No two variants may share
  /// a key or a combination of modifiers, none may share the base's key, and
  /// none may carry [EmojiModifiers.none] (that combination is the base).
  ///
  /// Throws an [ArgumentError] otherwise, in release builds too: variants come
  /// from external data, and a duplicate would make [keyFor] and [modifiersOf]
  /// answer by position instead of by identity.
  EmojiEntry({
    required this.base,
    List<EmojiVariant> variants = const <EmojiVariant>[],
  }) : variants = _checked(base, variants);

  /// The key of the base form: the entry without modifiers.
  final ContentKey$Unicode base;

  /// The variants in display order, not including the base. Unmodifiable.
  final List<EmojiVariant> variants;

  /// Whether any variant carries a skin tone.
  bool get hasToneVariants =>
      variants.any((variant) => variant.modifiers.tones.isNotEmpty);

  /// The key this entry sends for [modifiers]: [base] for
  /// [EmojiModifiers.none], the matching variant's key otherwise, or null when
  /// the entry has no such variant.
  ContentKey$Unicode? keyFor(EmojiModifiers modifiers) {
    if (modifiers == EmojiModifiers.none) return base;
    for (final variant in variants) {
      if (variant.modifiers == modifiers) return variant.key;
    }
    return null;
  }

  /// The modifiers of [key] within this entry: [EmojiModifiers.none] for the
  /// base, a variant's combination for a variant, or null when [key] belongs
  /// to neither.
  EmojiModifiers? modifiersOf(ContentKey key) {
    if (key == base) return EmojiModifiers.none;
    for (final variant in variants) {
      if (variant.key == key) return variant.modifiers;
    }
    return null;
  }

  static List<EmojiVariant> _checked(
    ContentKey$Unicode base,
    List<EmojiVariant> variants,
  ) {
    if (_conflict(base, variants) case final conflict?) {
      throw ArgumentError.value(variants, 'variants', conflict);
    }
    return List<EmojiVariant>.unmodifiable(variants);
  }

  // The first inconsistency of the data, or null.
  static String? _conflict(
    ContentKey$Unicode base,
    List<EmojiVariant> variants,
  ) {
    final keys = <ContentKey$Unicode>{base};
    final combinations = <EmojiModifiers>{EmojiModifiers.none};
    for (final variant in variants) {
      if (!keys.add(variant.key)) {
        return '${variant.key} is already the base or another variant.';
      }
      if (!combinations.add(variant.modifiers)) {
        return '${variant.key} repeats the modifiers ${variant.modifiers}, '
            'which are the base or another variant.';
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is EmojiEntry &&
      other.base == base &&
      ValueEquality.lists(other.variants, variants);

  @override
  int get hashCode => Object.hash(base, Object.hashAll(variants));

  @override
  String toString() => 'EmojiEntry($base, ${variants.length} variants)';
}
