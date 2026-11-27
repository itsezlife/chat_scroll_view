import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/src/capabilities/composer_capability_state.dart';
import 'package:chat_composer/src/capabilities/composer_denied_forms.dart';
import 'package:chat_composer/src/capabilities/composer_slow_mode_forms.dart';
import 'package:chat_composer/src/capabilities/composer_slow_mode_state.dart';
import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/menu/composer_menu_policy.dart';
import 'package:chat_composer/src/shortcuts/composer_formatting_actions.dart';
import 'package:chat_composer/src/shortcuts/composer_intents.dart';
import 'package:chat_composer/src/spec/action_descriptor.dart';
import 'package:chat_composer/src/spec/composer_header.dart';
import 'package:chat_composer/src/spec/composer_panel.dart';
import 'package:chat_composer/src/spec/composer_spec.dart';
import 'package:chat_composer/src/view/composer_access_panel.dart';
import 'package:chat_composer/src/view/composer_button.dart';
import 'package:chat_composer/src/view/composer_field.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chat_composer/src/view/composer_length_counter.dart';
import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chat_composer/src/view/composer_primary_style.dart';
import 'package:chat_composer/src/view/listen_value_builder.dart';
import 'package:chat_composer/src/view/slot_boxes.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart'
    show ExtendedEditableTextState, ProcessTextQueryCache;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart' show BinaryMessenger, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;

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
/// ## Capabilities
///
/// With [capabilities], the chat's rights shape the row
/// (each change applies on the next value, the draft kept):
///
/// - a write access other than `canWrite` puts its default panel in the
///   row in place of [ComposerSpec.panel] (`ComposerPanelId.forWriteAccess`),
///   built by [panelResolver] when it knows the id, else as a plain text
///   node with the host's denial text and [accessAction];
/// - `sending.text` denied locks the field: disabled, the host's denial text
///   as its placeholder (after a lock on Android), still focusable and
///   announced as not available with that text as its hint, a tap (or
///   activation) reported to the host; the actions stay usable;
/// - an action whose `ActionDescriptor.capability` is denied is drawn
///   dimmed ([deniedForms]), stays focusable, is announced as not available
///   with the denial text as its hint, and a tap reports the attempt instead
///   of calling its `onTap`;
/// - in slow mode, a send during the wait or while a message is still
///   sending is refused (the text stays) and reported as `sendNow` with the
///   wait left; the countdown shows as [deniedForms]' `slowMode` places it
///   (on the send button, or as the empty field's placeholder), and is
///   announced politely when it starts and when it ends. A view that mounts
///   into a running countdown announces only its end.
///
/// The rules are the controller's: the view binds [capabilities] to it
/// while mounted (`ComposerController.bindCapabilities`) and draws
/// `ComposerController.capabilities`; texts come from, and attempts are
/// reported through, its `capabilityFeedback`. A host that draws its own
/// row binds the controller itself and keeps every rule. Without
/// capabilities the view is what it was before them.
///
/// ## Extent
///
/// The view publishes the height it takes as data on [ComposerController.extent],
/// frame by frame while it animates. It includes the island's margins and
/// excludes the bottom safe-area pad ([safeAreaBottom]) and any panel or
/// keyboard below it. The pad is left out because it is the host's to add: the
/// host knows the band the keyboard or the panel has covered, and the
/// measurement arrives a frame after the layout it measures, so a pad that
/// moved with the keyboard would show in the chat's bottom padding a frame late.
/// The host adds the presentation's bottom band (the larger of the safe area
/// and the occupancy) and feeds the sum to the chat's bottom padding.
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
    this.onFieldPointerDown,
    this.onFieldPointerEnd,
    this.shortcuts,
    this.menuPolicy,
    this.primaryStyle = ComposerPrimaryStyle.disc,
    this.safeAreaBottom,
    this.maxWidth = ComposerMetrics.maxWidth,
    this.fieldStartInset = 0,
    this.hintFontSize,
    this.hintText,
    this.hintMaxLines,
    this.primaryDiameter = ComposerMetrics.primaryDiscDiameter,
    this.autofocus = true,
    this.accessAction,
    this.deniedForms,
    this.capabilities,
    super.key,
  });

  /// Asks the platform now for the text processing actions the field's
  /// selection toolbar offers (the apps that take selected text), so the
  /// first composer that mounts does not.
  ///
  /// They are asked once per app run. On Android the query blocks the UI
  /// thread, and asked by the field it lands in the frame the composer first
  /// shows in, often during the route transition bringing the chat in. A host
  /// calls this at an idle moment before its first composer, such as after
  /// its first frame. Calls after the first do nothing.
  static void prefetchTextActions() =>
      ExtendedEditableTextState.prefetchProcessTextActions();

  /// The app's messenger to the platform, [platform], with the text
  /// processing actions query answered once per app run for every text field
  /// of the app: the stock ones too (a panel's search field), which ask on
  /// every mount and have no hook of their own.
  ///
  /// A host returns it from its binding's `createBinaryMessenger`; the
  /// query [prefetchTextActions] makes is then the only one the platform
  /// sees, and a field that mounts later costs no platform call.
  static BinaryMessenger shareTextActions(BinaryMessenger platform) =>
      ProcessTextQueryCache(platform);

  /// The input state: text, focus, selection, soft keyboard mode. Its
  /// `extent` and `fieldHeight` receive what the view measures.
  final ComposerController controller;

  /// What to show now.
  final ComposerSpec spec;

  /// Builds the panels other than the text field.
  final ComposerPanelResolver? panelResolver;

  /// Key on the glass island, for a host that measures it (to anchor a popup
  /// to it, say).
  final GlobalKey? islandKey;

  /// Called when the field is tapped, also if it already has focus.
  final VoidCallback? onFieldTap;

  /// Called when a pointer goes down on the field, before the field reacts to
  /// it. A host whose panel suppresses the keyboard lifts the suppression
  /// here, so the focus the tap brings attaches with a keyboard type and the
  /// keyboard already up (for a search field in the panel) stays up.
  final VoidCallback? onFieldPointerDown;

  /// Called when that pointer lifts or is cancelled. When the press was a tap,
  /// [onFieldTap] follows in the same event.
  final VoidCallback? onFieldPointerEnd;

  /// Key bindings; defaults to the [ComposerShortcutPolicy] of the platform.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// How the field presents its menu; defaults to the [ComposerMenuPolicy] of
  /// the platform: the floating toolbar on a touch platform, and on desktop
  /// (and the web) the pointer menu for a secondary click, with the toolbar
  /// kept for touch.
  final ComposerMenuPolicy? menuPolicy;

  /// How the primary action (the send) is drawn: a filled disc (the default), or the
  /// bare glyph in the send colour.
  final ComposerPrimaryStyle primaryStyle;

  /// Bottom safe-area pad inside the view, which does not count in the
  /// extent. Defaults to the bottom view padding of the `MediaQuery`; a host
  /// that covers the area (a keyboard or panel stands below) passes what is
  /// left of it.
  final double? safeAreaBottom;

  /// Widest the island grows.
  final double maxWidth;

  /// Inset between the island's start edge and the field text, applied only
  /// while the island has no visible leading action (a leading action's own
  /// slot already keeps the text off the edge, so the chat composer is
  /// unchanged). Directional: it flips in right-to-left. Zero, the default,
  /// adds nothing.
  final double fieldStartInset;

  /// Font size of the field's hint; null keeps the field's own size (the
  /// chat). A host with long hints sets a smaller one.
  final double? hintFontSize;

  /// The field's hint in place of the strings' message hint (a caption
  /// field says "Add a caption"); null for the message hint.
  final String? hintText;

  /// Most lines the hint takes before an ellipsis; null lets it wrap (the
  /// chat). One keeps a long hint on the field's line.
  final int? hintMaxLines;

  /// Diameter of the filled disc of a [ComposerPrimaryStyle.disc] primary
  /// action.
  final double primaryDiameter;

  /// Whether the text field takes focus the first time it is built.
  ///
  /// The caret is there when the chat opens on
  /// every platform, and on a touch platform the soft keyboard is not: the
  /// field attaches without a keyboard type, and the first tap on it (or
  /// `requestKeyboard`) brings the keyboard, as for a field that attached
  /// while [ComposerController.softKeyboard] was suppressed.
  ///
  /// Once per view: a field that comes back after another panel held the row
  /// (a restriction lifted, a recording ended) does not take focus again.
  /// Read when the view mounts; a later change has no effect.
  final bool autofocus;

  /// The host's action on a default write-access panel (a join verb, the
  /// unlock of an `unlockable` restriction), or null for panels of text
  /// alone.
  final ComposerPanelActionResolver? accessAction;

  /// How denied actions and the locked field are drawn; null takes the
  /// platform's ([ComposerDeniedForms.forPlatform]).
  final ComposerDeniedForms? deniedForms;

  /// The chat's capabilities, whose `limits.messageLength` is the message
  /// length budget when [ComposerSpec.messageLengthLimit] is null; an explicit
  /// spec limit wins. Null leaves the budget to the spec alone. A change of
  /// the limit reaches the counter and the send refusal at once.
  ///
  /// Their `writeAccess` and `sending` rights also pick the row's panel,
  /// lock the field and dim denied actions (see "Capabilities" above).
  final listen.ValueListenable<ChatCapabilities>? capabilities;

  @override
  State<ComposerView> createState() => _ComposerViewState();
}

class _ComposerViewState extends State<ComposerView>
    with TickerProviderStateMixin {
  // 0 hidden, 1 revealed; the controller value is already curved.
  late final AnimationController _reveal;

  // Progress of the current row height tween, 0 to 1, already curved.
  late final AnimationController _rowProgress;

  // The refusal of an over-budget send, 0 at rest.
  late final AnimationController _shake;

  // Kept while the strip hides, after the spec has dropped it.
  ComposerHeader? _shownHeader;

  // Whether the next field built takes focus: true until the first one is.
  late var _autofocusPending = widget.autofocus;

  double _rowFrom = ComposerMetrics.islandHeight;
  double _rowTo = ComposerMetrics.islandHeight;
  var _rowLaidOut = false;

  late final Map<Type, Action<Intent>> _intentActions = {
    SubmitComposerIntent: _SubmitAction(this),
    DismissComposerHeaderIntent: _DismissHeaderAction(this),
    ...ComposerFormattingActions.of(
      text: widget.controller.text,
      linkPrompt: () => _spec.linkPrompt,
      context: () => context,
      isAlive: () => mounted,
    ),
  };

  ComposerSpec get _spec => widget.spec;

  // The countdown last heard, to tell which redraws change the row.
  var _slowState = ComposerSlowModeState.free;

  // The countdown's starts and ends, announced; heard once bound.
  StreamSubscription<ComposerSlowModeEdge>? _slowModeEdges;

  // Whether the capabilities were bound: on the first dependencies, since
  // the host's panel resolver may read inherited widgets.
  var _bound = false;

  ComposerController get _controller => widget.controller;

  ComposerCapabilityState get _capabilities => _controller.capabilities.value;

  // The budget in force: the spec's, else the chat's.
  int? get _messageLengthLimit =>
      _spec.messageLengthLimit ?? _capabilities.messageLength;

  @override
  void initState() {
    super.initState();
    _shownHeader = _spec.header;
    _controller.capabilities.addListener(_onCapabilities);
    _controller.slowMode.addListener(_onSlowModeState);
    _reveal = AnimationController(
      vsync: this,
      value: switch (_spec.header) {
        null => 0,
        _ => 1,
      },
    )..addStatusListener(_onRevealStatus);
    _rowProgress = AnimationController(vsync: this, value: 1);
    _shake = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _bind();
  }

  @override
  void didUpdateWidget(ComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.capabilities, widget.capabilities) ||
        oldWidget.deniedForms != widget.deniedForms) {
      _bind();
    }
    _syncHeader();
  }

  // --- Capabilities ---

  // Hands the controller the chat's capabilities; what they decide is the
  // controller's, and this view draws it.
  void _bind() {
    if (widget.capabilities == null && !_capabilities.isBound) return;
    _controller.bindCapabilities(
      widget.capabilities,
      forms: _deniedForms,
      hostBuilds: _hostBuilds,
    );
    _slowState = _controller.slowMode.value;
    // After the first bind, so a view that mounts into a running countdown
    // announces only its end.
    _slowModeEdges ??= _controller.slowModeEdges.listen(_announceEdge);
  }

  bool _hostBuilds(ComposerPanelId panel) =>
      mounted && widget.panelResolver?.call(context, panel) != null;

  void _onCapabilities() {
    if (mounted) setState(() {});
  }

  // --- Slow mode ---

  ComposerSlowModeForms get _slowModeForms => _deniedForms.slowMode;

  bool get _slowModeActive => _capabilities.slowModeActive;

  // Rebuilds the row only when what it draws changes: the held send (held
  // actions, the submit key) or, with the countdown in the placeholder, the
  // text it shows. The send button's countdown rebuilds by itself.
  void _onSlowModeState() {
    if (!mounted) return;
    final before = _slowState;
    final next = _controller.slowMode.value;
    _slowState = next;
    if (before.holdsSend != next.holdsSend ||
        _countdownHint(before) != _countdownHint(next)) {
      setState(() {});
    }
  }

  void _announceEdge(ComposerSlowModeEdge edge) {
    if (!mounted) return;
    final strings = ChromeStringsScope.composerOf(context);
    _announce(switch (edge) {
      ComposerSlowModeEdge.started => strings.slowModeStarted(
        _countdownText(_controller.slowMode.value),
      ),
      ComposerSlowModeEdge.ended => strings.slowModeEnded,
    });
  }

  // Politely, so it waits for what the reader is saying.
  void _announce(String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    SemanticsService.sendAnnouncement(
      view,
      message,
      Directionality.of(context),
    ).ignore();
  }

  String _countdownText(ComposerSlowModeState state) =>
      ChromeStringsScope.composerOf(context).slowModeCountdown(state.remaining);

  // The empty field's placeholder during the countdown, where the platform
  // puts it there; null otherwise.
  String? _countdownHint(ComposerSlowModeState state) =>
      switch ((_slowModeForms.countdown, state.isCounting)) {
        (ComposerCountdownPlacement.placeholder, true) => _countdownText(state),
        _ => null,
      };

  ComposerDeniedForms get _deniedForms =>
      widget.deniedForms ??
      ComposerDeniedForms.forPlatform(defaultTargetPlatform, isWeb: kIsWeb);

  ComposerPanelId get _panelId => _capabilities.accessPanel ?? _spec.panel;

  @override
  void dispose() {
    _controller.slowMode.removeListener(_onSlowModeState);
    _controller.capabilities.removeListener(_onCapabilities);
    unawaited(_slowModeEdges?.cancel());
    if (_capabilities.isBound) _controller.unbindCapabilities();
    _reveal
      ..removeStatusListener(_onRevealStatus)
      ..dispose();
    _rowProgress.dispose();
    _shake.dispose();
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
      _spec.enabled &&
      action.isTappable &&
      !(action.primary && (_spec.busy || _controller.isSendDisabledBySlowMode));

  bool get _overBudget {
    final limit = _messageLengthLimit;
    return limit != null && widget.controller.length > limit;
  }

  // The primary action is the send: over the budget it is refused, with the
  // counter shaking, and the host's handler is not called. Under an instant
  // motion speed nothing shakes (the refusal is the unsent text).
  //
  // In slow mode a send during the wait is refused first: the text stays
  // and the controller reports the attempt.
  void _activate(ActionDescriptor action) {
    if (action.primary && _controller.refuseEarlySend()) return;
    if (action.primary && _overBudget) {
      final duration = ChromeMotionScope.of(
        context,
      ).durationOf(MotionRole.release);
      if (duration > Duration.zero) {
        _shake
          ..duration = duration
          ..forward(from: 0);
      }
      return;
    }
    action.onTap?.call();
  }

  Widget _button(ActionDescriptor action) {
    if (_deniedButton(action) case final denied?) return denied;
    final button = action.primary && _slowModeActive
        // Redrawn with each tick of the countdown, without the row.
        ? ListenValueBuilder<ComposerSlowModeState>(
            key: ValueKey<String>('slowMode:${action.id}'),
            listenable: _controller.slowMode,
            builder: (context, state) => _slowModeButton(action, state),
          )
        : _face(
            action,
            enabled: _usable(action) && !_controller.isHeldBySlowMode(action),
          );
    final wrap = action.wrap;
    if (wrap == null) return button;
    // The wrapper's slot in the row is keyed apart from the button's own key,
    // so finding the button by its id still finds the button, and a row that
    // reorders keeps each slot's state with its action.
    return Builder(
      key: ValueKey<String>('wrap:${action.id}'),
      builder: (context) => wrap(context, button),
    );
  }

  ComposerButton _face(
    ActionDescriptor action, {
    required bool enabled,
    String? text,
    String? semanticLabel,
    String? semanticHint,
  }) => ComposerButton(
    key: ValueKey<String>(action.id),
    icon: action.icon,
    text: text,
    semanticLabel: semanticLabel ?? action.semanticLabel,
    semanticHint: semanticHint,
    onTap: action.primary && action.onTap != null
        ? () => _activate(action)
        : action.onTap,
    enabled: enabled,
    primary: action.primary,
    primaryStyle: widget.primaryStyle,
    discDiameter: widget.primaryDiameter,
    fill: action.fill,
    onFill: action.onFill,
    iconSize: action.iconSize ?? ComposerMetrics.actionIconSize,
    active: action.active,
  );

  // The send in slow mode. During the wait, where the platform puts the
  // countdown on it, it reads `m:ss` and is announced as not available
  // with the countdown as its hint; a tap is refused and reported. While a
  // message is still sending it is dimmed (a tap reported) or disabled, as
  // the platform draws it.
  Widget _slowModeButton(ActionDescriptor action, ComposerSlowModeState state) {
    final forms = _slowModeForms;
    final countdown =
        state.isCounting &&
            forms.countdown == ComposerCountdownPlacement.primaryAction
        ? _countdownText(state)
        : null;
    final disabled =
        state.pending && forms.pendingSend == ComposerPendingSend.disabled;
    final face = _face(
      action,
      enabled: _usable(action) && !disabled,
      text: countdown,
      semanticLabel: switch (countdown) {
        null => null,
        _ => ChromeStringsScope.composerOf(
          context,
        ).unavailableAction(action.semanticLabel),
      },
      semanticHint: countdown,
    );
    if (!state.pending || disabled) return face;
    return Opacity(opacity: _deniedForms.dimmedOpacity, child: face);
  }

  // The denied form of an action whose capability the chat denies, or null
  // for its own form. Enabled and focusable for assistive technology:
  // activating it reports the attempt, which is how the user learns why.
  Widget? _deniedButton(ActionDescriptor action) {
    final capability = action.capability;
    if (capability == null) return null;
    final denial = _controller.actionDenial(capability);
    if (denial == null) return null;
    final strings = ChromeStringsScope.composerOf(context);
    final button = Opacity(
      key: ValueKey<String>('denied:${action.id}'),
      opacity: _deniedForms.dimmedOpacity,
      child: ComposerButton(
        key: ValueKey<String>(action.id),
        icon: action.icon,
        semanticLabel: strings.unavailableAction(action.semanticLabel),
        semanticHint: denial.text,
        onTap: () => _controller.reportDenied(capability, denial.reason),
        enabled: _spec.enabled,
        primary: action.primary,
        primaryStyle: widget.primaryStyle,
        discDiameter: widget.primaryDiameter,
        fill: action.fill,
        onFill: action.onFill,
        iconSize: action.iconSize ?? ComposerMetrics.actionIconSize,
      ),
    );
    final wrap = action.wrap;
    if (wrap == null) return button;
    return Builder(
      key: ValueKey<String>('wrap:${action.id}'),
      builder: (context) => wrap(context, button),
    );
  }

  Widget _panel(BuildContext context) {
    final panel = _panelId;
    final capabilities = _capabilities;
    if (panel == ComposerPanelId.text) {
      final autofocus = _autofocusPending;
      _autofocusPending = false;
      final textDenial = capabilities.textDenial;
      final locked = textDenial != null;
      final field = ComposerField(
        controller: _controller,
        enabled: _spec.enabled && !locked,
        autofocus: autofocus,
        formatting: _spec.formatting,
        linkPrompt: _spec.linkPrompt,
        backPriority: _spec.backPriority,
        spellChecker: _spec.spellChecker,
        menuPolicy: widget.menuPolicy,
        onTap: widget.onFieldTap,
        onPointerDown: widget.onFieldPointerDown,
        onPointerEnd: widget.onFieldPointerEnd,
        startInset: _spec.visibleActions(ActionPlacement.leading).isEmpty
            ? widget.fieldStartInset
            : 0,
        hintFontSize: widget.hintFontSize,
        hintText:
            capabilities.lockedHint ??
            _countdownHint(_slowState) ??
            widget.hintText,
        hintMaxLines: widget.hintMaxLines,
        hintIcon: locked && _deniedForms.lockedFieldGlyph
            ? ChromeIconId.lock
            : null,
      );
      return switch (textDenial) {
        null => field,
        final DenialReason reason => _lockedField(
          field,
          reason,
          capabilities.lockedHint,
        ),
      };
    }
    final built =
        widget.panelResolver?.call(context, panel) ??
        switch (capabilities.accessPanel) {
          null => null,
          _ => ComposerAccessPanel(
            text: capabilities.accessText,
            action: widget.accessAction?.call(capabilities.writeAccess),
          ),
        };
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

  // The locked field: the disabled field takes no pointer, so a tap on it,
  // or activating it from the keyboard or assistive technology, reports
  // the attempt. It stays focusable and is announced as not available,
  // with the host's text as its hint, like a dimmed action.
  Widget _lockedField(Widget field, DenialReason reason, String? hint) {
    void report() =>
        _controller.reportDenied(CapabilityAction.sendText, reason);
    final strings = ChromeStringsScope.composerOf(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      focusable: true,
      label: strings.unavailableAction(widget.hintText ?? strings.messageHint),
      hint: hint,
      onTap: report,
      child: FocusableActionDetector(
        // Its own keys: the composer's shortcuts map Enter to the send.
        shortcuts: _lockedFieldKeys,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              report();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: const ValueKey<String>('composer-locked-field'),
          behavior: HitTestBehavior.opaque,
          onTap: report,
          child: field,
        ),
      ),
    );
  }

  static const _lockedFieldKeys = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  // The row's inset from the island's sides.
  static const double _rowInset = 2;

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
            key: ValueKey<String>(_panelId.value),
            child: _panel(context),
          ),
        ),
        for (final action in _spec.visibleActions(ActionPlacement.trailing))
          _button(action),
      ],
    );

    return HeightReporter(
      onHeight: (height) => widget.controller.reportExtent(height - safeBottom),
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
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GlassSurface(
                        key: widget.islandKey,
                        material: GlassMaterial.island,
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
                                  padding:
                                      const EdgeInsetsDirectional.symmetric(
                                        horizontal: _rowInset,
                                      ),
                                  child: row,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Over the primary button, at the row's end: drawn
                      // above the island, taking none of its room.
                      if (_messageLengthLimit case final limit?)
                        PositionedDirectional(
                          end: _rowInset,
                          bottom: ComposerMetrics.actionSize,
                          width: ComposerLengthCounter.width,
                          height: ComposerLengthCounter.height,
                          child: ComposerLengthCounter(
                            controller: widget.controller,
                            limit: limit,
                            visibleFromLength: _spec.messageLengthCounterFrom,
                            shake: _shake,
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
  // let it through. So must a caret in a list item, where Enter is the list's
  // (a new item, or out of the list), as in any editor that has lists.
  @override
  bool isEnabled(SubmitComposerIntent intent) {
    final text = _state.widget.controller.text;
    return !text.isComposing && !text.isInListItem && _target != null;
  }

  @override
  Object? invoke(SubmitComposerIntent intent) {
    if (_target case final target?) _state._activate(target);
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
