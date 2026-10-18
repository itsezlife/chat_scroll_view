import 'dart:ui' hide VoidCallback;

import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:listen/listen.dart';

/// An [InlineEmbed] that records what is done to it and signals when a test
/// calls [invalidate].
final class FakeInlineEmbed with ChangeNotifier implements InlineEmbed {
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
