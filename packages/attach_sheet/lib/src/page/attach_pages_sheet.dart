import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/host/attach_sheet_host.dart';
import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/page/attach_page_scope.dart';
import 'package:attach_sheet/src/page/attach_tab_bar.dart';
import 'package:attach_sheet/src/panel/attach_panel.dart';
import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:attach_sheet/src/policy/attach_tab_bar_style.dart';
import 'package:attach_sheet/src/sheet/attach_outcome.dart';
import 'package:attach_sheet/src/sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// The sheet with its pages: the page area as the content, the tab bar (or
/// a host page's main button) as the bottom bar, the shown page's header
/// items as the pinned header.
@internal
class AttachPagesSheet extends StatefulWidget {
  /// A sheet of [pages].
  const AttachPagesSheet({
    required this.policy,
    required this.selection,
    required this.pages,
    required this.host,
    required this.opening,
    required this.onClosed,
    this.initialCaption = RichText.empty,
    this.optionStore,
    super.key,
  });

  /// The composer's text, moved into the caption.
  final RichText initialCaption;

  /// Where the send options are remembered; null for nowhere.
  final SendOptionStore? optionStore;

  /// The sheet's policy.
  final AttachSheetPolicy policy;

  /// The open's selection.
  final AttachSelection selection;

  /// The pages, in tab order.
  final AttachPageRegistry pages;

  /// The sheet's host.
  final AttachSheetHost host;

  /// What the host knew at open.
  final AttachSheetOpening opening;

  /// Called once the sheet has closed.
  final ValueChanged<AttachOutcome> onClosed;

  @override
  State<AttachPagesSheet> createState() => _AttachPagesSheetState();
}

class _AttachPagesSheetState extends State<AttachPagesSheet> {
  late final AttachSendController _$send = AttachSendController(
    selection: widget.selection,
    policy: widget.policy,
    host: widget.host,
    initialCaption: widget.initialCaption,
    store: widget.optionStore,
    onSend: (request) =>
        unawaited(_$model.sheet.close(AttachOutcome.send(request))),
  );

  late final AttachPagesModel _$model = AttachPagesModel(
    policy: widget.policy,
    selection: widget.selection,
    pages: widget.pages,
    send: _$send,
  );

  @override
  void dispose() {
    _$model.dispose();
    _$send.dispose();
    super.dispose();
  }

  /// A cancel hands the caption back to the composer.
  void _closed(AttachOutcome outcome) => widget.onClosed(switch (outcome) {
    AttachOutcome$Cancelled() => AttachOutcome.cancelled(
      _$send.caption.richText,
    ),
    _ => outcome,
  });

  @override
  Widget build(BuildContext context) => AttachSheet(
    policy: widget.policy,
    selection: widget.selection,
    host: widget.host,
    opening: widget.opening,
    onClosed: _closed,
    header: ValueListenableBuilder<Widget?>(
      valueListenable: _$model.header,
      builder: (context, header, _) => header ?? const SizedBox.shrink(),
    ),
    bottomBar: Stack(
      alignment: Alignment.bottomCenter,
      children: [
        AttachTabBar(model: _$model),
        AttachPanelReveal(controller: _$send),
      ],
    ),
    builder: (context, _) => _AttachPageArea(model: _$model),
  );
}

/// The shared state of the pages of one open: which page is shown, each
/// page's scope, and what the shown page asks of the sheet.
@internal
final class AttachPagesModel {
  /// The model of [pages].
  AttachPagesModel({
    required this.policy,
    required this.selection,
    required this.pages,
    required this.send,
  }) : active = ValueNotifier(pages.initial);

  /// The panel's state, shared by every page.
  final AttachSendController send;

  /// The sheet's policy.
  final AttachSheetPolicy policy;

  /// The open's selection.
  final AttachSelection selection;

  /// The pages.
  final AttachPageRegistry pages;

  /// The page shown.
  final ValueNotifier<AttachPageId> active;

  /// The shown page's header items.
  final ValueNotifier<Widget?> header = ValueNotifier(null);

  /// The shown page's main button.
  final ValueNotifier<AttachMainButton?> mainButton = ValueNotifier(null);

  /// Whether the shown page hides the panel.
  final ValueNotifier<bool> panelHidden = ValueNotifier(false);

  /// Whether a switch is running and taps on tabs wait.
  bool switching = false;

  AttachSheetController? _$sheet;
  final Map<AttachPageId, PageSlot> _$slots = {};

  /// The sheet, once the page area is laid out below it.
  AttachSheetController get sheet => _$sheet!;

  /// Binds the model to the sheet above the page area.
  void attach(AttachSheetController sheet) {
    if (identical(_$sheet, sheet)) return;
    _$sheet = sheet;
    _apply();
  }

  /// The scope of page [id], made the first time it is shown.
  PageSlot slotOf(AttachPageId id) =>
      _$slots[id] ??= PageSlot(this, pages[id])
        .._isActive.value = active.value == id;

  /// The pages built so far.
  Iterable<PageSlot> get built => _$slots.values;

  /// A tap on the tab of [id].
  void select(AttachPageId id) {
    if (switching) return;
    final page = pages[id];
    if (policy.tabBar.permissionBadges) {
      if (page.permission case final permission?
          when !permission.granted.value) {
        unawaited(permission.request());
        return;
      }
    }
    if (id == active.value) {
      slotOf(id).scrollToTop();
      unawaited(sheet.expand());
      return;
    }
    active.value = id;
    for (final slot in _$slots.values) {
      slot._isActive.value = slot.page == id;
    }
    slotOf(id);
    _apply();
  }

  /// Pushes the shown page's settings to the sheet and the bars.
  void _apply() {
    final sheet = _$sheet;
    if (sheet == null) return;
    final slot = slotOf(active.value);
    sheet
      ..panEnabled = slot._panEnabled
      ..restTop = slot._topOffset
      ..dismissGuard = slot._dismissGuard;
    header.value = slot._headerItems;
    mainButton.value = slot._mainButton;
    panelHidden.value = slot._panelHidden;
  }

  void _changed(PageSlot slot) {
    if (slot.page == active.value) _apply();
  }

  /// Releases what the pages hold.
  void dispose() {
    for (final slot in _$slots.values) {
      slot.dispose();
    }
    active.dispose();
    header.dispose();
    mainButton.dispose();
    panelHidden.dispose();
  }
}

/// One page's [AttachPageScope]: its settings, its scroll controller and
/// its built content.
@internal
final class PageSlot implements AttachPageScope {
  /// The scope of [definition] in [_model].
  PageSlot(this._model, this.definition)
    : scrollController = _model.sheet.createScrollController();

  final AttachPagesModel _model;

  /// The page.
  final AttachPage definition;

  final ValueNotifier<bool> _isActive = ValueNotifier(false);
  bool _panEnabled = true;
  double? _topOffset;
  Widget? _headerItems;
  Future<bool> Function()? _dismissGuard;
  VoidCallback? _onScrollToTop;
  AttachMainButton? _mainButton;
  bool _panelHidden = false;

  /// The page's content, built once.
  late final Widget content = AttachPageScopeProvider(
    scope: this,
    child: Builder(builder: (context) => definition.builder(context, this)),
  );

  @override
  AttachPageId get page => definition.id;

  @override
  ValueListenable<bool> get isActive => _isActive;

  @override
  final ScrollController scrollController;

  @override
  AttachSendController get panel => _model.send;

  @override
  void requestExpansion() => unawaited(_model.sheet.expand());

  @override
  set panEnabled(bool value) {
    _panEnabled = value;
    _model._changed(this);
  }

  @override
  set topOffset(double? value) {
    _topOffset = value;
    _model._changed(this);
  }

  @override
  set headerItems(Widget? value) {
    _headerItems = value;
    _model._changed(this);
  }

  @override
  set dismissGuard(Future<bool> Function()? value) {
    _dismissGuard = value;
    _model._changed(this);
  }

  @override
  set onScrollToTop(VoidCallback? value) => _onScrollToTop = value;

  @override
  set mainButton(AttachMainButton? value) {
    _mainButton = value;
    _model._changed(this);
  }

  @override
  set panelHidden(bool value) {
    _panelHidden = value;
    _model._changed(this);
  }

  @override
  void finish(Object? payload) =>
      unawaited(_model.sheet.close(AttachOutcome.custom(page, payload)));

  /// Scrolls the page to its top, or runs the page's own handler.
  void scrollToTop() {
    if (_onScrollToTop case final handler?) return handler();
    if (!scrollController.hasClients) return;
    unawaited(
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Releases the controller and listenable.
  void dispose() {
    scrollController.dispose();
    _isActive.dispose();
  }
}

/// The page area: every page built so far, the shown one on stage, and the
/// switch motion between them.
class _AttachPageArea extends StatefulWidget {
  const _AttachPageArea({required this.model});

  final AttachPagesModel model;

  @override
  State<_AttachPageArea> createState() => _AttachPageAreaState();
}

class _AttachPageAreaState extends State<_AttachPageArea>
    with TickerProviderStateMixin {
  late final AnimationController _$out = AnimationController(vsync: this);
  late final AnimationController _$in = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  late final AnimationController _$fadeIn = AnimationController(
    vsync: this,
    value: 1,
  );
  AttachPageId? _leaving;

  AttachPagesModel get _model => widget.model;

  @override
  void initState() {
    super.initState();
    _model.active.addListener(_switched);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model.attach(AttachSheetController.of(context));
  }

  @override
  void dispose() {
    _model.active.removeListener(_switched);
    _$out.dispose();
    _$in.dispose();
    _$fadeIn.dispose();
    super.dispose();
  }

  Future<void> _switched() async {
    final from = _previous;
    _previous = _model.active.value;
    final speed = ChromeMotionScope.of(context).speed;
    if (from == null || speed.isInstant) {
      setState(() {});
      return;
    }
    _model.switching = true;
    setState(() => _leaving = from);
    try {
      switch (_model.policy.tabSwitch) {
        case AttachTabSwitch$Slide(:final out, :final inSpring):
          _$in.value = 0;
          _$fadeIn.value = 0;
          final spec = out.withSpeed(speed);
          _$out.value = 0;
          await _$out
              .animateTo(1, duration: spec.duration, curve: spec.curve)
              .orCancel;
          if (!mounted) return;
          setState(() => _leaving = null);
          _model.switching = false;
          await _$in.animateWith(SpringSimulation(inSpring, 0, 1, 0)).orCancel;
          _$in.value = 1;
        case AttachTabSwitch$CrossFade(:final fade, :final inSpring):
          final spec = fade.withSpeed(speed);
          _$out.value = 0;
          _$in.value = 0;
          _$fadeIn.value = 0;
          unawaited(
            _$in
                .animateWith(SpringSimulation(inSpring, 0, 1, 0))
                .orCancel
                .then((_) => _$in.value = 1, onError: (Object _) {}),
          );
          unawaited(
            _$fadeIn
                .animateTo(1, duration: spec.duration, curve: spec.curve)
                .orCancel
                .then((_) {}, onError: (Object _) {}),
          );
          await _$out
              .animateTo(1, duration: spec.duration, curve: spec.curve)
              .orCancel;
      }
    } on TickerCanceled {
      return;
    } finally {
      _model.switching = false;
    }
    if (mounted) setState(() => _leaving = null);
  }

  AttachPageId? _previous;

  @override
  Widget build(BuildContext context) {
    _previous ??= _model.active.value;
    final active = _model.active.value;
    _model.slotOf(active);
    final slide = switch (_model.policy.tabSwitch) {
      AttachTabSwitch$Slide(:final distance) => distance,
      AttachTabSwitch$CrossFade(:final dip) => dip,
    };
    final slides = switch (_model.policy.tabSwitch) {
      AttachTabSwitch$Slide() => true,
      AttachTabSwitch$CrossFade() => false,
    };
    return Stack(
      children: [
        for (final slot in _model.built)
          Positioned.fill(
            key: ValueKey(slot.page),
            child: _stage(slot, active: active, slide: slide, slides: slides),
          ),
      ],
    );
  }
}

extension on _AttachPageAreaState {
  /// One page on stage: the shown one coming in, the old one going out, the
  /// rest kept offstage with their tickers off. The wrappers are the same
  /// for every role so a page keeps its state as its role changes.
  Widget _stage(
    PageSlot slot, {
    required AttachPageId active,
    required double slide,
    required bool slides,
  }) {
    final shown = slot.page == active;
    final leaving = slot.page == _leaving;
    return Offstage(
      offstage: !shown && !leaving,
      child: TickerMode(
        enabled: shown || leaving,
        child: IgnorePointer(
          ignoring: leaving,
          child: AnimatedBuilder(
            animation: Listenable.merge([_$in, _$fadeIn, _$out]),
            child: slot.content,
            builder: (context, child) {
              final (double opacity, double dy) = shown
                  ? (
                      (slides ? _$in.value : _$fadeIn.value).clamp(0.0, 1.0),
                      slide * (1 - _$in.value),
                    )
                  : (1 - _$out.value, slides ? slide * _$out.value : 0);
              return Opacity(
                opacity: opacity,
                child: Transform.translate(offset: Offset(0, dy), child: child),
              );
            },
          ),
        ),
      ),
    );
  }
}
