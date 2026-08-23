import 'dart:async';
import 'dart:math' as math;

import 'package:chat_chrome/src/debug/chat_chrome_log.dart';
import 'package:chat_chrome/src/inset/keyboard_height_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Which surface owns the bottom inset term.
enum ChatBottomInsetOwner {
  /// Soft keyboard (or idle zero).
  ime,

  /// Custom emoji / sticker / GIF panel.
  panel,
}

/// Single writer for the host `keyboard` bottom-inset term.
///
/// Composer / panel bottom-inset model vs Flutter `keyboard_insets`:
/// - IME open → publish live IME height (record settled peaks only).
/// - Keyboard → emoji → claim slot at current IME height (inset unchanged).
/// - Cold emoji open → occupancy animates 0→target.
/// - Never follow collapsing live IME while the panel owns the slot.
/// - Do **not** auto-dismiss on a one-frame IME spike after hide
///   (`310→0→310` glitch from WindowInsetsAnimation).
final class ChatBottomInsetController extends ChangeNotifier {
  /// Creates an arbiter.
  ChatBottomInsetController({
    required KeyboardHeightStore store,
    double holdEpsilon = 2,
    this.osKeyboardHeight,
  }) : _store = store,
       _holdEpsilon = holdEpsilon;

  final KeyboardHeightStore _store;
  final double _holdEpsilon;

  /// OS persistent keyboard peak (e.g. `KeyboardInsets.keyboardHeight`).
  ///
  /// Native `keyboard_insets` keeps the last measured IME target even while
  /// the keyboard is hidden — use that for emoji-panel sizing, not live
  /// animation frames.
  final double? Function()? osKeyboardHeight;

  ChatBottomInsetOwner _owner = ChatBottomInsetOwner.ime;
  double _imeHeight = 0;
  double _panelTarget = 0;
  double _panelOccupancy = 0;
  double _published = 0;
  double _holdFloor = 0;
  bool _panelDesired = false;
  bool _openedReplacingIme = false;

  /// Keyboard-sized target captured before [expandPanelForSearch].
  double _panelBaseTarget = 0;
  bool _searchExpanded = false;

  /// After [waitForIme] hold releases, ignore one-frame IME=0 dips.
  DateTime? _postHoldStickyUntil;
  double _postHoldFloor = 0;
  var _postHoldSawDescent = false;
  var _postHoldDescentStreak = 0;
  var _holdHitStreak = 0;

  void _clearPostHoldSticky() {
    _postHoldStickyUntil = null;
    _postHoldFloor = 0;
    _postHoldSawDescent = false;
    _postHoldDescentStreak = 0;
  }

  /// Current inset owner.
  ChatBottomInsetOwner get owner => _owner;

  /// Whether the emoji panel should be considered open.
  bool get isPanelOpen => _panelDesired;

  /// Whether [closePanel] is holding the inset floor for IME handoff.
  bool get isHoldingForIme => _holdFloor > _holdEpsilon;

  /// Last live IME height (0 when fully hidden).
  double get imeHeight => _imeHeight;

  /// Whether the soft keyboard currently reports a visible height.
  bool get isImeVisible => _imeHeight > _holdEpsilon;

  /// Whether the last [openPanel] claimed the slot while IME was visible.
  bool get openedReplacingIme => _openedReplacingIme;

  /// Target panel height (store / replace height), independent of animation.
  double get panelTarget => _panelTarget;

  /// Keyboard-sized target before search expand; equals [panelTarget] when not expanded.
  double get panelBaseTarget =>
      _searchExpanded ? _panelBaseTarget : _panelTarget;

  /// Whether [expandPanelForSearch] raised the target above the keyboard size.
  bool get isSearchExpanded => _searchExpanded;

  /// Published bottom inset.
  double get height => _published;

  /// Listenable view of [height].
  late final ValueNotifier<double> heightListenable = ValueNotifier<double>(0);

  /// Preferred panel layout height.
  ///
  /// Prefer the larger of: prefs store, optional OS persistent peak
  /// ([osKeyboardHeight], e.g. `KeyboardInsets.keyboardHeight`), and a sane
  /// default floor.
  double panelTargetHeight({required bool landscape}) {
    final stored = _store.heightFor(landscape: landscape);
    final os = _resolvedOsHeight();
    return math.max(stored, os);
  }

  double _resolvedOsHeight() {
    final raw = osKeyboardHeight?.call();
    if (raw == null || !raw.isFinite) return _store.defaultHeight;
    if (raw < KeyboardHeightStore.minSaneKeyboardHeight) {
      return _store.defaultHeight;
    }
    return raw;
  }

  /// Claims the bottom slot for the emoji panel.
  ///
  /// Call **before** hiding the IME when replacing the keyboard.
  double openPanel({required bool landscape}) {
    final stored = _store.heightFor(landscape: landscape);
    final os = _resolvedOsHeight();
    _openedReplacingIme = isImeVisible;
    if (_openedReplacingIme) {
      _panelTarget = math.max(math.max(stored, os), _imeHeight);
    } else {
      _panelTarget = math.max(stored, os);
    }
    if (_panelTarget < KeyboardHeightStore.minSaneKeyboardHeight) {
      _panelTarget = _store.defaultHeight;
    }
    _panelDesired = true;
    _owner = ChatBottomInsetOwner.panel;
    _holdFloor = _panelTarget;
    _clearPostHoldSticky();
    _holdHitStreak = 0;

    if (_openedReplacingIme) {
      _panelOccupancy = _panelTarget;
      chatChromeLog(
        'openPanel REPLACE target=$_panelTarget ime=$_imeHeight '
        'stored=$stored os=$os',
      );
      _setPublished(_panelTarget, force: true);
    } else {
      _panelOccupancy = 0;
      chatChromeLog(
        'openPanel COLD target=$_panelTarget stored=$stored os=$os '
        '(publish 0, animate occupancy)',
      );
      _setPublished(0, force: true);
    }
    _panelBaseTarget = _panelTarget;
    _searchExpanded = false;
    return _panelTarget;
  }

  /// Raises [panelTarget] for emoji search (`min(availableMax, base + 175)`).
  ///
  /// Does not animate occupancy — the panel shell animates [setPanelOccupancy]
  /// toward the new target. No-op when the panel is not open.
  double expandPanelForSearch({required double availableMax}) {
    if (!_panelDesired) return _panelTarget;
    if (!_searchExpanded) {
      _panelBaseTarget = _panelTarget;
    }
    final capped = availableMax.isFinite && availableMax > 0
        ? availableMax
        : _panelBaseTarget + 175;
    final expanded = math.min(capped, _panelBaseTarget + 175);
    _panelTarget = math.max(_panelBaseTarget, expanded);
    _searchExpanded = true;
    _holdFloor = _panelTarget;
    return _panelTarget;
  }

  /// Restores [panelTarget] to the pre-search keyboard-sized base.
  ///
  /// Call after occupancy has animated down (or immediately when tearing down).
  void collapsePanelFromSearch() {
    if (!_searchExpanded) return;
    final base = _panelBaseTarget > 0 ? _panelBaseTarget : _panelTarget;
    _panelTarget = base;
    _searchExpanded = false;
    _panelBaseTarget = base;
    _holdFloor = _panelTarget;
    if (_panelOccupancy > _panelTarget) {
      _panelOccupancy = _panelTarget;
      _setPublished(_panelTarget, force: true);
    }
  }

  /// Drives panel slot height during cold-open / close animation.
  void setPanelOccupancy(double occupancy) {
    if (!_panelDesired) return;
    final next = occupancy.clamp(0.0, _panelTarget);
    if ((next - _panelOccupancy).abs() < 0.01 &&
        (next - _published).abs() < 0.01) {
      return;
    }
    _panelOccupancy = next;
    _owner = ChatBottomInsetOwner.panel;
    _setPublished(next);
  }

  /// Publishes animated close height while [closePanel] is deferred.
  ///
  /// Unlike [setPanelOccupancy], does not require [_panelDesired] so the slot
  /// can animate down before the panel slot is released.
  /// Always ≥ 0 — never drive chat/composer insets negative.
  void setPanelCloseOccupancy(double height) {
    final next = math.max(0.0, height);
    if ((next - _published).abs() < 0.01) return;
    _panelOccupancy = next;
    _owner = ChatBottomInsetOwner.panel;
    _setPublished(next);
  }

  /// Closes the panel. [waitForIme] keeps the hold floor until IME rises.
  void closePanel({bool waitForIme = false}) {
    final hold = waitForIme && _published > _holdEpsilon
        ? _published
        : (waitForIme && _panelTarget > _holdEpsilon ? _panelTarget : 0.0);
    chatChromeLog(
      'closePanel waitForIme=$waitForIme published=$_published '
      'hold=$hold ime=$_imeHeight',
    );
    _panelDesired = false;
    _openedReplacingIme = false;
    _searchExpanded = false;
    _panelBaseTarget = 0;
    _holdFloor = hold;
    _holdHitStreak = 0;
    _clearPostHoldSticky();
    _owner = ChatBottomInsetOwner.ime;
    _panelTarget = 0;
    _panelOccupancy = 0;
    // Always publish at least the hold — never flash to live IME=0.
    if (_holdFloor > _holdEpsilon) {
      _setPublished(math.max(_imeHeight, _holdFloor), force: true);
    } else {
      _publish();
    }
  }

  /// Live IME height.
  ///
  /// [record] should be false while the OS keyboard is animating so mid-flight
  /// frames do not poison prefs (use `!KeyboardInsets.isAnimating`).
  void onImeHeight(
    double height, {
    required bool landscape,
    bool record = true,
  }) {
    final previous = _imeHeight;
    _imeHeight = height;

    // Never record while panel owns the slot, or while the caller says the
    // OS keyboard is still animating.
    if (record && !_panelDesired && height >= _store.minRecordableHeight) {
      unawaited(_store.record(height, landscape: landscape));
    }

    if (_panelDesired) {
      // Never auto-dismiss on rising IME. Hide-animations from TextInput.hide
      // produce 0-streaks then a 0→peak glitch that looked like "user opened
      // the keyboard" and tore the panel down. Close only via host UI
      // (emoji toggle, back, tap composer).
      if (height > previous + _holdEpsilon &&
          height > _holdEpsilon &&
          height >= _panelTarget - _holdEpsilon) {
        chatChromeLog(
          'onImeHeight rising while panel (ignored) h=$height prev=$previous',
        );
      }
      return;
    }

    _owner = ChatBottomInsetOwner.ime;

    // waitForIme hold: never publish below the floor. Clear only after the
    // keyboard has *stayed* at the floor for 2 samples (ignores 0→310→0 glitch).
    if (_holdFloor > _holdEpsilon) {
      if (height >= _holdFloor - _holdEpsilon) {
        _holdHitStreak++;
        if (_holdHitStreak >= 2) {
          chatChromeLog(
            'onImeHeight hold released (ime settled at floor) h=$height '
            'floor=$_holdFloor',
          );
          _postHoldFloor = _holdFloor;
          _postHoldStickyUntil = DateTime.now().add(
            const Duration(milliseconds: 450),
          );
          _postHoldSawDescent = false;
          _postHoldDescentStreak = 0;
          // Never dip below the floor on release — IME often reports
          // floor−ε (e.g. 309.33 vs 310.4) for a few frames → 1dp jump.
          final settled = math.max(height, _holdFloor);
          _holdFloor = 0;
          _holdHitStreak = 0;
          _setPublished(settled, force: true);
          return;
        }
      } else {
        _holdHitStreak = 0;
      }
      final held = math.max(height, _holdFloor);
      if ((held - _published).abs() > 1) {
        chatChromeLog(
          'onImeHeight HOLD max(ime=$height, floor=$_holdFloor)=$held',
        );
      }
      _setPublished(held);
      return;
    }

    // Post-release sticky: ignore brief IME=0 glitch at the peak (310→0→310).
    // Do **not** restore the floor after a real descent (emoji handoff → IME hide).
    if (_postHoldStickyUntil != null) {
      if (DateTime.now().isBefore(_postHoldStickyUntil!) &&
          _postHoldFloor > _holdEpsilon) {
        // Partial descent (above zero, below floor) for 2+ frames → real hide.
        if (height < _postHoldFloor - _holdEpsilon && height > _holdEpsilon) {
          _postHoldDescentStreak++;
          if (_postHoldDescentStreak >= 2) {
            _postHoldSawDescent = true;
          }
        } else if (height > _holdEpsilon) {
          _postHoldDescentStreak = 0;
        }
        if (height <= _holdEpsilon) {
          if (!_postHoldSawDescent) {
            chatChromeLog(
              'onImeHeight post-hold sticky ignore zero glitch '
              'floor=$_postHoldFloor',
            );
            _setPublished(_postHoldFloor);
            return;
          }
          chatChromeLog(
            'onImeHeight post-hold sticky cleared (zero after descent) '
            'h=$height floor=$_postHoldFloor',
          );
          _clearPostHoldSticky();
        } else if (height >= _postHoldFloor - _holdEpsilon) {
          _setPublished(math.max(height, _postHoldFloor));
          return;
        }
      } else {
        _clearPostHoldSticky();
      }
    }

    if ((height - _published).abs() > 1) {
      chatChromeLog('onImeHeight publish ime=$height (was $_published)');
    }
    _publish();
  }

  void _publish() {
    final next = switch (_owner) {
      ChatBottomInsetOwner.panel => _panelOccupancy,
      ChatBottomInsetOwner.ime =>
        _holdFloor > _holdEpsilon && _imeHeight + _holdEpsilon < _holdFloor
            ? _holdFloor
            : _imeHeight,
    };
    _setPublished(next);
  }

  void _setPublished(double next, {bool force = false}) {
    if (!force && (next - _published).abs() < 0.01) return;
    _published = next;
    void flush() {
      heightListenable.value = _published;
      notifyListeners();
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      flush();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => flush());
    }
  }

  @override
  void dispose() {
    heightListenable.dispose();
    super.dispose();
  }
}
