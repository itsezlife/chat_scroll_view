import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';

/// Where the leases of one frame scheduler play now, as the schedulers'
/// `leasePlaces()` reads it.
typedef LabLeasePlaces = ({
  int onTextures,
  int onSlots,
  int forCanvas,
  int kept,
  List<Object> slotKeys,
});

/// The scroll lab's view of the media path: which content reaches the GPU
/// as a page upload, whose it is (the chat's or another surface's), each
/// decode start, the panel's show and hide, and the texture pool around
/// them.
///
/// Wired only in a `SCROLL_LAB` build (`DemoConfig.scrollLab`): the hooks it
/// fills are null otherwise, and the packages then collect nothing.
///
/// Trace marks (timeline slices and instants, read with the trace):
///
/// - `LABup <side>x<rows> <KiB>K <owner> <keys>` around each page upload call
///   (the `decodeImageFromPixelsSync` whose raster half is `SnapshotImage`).
/// - `LABdecode <form> <part> <owner> <key> <w>x<h>` at each decode start.
/// - `LABpanel <state> @<ms>` at each change of the panel's visibility.
///
/// Log lines (`adb logcat -s flutter | grep LAB`):
///
/// - `LAB media up=<n> upKiB=<KiB> chatUp=<n> chatUpKiB=<KiB> ...` once a
///   second while any upload or decode happened: uploads and their KiB, the
///   chat's among them, then `decodes=` and `chatDecodes=`.
/// - `LAB pool <when> ...` at the panel's show and at +0, +1 and +2 s after
///   it hides, and on the `pool` command.
abstract final class LabMediaTrace {
  /// Writes a `LAB` line; set by `ScrollLab.install`.
  static void Function(String message) log = (_) {};

  /// Every content key the chat's bodies made an embed of, as text: an
  /// upload or a decode of one of these is the chat's. The panel's own cells
  /// are not listed; a key in both counts as the chat's, and its size tells
  /// them apart.
  static final Set<String> chatContent = <String>{};

  /// Notes that a chat body shows [content].
  static void noteChat(ContentKey content) => chatContent.add('$content');

  /// The texture pool, for the pool lines.
  static FrameTexturePool? pool;

  /// The frame schedulers' lease places by name (`lottie`, `video`).
  static final Map<String, LabLeasePlaces Function()> schedulers = {};

  static String _ownerOfContent(String content) =>
      chatContent.contains(content) ? 'chat' : 'other';

  // A lease key reads `<content>@<w>x<h>` (the decoders name theirs so).
  static String _ownerOfKey(Object key) =>
      _ownerOfContent('$key'.split('@').first);

  static int _ups = 0;
  static int _upBytes = 0;
  static int _chatUps = 0;
  static int _chatUpBytes = 0;
  static int _decodes = 0;
  static int _chatDecodes = 0;
  static Timer? _second;

  static void _count() {
    _second ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ups == 0 && _decodes == 0) return;
      log(
        'media up=$_ups upKiB=${_upBytes >> 10} chatUp=$_chatUps '
        'chatUpKiB=${_chatUpBytes >> 10} decodes=$_decodes '
        'chatDecodes=$_chatDecodes',
      );
      _ups = _upBytes = _chatUps = _chatUpBytes = 0;
      _decodes = _chatDecodes = 0;
    });
  }

  /// The atlases' upload trace (`FrameAtlas.uploadTrace`): marks the upload
  /// call with its size and owner, and counts it.
  static Future<ui.Image> traceUpload(
    FramePageUpload upload,
    Future<ui.Image> Function() run,
  ) {
    final chat = upload.keys.any((key) => _ownerOfKey(key) == 'chat');
    _count();
    _ups++;
    _upBytes += upload.bytes;
    if (chat) {
      _chatUps++;
      _chatUpBytes += upload.bytes;
    }
    final keys = upload.keys.join(',');
    return Timeline.timeSync(
      'LABup ${upload.side}x${upload.rows} ${upload.bytes >> 10}K '
      '${chat ? 'chat' : 'other'} $keys',
      run,
    );
  }

  /// [decoder] with each decode start marked and counted.
  static Decoder traceDecodes(Decoder decoder, MediaForm form) =>
      _LabDecoder(decoder, form);

  /// Follows the panel's visibility: a `LABpanel` mark at each change, a pool
  /// line as it shows and at +0, +1 and +2 s after it hides. Returns the
  /// stop.
  static void Function() watchPanel(
    listen.ValueListenable<PanelVisibility> visibility,
  ) {
    var last = visibility.value;
    final timers = <Timer>[];
    void follow() {
      final state = visibility.value;
      if (state.runtimeType == last.runtimeType) return;
      last = state;
      final name = switch (state) {
        PanelVisibility$Showing() => 'showing',
        PanelVisibility$Shown() => 'shown',
        PanelVisibility$Hiding() => 'hiding',
        PanelVisibility$Hidden() => 'hidden',
      };
      Timeline.instantSync('LABpanel $name @${nowMs()}');
      log('panel $name');
      if (state case PanelVisibility$Showing()) reportPool('showing');
      if (state case PanelVisibility$Hidden()) {
        for (final timer in timers) {
          timer.cancel();
        }
        timers.clear();
        reportPool('hidden+0s');
        for (final s in [1, 2]) {
          timers.add(
            Timer(Duration(seconds: s), () => reportPool('hidden+${s}s')),
          );
        }
      }
    }

    visibility.addListener(follow);
    return () {
      visibility.removeListener(follow);
      for (final timer in timers) {
        timer.cancel();
      }
    };
  }

  /// The monotonic time of the timeline, in milliseconds: the clock of the
  /// trace's Dart marks and of `FrameTiming`.
  static String nowMs() => (Timeline.now / 1000).toStringAsFixed(1);

  static int _missedLeases = 0;
  static int _warmsShort = 0;

  /// One `LAB pool <when>` line: the texture pool by class
  /// (`<class>:<leased>/<idle>/<kept>`), its leases that found no texture and
  /// its warms short of room since the last line, and where each scheduler's
  /// leases play (`tex`, `slot`, `canvas`, `kept`, and the chat's on slots).
  static void reportPool(String when) {
    final buffer = StringBuffer('pool $when');
    if (pool case final pool?) {
      final classes = [
        for (final MapEntry(:key, :value) in pool.classCounts().entries)
          if (value.leased + value.idle > 0)
            '$key:${value.leased}/${value.idle}/${value.kept}',
      ].join(',');
      buffer.write(
        ' leased=${pool.leasedTextures} idle=${pool.idleTextures} '
        'kept=${pool.keptFrames} MiB=${pool.bytes >> 20}/'
        '${pool.budgetBytes >> 20} '
        'missed=+${pool.missedLeases - _missedLeases} '
        'shortOfRoom=+${pool.warmsShortOfRoom - _warmsShort} '
        'classes=$classes',
      );
      _missedLeases = pool.missedLeases;
      _warmsShort = pool.warmsShortOfRoom;
    } else {
      buffer.write(' no texture host');
    }
    for (final MapEntry(:key, value: read) in schedulers.entries) {
      final places = read();
      final chatOnSlots = [
        for (final slotKey in places.slotKeys)
          if (_ownerOfKey(slotKey) == 'chat') slotKey,
      ];
      buffer.write(
        ' | $key tex=${places.onTextures} slot=${places.onSlots} '
        'canvas=${places.forCanvas} kept=${places.kept} '
        'chatOnSlots=${chatOnSlots.length}'
        '${chatOnSlots.isEmpty ? '' : ' [${chatOnSlots.join(',')}]'}',
      );
    }
    log(buffer.toString());
  }
}

final class _LabDecoder implements Decoder {
  _LabDecoder(this._decoder, this._form);

  final Decoder _decoder;
  final MediaForm _form;

  @override
  AssetTask decode(DecodeRequest request, AssetProgress progress) {
    final content = '${request.descriptor.key}';
    final owner = LabMediaTrace._ownerOfContent(content);
    LabMediaTrace._count();
    LabMediaTrace._decodes++;
    if (owner == 'chat') LabMediaTrace._chatDecodes++;
    Timeline.instantSync(
      'LABdecode ${_form.name} ${request.part.name} $owner $content '
      '${request.spec.pixelWidth}x${request.spec.pixelHeight}',
    );
    return _decoder.decode(request, progress);
  }
}
