import 'package:content_model/src/emoji/emoji_entry.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:listen/listen.dart';

/// Typed user choices that outlive a session.
///
/// A closed set of named preferences, not a bag of strings: each has a
/// meaning and a type, and the set grows by addition. Choices that belong to
/// one widget's chrome (sizes, heights) are not here.
///
/// Like a [RecentsStore], a store is created already loaded: getters are
/// synchronous, a setter is reflected by the getter and by [changes] before
/// its future completes, and the future completes when the choice is
/// persisted, failing if persisting did.
///
/// Setting a preference to the value it already has changes nothing and
/// signals nothing. After [dispose] [changes] is silent, getters keep
/// answering with the last state and setters do nothing.
abstract interface class PreferenceStore {
  /// Signals once per setter call that changed a preference.
  Listenable get changes;

  /// The variant of the emoji [base] the user chose, or null when they chose
  /// none. The answer is the exact variant key, never an index: a variant is
  /// its own unicode key.
  ///
  /// A user who chose the emoji as it is (the base) is remembered like any
  /// other choice, as [base] itself: a non-null answer means the user has
  /// chosen a variant of [base] at some point, and null that they never did.
  ///
  /// The store keeps what it was given. Whether that key still belongs to
  /// [base] in the current catalogue is for the caller to check.
  ContentKey$Unicode? preferredVariant(ContentKey$Unicode base);

  /// Remembers [variant] as the user's choice for [base], or forgets the
  /// choice when it is null.
  Future<void> setPreferredVariant(
    ContentKey$Unicode base,
    ContentKey$Unicode? variant,
  );

  /// The variant every emoji is shown in when the user chose none for it, as
  /// the modifiers to apply (its tones), or null when no default was chosen.
  /// [EmojiModifiers.none] is a default too: the emoji as it is.
  ///
  /// What it means for an emoji whose variants do not have those modifiers
  /// is the caller's to decide; the store keeps what it was given.
  EmojiModifiers? get defaultVariant;

  /// Remembers [modifiers] as the default variant and forgets every choice
  /// made per emoji ([preferredVariant]), as a "this tone for all" choice
  /// does. Choices made afterwards are kept beside it.
  Future<void> setDefaultVariant(EmojiModifiers modifiers);

  /// The id of the page the user last had open, or null when none was
  /// remembered. Opaque to the store.
  String? get selectedPageId;

  /// Remembers [id] as the page last open, or forgets it when null.
  Future<void> setSelectedPageId(String? id);

  /// Whether the user keeps the panel docked beside the content rather than
  /// popping it up. Off until chosen.
  ///
  /// A choice, not a state: it says what the user wants when the window is
  /// wide enough, not whether a docked section is on screen now.
  bool get dockPreferred;

  /// Remembers whether the user wants the panel docked.
  Future<void> setDockPreferred({required bool preferred});

  /// Releases the store and its listeners.
  void dispose();
}
