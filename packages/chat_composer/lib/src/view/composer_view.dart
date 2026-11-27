import 'dart:ui' show lerpDouble;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/src/capabilities/composer_denied_forms.dart';
import 'package:chat_composer/src/capabilities/composer_slow_mode_forms.dart';
import 'package:chat_composer/src/capabilities/composer_slow_mode_state.dart';
import 'package:chat_composer/src/capabilities/sending_denial.dart';
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
import 'package:content_model/content_model.dart'
    show ChatDiagnostics, ChatEventCategory, ChatEventLevel;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart' show BinaryMessenger;
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
///   as its placeholder (after a lock on Android), a tap reported to the
///   host; the actions stay usable;
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
/// Texts come from, and attempts are reported through, the controller's
/// `capabilityFeedback` (`ComposerController.denialText`, `reportDenied`).
/// Without capabilities the view is what it was before them.
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

  // The write access and sending rights, selected from the capabilities so a slow mode tick does not rebuild the row; null without
  // capabilities.
  listen.ValueListenable<_Gate>? _gateSource;

  // The panel choice last reported as `panelChosen`.
  Map<String, Object>? _reportedPanel;

  _Gate? get _gate => _gateSource?.value;

  // The slow mode group, heard only while capabilities are set.
  listen.ValueListenable<SlowMode>? _slowModeSource;

  // The countdown last heard, to tell a start and an end from a redraw.
  var _slowState = ComposerSlowModeState.free;
  // The limits group of the capabilities, heard only while it is set.
  listen.ValueListenable<ChatLimits>? _limits;

  // The budget in force: the spec's, else the chat's.
  int? get _messageLengthLimit =>
      _spec.messageLengthLimit ?? _limits?.value.messageLength;

  void _bindLimits() {
    _limits?.removeListener(_onLimits);
    _limits = widget.capabilities?.select((c) => c.limits)
      ?..addListener(_onLimits);
  }

  void _onLimits() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _subscribeGate();
    _shownHeader = _spec.header;
    _bindLimits();
    _bindSlowMode();
    widget.controller.slowMode.addListener(_onSlowModeState);
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
  void didUpdateWidget(ComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.capabilities, widget.capabilities)) {
      _bindLimits();
      _gateSource?.removeListener(_onGate);
      _subscribeGate();
      _bindSlowMode();
    } else if (oldWidget.deniedForms != widget.deniedForms) {
      _trackSlowMode();
    }
    _syncHeader();
  }

  // --- Capabilities ---

  void _subscribeGate() {
    _gateSource = widget.capabilities?.select(
      (c) => (writeAccess: c.writeAccess, sending: c.sending),
    )?..addListener(_onGate);
  }

  void _onGate() {
    if (mounted) setState(() {});
  }

  // --- Slow mode ---

  void _bindSlowMode() {
    _slowModeSource?.removeListener(_onSlowModeSource);
    _slowModeSource = widget.capabilities?.select((c) => c.slowMode)
      ?..addListener(_onSlowModeSource);
    if (_slowModeSource == null) widget.controller.untrackSlowMode();
    _trackSlowMode();
    _slowState = widget.controller.slowMode.value;
  }

  void _trackSlowMode() {
    if (_slowModeSource case final source?) {
      widget.controller.trackSlowMode(
        source.value,
        refresh: _slowModeForms.refresh,
      );
    }
  }

  void _onSlowModeSource() {
    if (!mounted) return;
    _trackSlowMode();
    // Slow mode turning on or off swaps the send button's form.
    setState(() {});
  }

  ComposerSlowModeForms get _slowModeForms => _deniedForms.slowMode;

  bool get _slowModeActive => _slowModeSource?.value.isActive ?? false;

  // Rebuilds the row only when what it draws changes: the held send (held
  // actions, the submit key) or, with the countdown in the placeholder, the
  // text it shows. The send button's countdown rebuilds by itself.
  void _onSlowModeState() {
    if (!mounted) return;
    final before = _slowState;
    final next = widget.controller.slowMode.value;
    _slowState = next;
    if (!before.isCounting && next.isCounting) {
      _announce(
        ChromeStringsScope.composerOf(
          context,
        ).slowModeStarted(_countdownText(next)),
      );
    } else if (before.isCounting && !next.isCounting) {
      _announce(ChromeStringsScope.composerOf(context).slowModeEnded);
    }
    if (before.holdsSend != next.holdsSend ||
        _countdownHint(before) != _countdownHint(next)) {
      setState(() {});
    }
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
      _slowModeForms.countdown == ComposerCountdownPlacement.placeholder &&
          state.isCounting
      ? _countdownText(state)
      : null;

  // Whether the primary action takes no tap now: a message still sending,
  // where the platform disables the send for it.
  bool get _sendDisabledBySlowMode =>
      _slowModeActive &&
      widget.controller.slowMode.value.pending &&
      _slowModeForms.pendingSend == ComposerPendingSend.disabled;

  // Whether an action that starts a send is held now, where the platform
  // holds such actions during the wait.
  bool _heldBySlowMode(ActionDescriptor action) =>
      action.heldBySlowMode &&
      _slowModeForms.holdsSendActions &&
      _slowModeActive &&
      _slowState.holdsSend;

  ComposerDeniedForms get _deniedForms =>
      widget.deniedForms ??
      ComposerDeniedForms.forPlatform(defaultTargetPlatform, isWeb: kIsWeb);

  // The write access's panel in place of the spec's, or null when the user
  // may write (and without capabilities).
  ComposerPanelId? get _accessPanel => switch (_gate) {
    final gate? => ComposerPanelId.forWriteAccess(gate.writeAccess),
    null => null,
  };

  ComposerPanelId get _panelId => _accessPanel ?? _spec.panel;

  // Once per change of the choice, not per build: rebuilds of the same row
  // (typing, a header) say nothing new.
  void _reportPanel(ComposerPanelId panel, String builder) {
    final gate = _gate;
    if (gate == null) return;
    final access = gate.writeAccess;
    final choice = <String, Object>{
      'writeAccess': _accessForm(access),
      if (access case WriteAccess$Restricted(:final reason))
        'reason': reason.diagnosticForm,
      if (access case WriteAccess$Custom(:final tag)) 'tag': _clip(tag),
      'panel': _clip(panel.value),
      'builder': builder,
    };
    if (mapEquals(choice, _reportedPanel)) return;
    _reportedPanel = choice;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.capabilities,
      CapabilitiesOp.panelChosen,
      correlation: widget.controller.correlation,
      fields: () => choice,
    );
  }

  static String _accessForm(WriteAccess access) => switch (access) {
    WriteAccess$CanWrite() => 'canWrite',
    WriteAccess$ReadOnly() => 'readOnly',
    WriteAccess$Join() => 'join',
    WriteAccess$RequestToJoin() => 'requestToJoin',
    WriteAccess$Restricted() => 'restricted',
    WriteAccess$Custom() => 'custom',
  };

  // An event string holds at most 64 characters; a host tag or panel id can
  // run longer.
  static String _clip(String value) =>
      value.length <= 64 ? value : value.substring(0, 64);

  @override
  void dispose() {
    widget.controller.slowMode.removeListener(_onSlowModeState);
    _slowModeSource?.removeListener(_onSlowModeSource);
    if (_slowModeSource != null) widget.controller.untrackSlowMode();
    _gateSource?.removeListener(_onGate);
    _limits?.removeListener(_onLimits);
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
      !(action.primary && (_spec.busy || _sendDisabledBySlowMode));

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
    if (action.primary && widget.controller.refuseEarlySend()) return;
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
            listenable: widget.controller.slowMode,
            builder: (context, state) => _slowModeButton(action, state),
          )
        : _face(action, enabled: _usable(action) && !_heldBySlowMode(action));
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
    final gate = _gate;
    if (capability == null || gate == null) return null;
    final reason = sendingDenial(gate.sending, capability);
    if (reason == null) return null;
    final controller = widget.controller;
    final strings = ChromeStringsScope.composerOf(context);
    final button = Opacity(
      key: ValueKey<String>('denied:${action.id}'),
      opacity: _deniedForms.dimmedOpacity,
      child: ComposerButton(
        key: ValueKey<String>(action.id),
        icon: action.icon,
        semanticLabel: strings.unavailableAction(action.semanticLabel),
        semanticHint: controller.denialText(
          capability,
          reason,
          form: 'dimmedAction',
        ),
        onTap: () => controller.reportDenied(capability, reason),
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
    if (panel == ComposerPanelId.text) {
      _reportPanel(panel, 'field');
      final autofocus = _autofocusPending;
      _autofocusPending = false;
      final textDenial = switch (_gate) {
        final gate? => sendingDenial(gate.sending, CapabilityAction.sendText),
        null => null,
      };
      final lockedHint = switch (textDenial) {
        final reason? => widget.controller.denialText(
          CapabilityAction.sendText,
          reason,
          form: 'lockedField',
        ),
        null => null,
      };
      final field = ComposerField(
        controller: widget.controller,
        enabled: _spec.enabled && textDenial == null,
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
        hintText: lockedHint ?? _countdownHint(_slowState) ?? widget.hintText,
        hintMaxLines: widget.hintMaxLines,
        hintIcon: textDenial != null && _deniedForms.lockedFieldGlyph
            ? ChromeIconId.lock
            : null,
      );
      if (textDenial == null) return field;
      // The disabled field takes no pointer; the tap that would have
      // focused it reports the attempt instead.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.controller.reportDenied(
          CapabilityAction.sendText,
          textDenial,
        ),
        child: field,
      );
    }
    final hostBuilt = widget.panelResolver?.call(context, panel);
    final built = switch ((hostBuilt, _gate)) {
      (final host?, _) => host,
      (null, final gate?) when _accessPanel != null => _defaultAccessPanel(
        gate.writeAccess,
      ),
      _ => null,
    };
    _reportPanel(panel, hostBuilt != null ? 'host' : 'default');
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

  Widget _defaultAccessPanel(WriteAccess access) => ComposerAccessPanel(
    text: switch (writeAccessReason(access)) {
      final reason? => widget.controller.denialText(
        CapabilityAction.sendText,
        reason,
        form: 'restrictionBar',
      ),
      null => null,
    },
    action: widget.accessAction?.call(access),
  );

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

/// What the row reads of the chat's capabilities: a record, so a selection
/// of it compares by value.
typedef _Gate = ({WriteAccess writeAccess, SendingCapabilities sending});

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
