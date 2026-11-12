import 'dart:ui' hide VoidCallback;

import 'package:catalog_assets/src/asset/asset_playback.dart';
import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:flutter/rendering.dart' show PaintingContext, TextureLayer;
import 'package:listen/listen.dart';

/// An [InlineEmbed] that records what is done to it and signals when a test
/// calls [invalidate].
base class FakeInlineEmbed with ChangeNotifier implements InlineEmbed {
  /// Creates an embed reserving [sizeHint].
  FakeInlineEmbed({this.sizeHint = const Size(18, 18)});

  @override
  final Size sizeHint;

  @override
  bool visible = true;

  /// Every painted rectangle with its context, in order.
  final List<({Rect rect, InlineEmbedPaintContext context})> paints = [];

  /// How many times [dispose] was called.
  int disposals = 0;

  /// Whether [dispose] was called.
  bool get isDisposed => disposals > 0;

  /// Signals the listeners that what the embed paints changed.
  void invalidate() {
    if (!isDisposed) notifyListeners();
  }

  @override
  void paint(Canvas canvas, Rect rect, InlineEmbedPaintContext context) {
    if (isDisposed) return;
    paints.add((rect: rect, context: context));
  }

  @override
  void dispose() {
    if (isDisposed) return;
    disposals++;
    super.dispose();
  }
}

/// A [FakeInlineEmbed] that plays: a test sets [playback] and [startsReplays],
/// and reads how often it was asked to [replay].
final class FakePlayableEmbed extends FakeInlineEmbed implements PlayableEmbed {
  /// Creates a playable embed that starts [AssetPlayback.playing].
  FakePlayableEmbed({
    super.sizeHint,
    AssetPlayback playback = AssetPlayback.playing,
  }) : _playback = playback;

  AssetPlayback _playback;

  /// Whether [replay] starts a pass when the pass is not running.
  bool startsReplays = true;

  /// How many times [replay] was called.
  int replays = 0;

  @override
  AssetPlayback get playback => switch (_playback) {
    _ when isDisposed => AssetPlayback.idle,
    AssetPlayback.playing when !visible => AssetPlayback.idle,
    final playback => playback,
  };

  /// Moves the playback and signals the listeners, as a binding would.
  set playback(AssetPlayback value) {
    _playback = value;
    invalidate();
  }

  @override
  bool replay() {
    replays++;
    if (isDisposed || !visible || !startsReplays) return false;
    if (_playback == AssetPlayback.playing) return false;
    playback = AssetPlayback.playing;
    return true;
  }
}

/// A [FakeInlineEmbed] that composites: a test makes it [play], on a texture
/// or on the canvas, and reads where it was [composited].
///
/// While it plays on a texture, [composite] adds a texture layer of exactly
/// the rectangle; otherwise it paints, as recorded in `paints`.
final class FakeCompositingEmbed extends FakeInlineEmbed
    implements CompositingEmbed {
  /// Creates an embed that does not play.
  FakeCompositingEmbed({super.sizeHint});

  bool _playing = false;
  int? _textureId;

  /// Every rectangle [composite] was called with, in order.
  final List<Rect> composited = [];

  /// Starts playing, its frames on texture [textureId] (on the canvas when
  /// null), and signals the listeners.
  void play({int? textureId}) {
    _playing = true;
    _textureId = textureId;
    invalidate();
  }

  /// Stops playing and signals the listeners.
  void stop() {
    _playing = false;
    _textureId = null;
    invalidate();
  }

  @override
  bool get needsCompositing => _playing && !isDisposed;

  @override
  void composite(
    PaintingContext context,
    Rect rect,
    InlineEmbedPaintContext paint,
  ) {
    if (isDisposed) return;
    composited.add(rect);
    if (_textureId case final id? when _playing) {
      context.addLayer(TextureLayer(rect: rect, textureId: id));
      return;
    }
    this.paint(context.canvas, rect, paint);
  }
}

/// An [InlineEmbedResolver] over a table of schemes, recording what it was
/// asked and handing out [FakeInlineEmbed]s.
final class FakeInlineEmbedResolver implements InlineEmbedResolver {
  /// Creates a resolver that knows [schemes].
  FakeInlineEmbedResolver({this.schemes = const {'fake'}});

  /// The schemes this resolver resolves; any other target yields null.
  final Set<String> schemes;

  /// Every target asked for, in order.
  final List<InlineEmbedTarget> asked = [];

  /// Every embed handed out, in order.
  final List<FakeInlineEmbed> made = [];

  @override
  InlineEmbed? resolve(InlineEmbedTarget target, InlineEmbedMetrics metrics) {
    asked.add(target);
    if (!schemes.contains(target.scheme)) return null;
    final embed = FakeInlineEmbed(
      sizeHint: Size.square(1.2 * (metrics.ascent + metrics.descent)),
    );
    made.add(embed);
    return embed;
  }
}
