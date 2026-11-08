import 'dart:async';

import 'package:chat_scroll_view_example/src/app/environment_specific/media_disk_sweep.dart'
    as environment_specific;
import 'package:l/l.dart';

/// Tells the time; injected so tests age files without waiting.
typedef MediaDiskClock = DateTime Function();

DateTime _systemClock() => DateTime.now();

/// The one disk store of animated media (ADR 022): a folder whose tiers (the
/// fetcher's stills and clips, the rendered Lottie frames) each keep their
/// files in a [folder] of it, kept by when they were last used rather than
/// each by a budget of its own.
///
/// A tier writes and reads its own files and stamps a file's time when it
/// uses one; the store only removes. A [sweep] removes every file no tier
/// used for [keepFor] and then, when the host sets [limitBytes], the least
/// recently used of the rest, across the tiers, until they fit. The reference
/// clients keep media the same way: no size limit by default, media unused
/// for a month deleted.
///
/// A sweep runs off the frame path (in an isolate of its own) and never
/// holds a tier up: a tier never waits for one, and a file removed under a
/// read is a miss that tier already handles. [start] sweeps at once and then
/// every [sweepEvery]; [dispose] stops that.
final class MediaDiskCache {
  /// Creates the store at [root]. [keepFor] is how long an unused file stays
  /// ([defaultKeepFor]); [limitBytes] the most the files may take together
  /// (null: no limit, the default). [retiredFolders] are folders outside
  /// [root] an older layout kept media in: the first sweep deletes them
  /// (absent ones are fine) and no later one looks again.
  MediaDiskCache(
    this.root, {
    this.retiredFolders = const [],
    this.keepFor = defaultKeepFor,
    this.limitBytes,
    this.sweepEvery = defaultSweepEvery,
    MediaDiskClock clock = _systemClock,
  }) : assert(limitBytes == null || limitBytes > 0, 'a limit keeps something'),
       assert(
         !retiredFolders.any(
           (path) => path == root || path.startsWith('$root/'),
         ),
         'a retired folder is outside the store',
       ),
       _clock = clock;

  /// How long a file no tier uses is kept: one month.
  static const Duration defaultKeepFor = Duration(days: 30);

  /// How often a started store sweeps: hourly, so a long session sheds what
  /// aged out and, under a limit, what it grew past it.
  static const Duration defaultSweepEvery = Duration(hours: 1);

  /// How recently used a file is spared by the limit: a write landing it or
  /// a read under way. The keep period is far longer, so it needs none.
  static const Duration _inUse = Duration(minutes: 1);

  /// The folder the tiers' folders are in.
  final String root;

  /// The folders of an older layout the first sweep deletes.
  final List<String> retiredFolders;

  /// How long a file is kept after its last use.
  final Duration keepFor;

  /// The most bytes the files may take together, or null for no limit.
  final int? limitBytes;

  /// How often [start] sweeps after the first.
  final Duration sweepEvery;

  final MediaDiskClock _clock;
  Timer? _$timer;
  Future<void>? _$sweeping;
  bool _$retiredGone = false;

  /// The folder of the tier [tier].
  String folder(String tier) => '$root/$tier';

  /// Removes what the keep period and the limit say to. One sweep at a
  /// time: a sweep asked for while one runs is that one. Never throws.
  Future<void> sweep() => _$sweeping ??= _sweep().whenComplete(() {
    _$sweeping = null;
  });

  Future<void> _sweep() async {
    try {
      final retire = _$retiredGone ? const <String>[] : retiredFolders;
      _$retiredGone = true;
      await environment_specific.$sweepMediaFolder(
        root,
        retire: retire,
        now: _clock(),
        keepFor: keepFor,
        limitBytes: limitBytes,
        inUse: _inUse,
      );
    } on Object catch (error, stackTrace) {
      // The files stay: a tier keeps working, and the next sweep tries again.
      l.w('The media disk cache could not be swept: $error', stackTrace);
    }
  }

  /// Sweeps now and every [sweepEvery] until [dispose]; idempotent.
  void start() {
    if (_$timer != null) return;
    _$timer = Timer.periodic(sweepEvery, (_) => unawaited(sweep()));
    unawaited(sweep());
  }

  /// Stops the sweeps [start] scheduled; a sweep under way finishes.
  void dispose() {
    _$timer?.cancel();
    _$timer = null;
  }
}
