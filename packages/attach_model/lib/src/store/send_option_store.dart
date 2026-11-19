import 'package:attach_model/src/policy/attach_policy.dart';
import 'package:attach_model/src/send/send_options.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// A send option a policy may remember between opens.
enum PersistedSendOption {
  /// [SendOptions.highQuality].
  highQuality,

  /// [SendOptions.videoPreset].
  videoPreset,

  /// [SendOptions.grouped].
  grouped,

  /// [SendOptions.asFiles].
  asFiles,
}

/// What a policy remembers of the send options, and when.
@immutable
final class SendOptionPersistence {
  /// Remembers [options].
  const SendOptionPersistence({
    this.options = const {},
    this.onlyWhenRemembered = false,
    this.presetPerOfferedCount = false,
  });

  /// Remembers nothing.
  static const SendOptionPersistence none = SendOptionPersistence();

  /// The options remembered.
  final Set<PersistedSendOption> options;

  /// Whether a save writes only when the user ticked "Remember".
  final bool onlyWhenRemembered;

  /// Whether the video preset is kept apart for each number of presets
  /// offered (a short video offers fewer).
  final bool presetPerOfferedCount;

  @override
  bool operator ==(Object other) =>
      other is SendOptionPersistence &&
      other.options.length == options.length &&
      other.options.containsAll(options) &&
      other.onlyWhenRemembered == onlyWhenRemembered &&
      other.presetPerOfferedCount == presetPerOfferedCount;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(options),
    onlyWhenRemembered,
    presetPerOfferedCount,
  );
}

/// The **send option store**: where a policy remembers send options between
/// opens, over a [KeyValueStore].
///
/// What is kept is [AttachPolicy.sendOptionPersistence]'s: one value per
/// option under the [namespace], each a plain string. App-wide, not per
/// chat. A value written under another schema version is ignored.
final class SendOptionStore {
  /// A store over [storage] for [policy].
  SendOptionStore(this._storage, {required this.policy});

  /// The namespace this package keeps in the key-value store.
  static const String namespace = 'attach_model';

  /// The schema version of every value written.
  static const int version = 1;

  final KeyValueStore _storage;

  /// Whose persistence rules apply.
  final AttachPolicy policy;

  SendOptionPersistence get _rules => policy.sendOptionPersistence;

  /// [defaults] with every remembered option applied. [offeredPresets] is
  /// how many video presets the item offers, for a policy that keeps the
  /// preset per count; without it no preset is read there.
  Future<SendOptions> restore(
    SendOptions defaults, {
    int? offeredPresets,
  }) async {
    var options = defaults;
    for (final option in _rules.options) {
      final key = _keyOf(option, offeredPresets);
      if (key == null) continue;
      final stored = await _storage.read(namespace, key);
      if (stored == null || stored.version != version) continue;
      options = _apply(options, option, stored.value);
    }
    return options;
  }

  /// Writes the remembered options of [options]. A policy that writes only
  /// when remembered writes nothing unless [remember] is true.
  Future<void> save(
    SendOptions options, {
    bool remember = false,
    int? offeredPresets,
  }) async {
    if (_rules.onlyWhenRemembered && !remember) return;
    for (final option in _rules.options) {
      final key = _keyOf(option, offeredPresets);
      if (key == null) continue;
      final value = switch (option) {
        PersistedSendOption.highQuality => '${options.highQuality}',
        PersistedSendOption.grouped => '${options.grouped}',
        PersistedSendOption.asFiles => '${options.asFiles}',
        PersistedSendOption.videoPreset => options.videoPreset?.toString(),
      };
      if (value == null) {
        await _storage.remove(namespace, key);
      } else {
        await _storage.write(
          namespace,
          key,
          StoredValue(value, version: version),
        );
      }
    }
  }

  String? _keyOf(PersistedSendOption option, int? offeredPresets) =>
      switch (option) {
        PersistedSendOption.highQuality => 'high_quality',
        PersistedSendOption.grouped => 'grouped',
        PersistedSendOption.asFiles => 'as_files',
        PersistedSendOption.videoPreset when !_rules.presetPerOfferedCount =>
          'video_preset',
        PersistedSendOption.videoPreset => switch (offeredPresets) {
          final count? => 'video_preset.$count',
          null => null,
        },
      };

  static SendOptions _apply(
    SendOptions options,
    PersistedSendOption option,
    String value,
  ) => switch (option) {
    PersistedSendOption.highQuality => switch (bool.tryParse(value)) {
      final v? => options.copyWith(highQuality: v),
      null => options,
    },
    PersistedSendOption.grouped => switch (bool.tryParse(value)) {
      final v? => options.copyWith(grouped: v),
      null => options,
    },
    PersistedSendOption.asFiles => switch (bool.tryParse(value)) {
      final v? => options.copyWith(asFiles: v),
      null => options,
    },
    PersistedSendOption.videoPreset => switch (int.tryParse(value)) {
      final v? => options.copyWith(videoPreset: v),
      null => options,
    },
  };
}
