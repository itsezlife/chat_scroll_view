import 'dart:ui' show lerpDouble;

import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/shortcuts/composer_intents.dart';
import 'package:chat_composer/src/spec/action_descriptor.dart';
import 'package:chat_composer/src/spec/composer_header.dart';
import 'package:chat_composer/src/spec/composer_panel.dart';
import 'package:chat_composer/src/spec/composer_spec.dart';
import 'package:chat_composer/src/view/composer_button.dart';
import 'package:chat_composer/src/view/composer_field.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chat_composer/src/view/slot_boxes.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

/// The composer: a glass island holding a header strip, a row of actions
/// around a panel, laid out and animated from a host-built [ComposerSpec].
///
/// The view is declarative. The host rebuilds [spec] from chat state and the
/// island animates from the previous one: the header reveals and hides, the
/// row grows and shrinks with its panel, an action that changes icon morphs.
/// Input lives in the [controller]; the view holds no mode of its own and
/// knows no panel, inset or presentation type.
///
/// ## Slots
///
/// - **Header** ([ComposerSpec.header]): the strip above the row.
/// - **Panel** ([ComposerSpec.panel]): what occupies the row. The text field
///   by default; any other id is built by [panelResolver].
/// - **Actions** ([ComposerSpec.actions]): buttons before and after the
///   panel, mirrored in right-to-left text.
///
/// ## Extent
///
/// The view publishes the height it takes as data on [ComposerController.extent],
/// frame by frame while it animates. It includes the island's margins and the
/// bottom safe-area pad ([safeAreaBottom]) and excludes any panel or keyboard
/// below it. The host adds the presentation occupancy and feeds the sum to
/// the chat's bottom padding.
///
/// ## Environment
///
/// Required above the view: a `ChromeThemeScope`, a `ChromeStringsScope`, a
/// `Directionality`, Material localisations (the text selection menu) and a
/// `MediaQuery`. A `GlassSourceScope`, `GlassQualityScope`, `ChromeMotionScope`
/// and `ChromeIconScope` are optional and refine glass, speed and icons.
class ComposerView extends StatefulWidget {
  /// A view of [spec] over [controller].
  const ComposerView({
    required this.controller,
    required this.spec,
    this.panelResolver,
    this.islandKey,
    this.onFieldTap,
    this.shortcuts,
    this.safeAreaBottom,
    this.maxWidth = ComposerMetrics.maxWidth,
    super.key,
  });

  /// The input state: text, focus, selection, soft keyboard mode. Its
  /// `extent` and `fieldHeight` receive what the view measures.
  final ComposerController controller;

  /// What to show now.
  final ComposerSpec spec;

  /// Builds the panels other than the text field.
  final ComposerPanelResolver? panelResolver;

  /// Key on the glass island, for the `ComposerBottomFade` cutout.
  final GlobalKey? islandKey;

  /// Called when the field is tapped, also if it already has focus.
  final VoidCallback? onFieldTap;

  /// Key bindings; defaults to the [ComposerShortcutPolicy] of the platform.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Bottom safe-area pad inside the view, which counts in the extent.
  /// Defaults to the bottom view padding of the `MediaQuery`; a host that
  /// covers the area (a keyboard or panel stands below) passes zero.
  final double? safeAreaBottom;

  /// Widest the island grows.
  final double maxWidth;

  @override
  State<ComposerView> createState() => _ComposerViewState();
}

class _ComposerViewState extends State<ComposerView>
    with TickerProviderStateMixin {
  // 0 hidden, 1 revealed; the controller value is already curved.
  late final AnimationController _reveal;

  // Progress of the current row height tween, 0 to 1, already curved.
  late final AnimationController _rowProgress;

  // Kept while the strip hides, after the spec has dropped it.
  ComposerHeader? _shownHeader;

  double _rowFrom = ComposerMetrics.islandHeight;
  double _rowTo = ComposerMetrics.islandHeight;
  var _rowLaidOut = false;

  late final Map<Type, Action<Intent>> _intentActions = {
    SubmitComposerIntent: _SubmitAction(this),
    DismissComposerHeaderIntent: _DismissHeaderAction(this),
  };

  ComposerSpec get _spec => widget.spec;

  @override
  void initState() {
    super.initState();
    _shownHeader = _spec.header;
    _reveal = AnimationController(
      vsync: this,
      value: switch (_spec.header) {
        null => 0,
        _ => 1,
      },
    )..addStatusListener(_onRevealStatus);
    _rowProgress = AnimationController(vsync: this, value: 1);
  }

  @override
  void didUpdateWidget(ComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncHeader();
  }

  @override
  void dispose() {
    _reveal
      ..removeStatusListener(_onRevealStatus)
      ..dispose();
    _rowProgress.dispose();
    super.dispose();
  }

  // --- Header reveal ---

  void _syncHeader() {
    final header = _spec.header;
    final motion = ChromeMotionScope.of(
      context,
    ).specOf(MotionRole.headerReveal);
    if (header != null) {
      _shownHeader = header;
      if (_reveal.value < 1 || _reveal.isAnimating) {
        _reveal.animateTo(1, duration: motion.duration, curve: motion.curve);
      }
    } else if (_reveal.value > 0 || _reveal.isAnimating) {
      // animateBack, not animateTo: only a reverse run ends as `dismissed`.
      _reveal.animateBack(0, duration: motion.duration, curve: motion.curve);
    }
  }

  void _onRevealStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    if (_spec.header != null || _shownHeader == null) return;
    setState(() => _shownHeader = null);
  }

  // --- Row height ---

  double get _rowHeight =>
      lerpDouble(_rowFrom, _rowTo, _rowProgress.value) ??
      ComposerMetrics.islandHeight;

  void _onRowMeasured(Size size) {
    if (!mounted) return;
    final target = size.height < ComposerMetrics.islandHeight
        ? ComposerMetrics.islandHeight
        : size.height;

    // The first layout sets the height at once. It must run before the
    // no-change check: a cold start at the default height still counts as
    // laid out, otherwise the first real change would snap.
    if (!_rowLaidOut) {
      _rowLaidOut = true;
      if ((target - _rowTo).abs() < ComposerMetrics.heightEpsilon) return;
      setState(() {
        _rowFrom = target;
        _rowTo = target;
        _rowProgress.value = 1;
      });
      return;
    }

    if ((target - _rowTo).abs() < ComposerMetrics.heightEpsilon) return;

    final motion = ChromeMotionScope.of(
      context,
    ).specOf(MotionRole.listTransition);
    _rowFrom = _rowHeight;
    _rowTo = target;
    _rowProgress
      ..value = 0
      ..animateTo(1, duration: motion.duration, curve: motion.curve);
  }

  // --- Actions ---

  bool _usable(ActionDescriptor action) =>
      _spec.enabled && action.isTappable && !(_spec.busy && action.primary);

  Widget _button(ActionDescriptor action) => ComposerButton(
    key: ValueKey<String>(action.id),
    icon: action.icon,
    semanticLabel: action.semanticLabel,
    onTap: action.onTap,
    enabled: _usable(action),
    primary: action.primary,
  );

  Widget _panel(BuildContext context) {
    final panel = _spec.panel;
    if (panel == ComposerPanelId.text) {
      return ComposerField(
        controller: widget.controller,
        enabled: _spec.enabled,
        onTap: widget.onFieldTap,
      );
    }
    final built = widget.panelResolver?.call(context, panel);
    assert(
      built != null,
      'No panel built for ${panel.value}: pass a panelResolver that knows it.',
    );
    // A short panel centres in the island height; a taller one sets it.
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ComposerMetrics.islandHeight,
      ),
      child: Align(child: built),
    );
  }

  Map<ShortcutActivator, Intent> get _shortcuts =>
      widget.shortcuts ??
      ComposerShortcutPolicy.forPlatform(
        defaultTargetPlatform,
        isWeb: kIsWeb,
      ).shortcuts;

  @override
  Widget build(BuildContext context) {
    final safeBottom =
        widget.safeAreaBottom ?? MediaQuery.viewPaddingOf(context).bottom;

    // Built outside the animation builder so animation ticks do not remount
    // the field and lose focus or the input connection.
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final action in _spec.visibleActions(ActionPlacement.leading))
          _button(action),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey<String>(_spec.panel.value),
            child: _panel(context),
          ),
        ),
        for (final action in _spec.visibleActions(ActionPlacement.trailing))
          _button(action),
      ],
    );

    return HeightReporter(
      onHeight: widget.controller.reportExtent,
      child: Align(
        alignment: AlignmentDirectional.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: ComposerMetrics.islandSideGap,
              end: ComposerMetrics.islandSideGap,
              top: ComposerMetrics.islandTopGap,
              bottom: ComposerMetrics.islandBottomGap + safeBottom,
            ),
            child: Shortcuts(
              shortcuts: _shortcuts,
              child: Actions(
                actions: _intentActions,
                child: Material(
                  type: MaterialType.transparency,
                  child: GlassSurface(
                    key: widget.islandKey,
                    material: GlassMaterial.composerIsland,
                    cornerRadius: ComposerMetrics.islandRadius,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_reveal, _rowProgress]),
                      child: row,
                      builder: (context, row) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_shownHeader case final header?)
                            RevealBox(
                              progress: _reveal.value,
                              extent: ComposerMetrics.headerHeight,
                              child: ComposerHeaderStrip(header: header),
                            ),
                          DrivenHeightBox(
                            height: _rowHeight,
                            onChildSize: _onRowMeasured,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 2,
                              ),
                              child: row,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmitAction extends Action<SubmitComposerIntent> {
  _SubmitAction(this._state);

  final _ComposerViewState _state;

  ActionDescriptor? get _target {
    final primary = _state._spec.primaryAction;
    if (primary == null || !_state._usable(primary)) return null;
    return primary;
  }

  // A composing IME uses Enter to confirm the composition; the shortcut must
  // let it through.
  @override
  bool isEnabled(SubmitComposerIntent intent) =>
      !_state.widget.controller.text.isComposing && _target != null;

  @override
  Object? invoke(SubmitComposerIntent intent) {
    _target?.onTap?.call();
    return null;
  }
}

class _DismissHeaderAction extends Action<DismissComposerHeaderIntent> {
  _DismissHeaderAction(this._state);

  final _ComposerViewState _state;

  @override
  bool isEnabled(DismissComposerHeaderIntent intent) =>
      _state._spec.header?.onDismiss != null;

  @override
  Object? invoke(DismissComposerHeaderIntent intent) {
    _state._spec.header?.onDismiss?.call();
    return null;
  }
}
