import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/chrome/media_chrome_slots.dart';
import 'package:message_media/src/chrome/media_spoiler_reveal.dart';
import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/paint/media_box_cell.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:mpx_core/mpx_core.dart';

/// How a spoiler's cover looks: the blur of its copy and the particles
/// drifting over it.
@immutable
final class MediaSpoilerLook {
  /// A look of the given blur and particles.
  const MediaSpoilerLook({
    required this.blurSigma,
    required this.areaPerParticle,
    required this.minParticleRadius,
    required this.maxParticleRadius,
    required this.speed,
    this.dim = const Color(0x00000000),
    this.particleColor = const Color(0xFFFFFFFF),
  });

  /// A strong blur under dense, fine, slowly drifting particles.
  const MediaSpoilerLook.android()
    : this(
        blurSigma: 24,
        areaPerParticle: 60,
        minParticleRadius: 0.5,
        maxParticleRadius: 1.3,
        speed: 6,
      );

  /// A dust of very fine particles.
  const MediaSpoilerLook.ios()
    : this(
        blurSigma: 24,
        areaPerParticle: 35,
        minParticleRadius: 0.4,
        maxParticleRadius: 1,
        speed: 8,
      );

  /// A blurred, slightly dimmed picture under sparse dots.
  const MediaSpoilerLook.desktop()
    : this(
        blurSigma: 20,
        areaPerParticle: 90,
        minParticleRadius: 0.6,
        maxParticleRadius: 1.4,
        speed: 5,
        dim: const Color(0x26000000),
      );

  /// The look of [family].
  factory MediaSpoilerLook.of(MessageMediaPlatform family) => switch (family) {
    MessageMediaPlatform.android => const MediaSpoilerLook.android(),
    MessageMediaPlatform.ios => const MediaSpoilerLook.ios(),
    MessageMediaPlatform.desktop => const MediaSpoilerLook.desktop(),
  };

  /// The blur of the picture's copy, in logical pixels.
  final double blurSigma;

  /// The cover's area per particle; the particle count follows the cell's
  /// size.
  final double areaPerParticle;

  /// The smallest particle's radius.
  final double minParticleRadius;

  /// The largest particle's radius.
  final double maxParticleRadius;

  /// How fast particles drift, in logical pixels a second.
  final double speed;

  /// A fill over the blurred copy, under the particles.
  final Color dim;

  /// The particles' colour.
  final Color particleColor;

  @override
  bool operator ==(Object other) =>
      other is MediaSpoilerLook &&
      other.blurSigma == blurSigma &&
      other.areaPerParticle == areaPerParticle &&
      other.minParticleRadius == minParticleRadius &&
      other.maxParticleRadius == maxParticleRadius &&
      other.speed == speed &&
      other.dim == dim &&
      other.particleColor == particleColor;

  @override
  int get hashCode => Object.hash(
    blurSigma,
    areaPerParticle,
    minParticleRadius,
    maxParticleRadius,
    speed,
    dim,
    particleColor,
  );
}

/// The default spoiler cover: a blurred copy of the item's picture under
/// drifting particles, clipped to the cell's corners, uncovered as the
/// reveal says (a hole grown from the touch point, or a fade).
///
/// The copy is the same cache entry as the picture under it, at the same
/// decode, so it costs no second download or decode. The particles stand
/// still under reduce motion and while tickers are off.
class MediaSpoilerCover extends StatefulWidget {
  /// A cover of [item]'s picture, [size], rounded by [radii].
  const MediaSpoilerCover({
    required this.item,
    required this.size,
    required this.reveal,
    required this.origin,
    required this.form,
    this.radii = MediaCornerRadii.zero,
    this.look = const MediaSpoilerLook.android(),
    this.downloadContext,
    super.key,
  });

  /// The [MediaSpoilerBuilder] of the default cover, in the family's look.
  static Widget builder(BuildContext context, MediaSpoilerData data) =>
      MediaSpoilerCover(
        item: data.chrome.item,
        size: data.chrome.cell.rect.size,
        radii: data.chrome.cell.radii,
        reveal: data.reveal,
        origin: data.origin,
        form: data.form,
        look: MediaSpoilerLook.of(data.chrome.family),
        downloadContext: data.chrome.downloadContext,
      );

  /// The item covered.
  final MediaItem item;

  /// The cell's size.
  final Size size;

  /// The cell's corners.
  final MediaCornerRadii radii;

  /// The reveal's progress: 0 hidden, 1 revealed.
  final Animation<double> reveal;

  /// Where the reveal starts, in the cell's coordinates.
  final Offset origin;

  /// How the reveal uncovers the cell.
  final MediaSpoilerReveal form;

  /// The blur and the particles.
  final MediaSpoilerLook look;

  /// The class of conversation the media is shown in.
  final AutoDownloadContext? downloadContext;

  @override
  State<MediaSpoilerCover> createState() => _MediaSpoilerCoverState();
}

class _MediaSpoilerCoverState extends State<MediaSpoilerCover>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  late final Ticker _ticker = createTicker(
    (elapsed) => _elapsed.value = elapsed,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _ticker.isActive) {
      _ticker.stop();
    } else if (!still && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final copy = MediaBoxCell(item: widget.item, size: widget.size);
    return AnimatedBuilder(
      animation: widget.reveal,
      builder: (context, child) {
        final progress = widget.reveal.value;
        final opacity = widget.form.coverOpacityOf(progress);
        return Opacity(
          opacity: opacity,
          child: ClipPath(
            clipper: _RevealClipper(
              radii: widget.radii,
              origin: widget.origin,
              hole: widget.form.holeRadiusOf(
                widget.size,
                widget.origin,
                progress,
              ),
            ),
            child: child,
          ),
        );
      },
      child: SizedBox.fromSize(
        size: widget.size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: look.blurSigma,
                sigmaY: look.blurSigma,
                tileMode: TileMode.mirror,
              ),
              child: ContentAssetView(
                content: widget.item.descriptor.key,
                preset: copy.presetOf(AssetFit.cover, animate: false),
                downloadContext: widget.downloadContext,
              ),
            ),
            ColoredBox(color: look.dim),
            CustomPaint(
              painter: _ParticlesPainter(
                look: look,
                seed: widget.item.id.hashCode,
                elapsed: _elapsed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The cell's rounded rect, less the reveal's hole around the origin.
class _RevealClipper extends CustomClipper<Path> {
  const _RevealClipper({
    required this.radii,
    required this.origin,
    required this.hole,
  });

  final MediaCornerRadii radii;
  final Offset origin;
  final double? hole;

  @override
  Path getClip(Size size) {
    final cover = Path()..addRRect(radii.toRRect(Offset.zero & size));
    final hole = this.hole;
    if (hole == null || hole <= 0) return cover;
    return Path.combine(
      PathOperation.difference,
      cover,
      Path()..addOval(Rect.fromCircle(center: origin, radius: hole)),
    );
  }

  @override
  bool shouldReclip(_RevealClipper oldClipper) =>
      oldClipper.radii != radii ||
      oldClipper.origin != origin ||
      oldClipper.hole != hole;
}

// Particles at seeded places drifting in seeded directions, wrapping at the
// edges, twinkling; repaints with [elapsed], never rebuilds.
class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter({
    required this.look,
    required this.seed,
    required this.elapsed,
  }) : super(repaint: elapsed);

  final MediaSpoilerLook look;
  final int seed;
  final ValueNotifier<Duration> elapsed;

  static const int _maxParticles = 900;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final count = (size.width * size.height / look.areaPerParticle)
        .round()
        .clamp(1, _maxParticles);
    final random = math.Random(seed);
    final seconds =
        elapsed.value.inMicroseconds / Duration.microsecondsPerSecond;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final angle = random.nextDouble() * 2 * math.pi;
      final speed = look.speed * (0.5 + random.nextDouble());
      final x =
          (random.nextDouble() * size.width +
              math.cos(angle) * speed * seconds) %
          size.width;
      final y =
          (random.nextDouble() * size.height +
              math.sin(angle) * speed * seconds) %
          size.height;
      final radius =
          look.minParticleRadius +
          random.nextDouble() *
              (look.maxParticleRadius - look.minParticleRadius);
      final phase = random.nextDouble() * 2 * math.pi;
      final alpha = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase + seconds * 2));
      paint.color = look.particleColor.withValues(
        alpha: look.particleColor.a * alpha,
      );
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter oldDelegate) =>
      oldDelegate.look != look ||
      oldDelegate.seed != seed ||
      oldDelegate.elapsed != elapsed;
}
