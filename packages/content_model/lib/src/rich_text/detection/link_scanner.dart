import 'package:content_model/src/rich_text/detection/code_point.dart';
import 'package:content_model/src/rich_text/detection/detection_policy.dart';
import 'package:content_model/src/rich_text/detection/iana_top_level_domains.dart';
import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';

/// Finds URLs and emails in plain text as link candidates.
///
/// Internal to [EntityDetection]: it reports candidates, and the caller
/// decides which survive (exclusions, overlaps, the budget).
///
/// The shape is Telegram Android's `LinkifyPort.WEB_URL`, written as a scanner
/// instead of a regular expression so the cost stays linear whatever the text
/// holds (a backtracking engine is quadratic on a long run of dotted labels):
///
/// - an optional scheme from the policy, then any host; without a scheme the
///   host must end in a top-level domain from [IanaTopLevelDomains], in
///   punycode (`xn--...`), or be a dotted IPv4 address;
/// - an optional `:port` and a path or query that starts with `/` or `?`;
/// - trailing punctuation is not part of the URL and a `)` it does not open
///   is not either (desktop `MessageLinksParser`);
/// - a match preceded by `@` is rejected (`sUrlMatchFilter`), and so is a
///   scheme-less one right after `://`, which would otherwise link the host
///   of a URL whose scheme the policy refuses.
///
/// Where this differs from the regular expression, on purpose: a host is one
/// maximal chain of labels, so `a.com.b.c` is not cut back to `a.com`; a path
/// stops at punctuation of the Latin-1, CJK and full-width blocks (`»`, `，`)
/// and never takes symbols or emoji, where the expression's character class
/// swallows both; the closing slash of `a.com/x/` stays.
///
/// An email is a local part of 1 to 64 characters of `[A-Za-z0-9._%+-]` that
/// starts and ends with a letter, digit or `_`, an `@`, and a host that ends
/// in a listed top-level domain. It is a `mailto:` link.
abstract final class LinkScanner {
  /// The candidates in [text] under [policy], in text order.
  static List<Entity> scan(String text, DetectionPolicy policy) =>
      _Scan(text, policy).run();
}

class _Scan {
  _Scan(this.text, this.policy)
    : schemes = policy.usableSchemes,
      implicitScheme = policy.implicitScheme;

  final String text;
  final DetectionPolicy policy;
  final List<String> schemes;
  final String? implicitScheme;
  final List<Entity> found = [];

  int get _length => text.length;

  List<Entity> run() {
    var i = 0;
    while (i < _length) {
      final unit = text.codeUnitAt(i);
      if (_isLocalStart(unit) && (i == 0 || !_isLocal(_unit(i - 1)))) {
        if (_email(i) case final end?) {
          i = end;
          continue;
        }
      }
      i = _isAsciiPunctuation(unit) || !_atBoundary(i) ? i + 1 : _url(i);
    }
    return found;
  }

  // --- Email ---

  /// Adds the email starting at [start] and returns where it ends, or null.
  int? _email(int start) {
    var at = start;
    while (at < _length &&
        at - start <= _maxLocalLength &&
        _isLocal(_unit(at))) {
      at++;
    }
    if (at >= _length || _unit(at) != _atSign || at - start > _maxLocalLength) {
      return null;
    }
    if (!_isLocalEdge(_unit(at - 1))) return null;
    final host = _chain(at + 1);
    if (host == null || host.labels < 2 || !_isTopLevel(host)) return null;
    found.add(
      Entity(
        start,
        host.end - start,
        EntityKind.link('mailto:${text.substring(start, host.end)}'),
      ),
    );
    return host.end;
  }

  // --- URL ---

  /// Scans for a URL at [start], adds it when it is accepted, and returns
  /// where scanning goes on.
  int _url(int start) {
    final schemeLength = _schemeLength(start);
    final int hostEnd;
    if (schemeLength > 0) {
      final host = _chain(_afterUserInfo(start + schemeLength));
      if (host == null) return start + 1;
      hostEnd = host.end;
    } else {
      final host = _chain(start);
      if (host == null) return start + 1;
      if (host.labels < 2 || !(_isTopLevel(host) || _isIpv4(start, host.end))) {
        // Every later start in this chain ends in the same label, so only the
        // last one can still begin a URL (its scheme); skipping to it keeps
        // the scan linear.
        return host.labels > 1 ? host.lastStart : start + 1;
      }
      hostEnd = host.end;
    }
    final end = _trimmed(start, hostEnd, _pathEnd(_portEnd(hostEnd)));
    if (_isRejected(start, schemeLength > 0)) return end;
    final target = schemeLength > 0
        ? text.substring(start, end)
        : implicitScheme == null
        ? null
        : '$implicitScheme://${text.substring(start, end)}';
    if (target != null) {
      found.add(Entity(start, end - start, EntityKind.link(target)));
    }
    return end;
  }

  /// The length of the `scheme://` at [start], or 0.
  int _schemeLength(int start) {
    for (final scheme in schemes) {
      final end = start + scheme.length;
      if (end + 3 > _length || !_matchesAt(scheme, start)) continue;
      if (text.startsWith('://', end)) return scheme.length + 3;
    }
    return 0;
  }

  bool _matchesAt(String lowercase, int start) {
    for (var k = 0; k < lowercase.length; k++) {
      var unit = _unit(start + k);
      if (unit >= 0x41 && unit <= 0x5A) unit += 0x20;
      if (unit != lowercase.codeUnitAt(k)) return false;
    }
    return true;
  }

  /// [hostStart], or the index after a `user:password@` that begins there.
  int _afterUserInfo(int hostStart) {
    var colon = -1;
    for (
      var k = hostStart;
      k < _length && k - hostStart <= _maxUserInfoLength;
      k++
    ) {
      final unit = _unit(k);
      if (unit == _atSign) {
        final hasUser = k > hostStart && colon != hostStart;
        final hasPassword = colon < 0 || colon < k - 1;
        return hasUser && hasPassword ? k + 1 : hostStart;
      }
      if (unit == _colon && colon < 0) {
        colon = k;
      } else if (!_isUserInfo(unit)) {
        break;
      }
    }
    return hostStart;
  }

  /// A match preceded by `@`, and a scheme-less one right after `://`.
  bool _isRejected(int start, bool hasScheme) =>
      (start > 0 && _unit(start - 1) == _atSign) ||
      (!hasScheme && start >= 3 && text.startsWith('://', start - 3));

  /// Where `:port` ends, or [hostEnd] when there is none.
  int _portEnd(int hostEnd) {
    if (hostEnd >= _length || _unit(hostEnd) != _colon) return hostEnd;
    var k = hostEnd + 1;
    while (k < _length && _isDigit(_unit(k))) {
      k++;
    }
    final digits = k - hostEnd - 1;
    if (digits < 1 || digits > 5) return hostEnd;
    if (k < _length && _isWordUnit(_unit(k))) return hostEnd;
    return k;
  }

  /// Where the path or query starting at [from] ends; [from] if none starts.
  int _pathEnd(int from) {
    if (from >= _length) return from;
    final first = _unit(from);
    if (first != _slash && first != _question) return from;
    var k = from;
    while (k < _length) {
      final unit = _unit(k);
      if (unit == _percent) {
        if (k + 2 < _length && _isHex(_unit(k + 1)) && _isHex(_unit(k + 2))) {
          k += 3;
          continue;
        }
        break;
      }
      if (unit < 0x80) {
        if (!_isPathAscii(unit)) break;
        k++;
      } else {
        final cp = CodePoint.at(text, k);
        if (!_isLabelCodePoint(cp)) break;
        k += CodePoint.width(cp);
      }
    }
    return k;
  }

  /// [end] without the punctuation and unopened `)` a URL does not end in,
  /// but never cutting into the host and port before [floor].
  ///
  /// Only `)` is counted: no other bracket is a path character.
  int _trimmed(int start, int floor, int end) {
    var opened = 0;
    var closed = 0;
    for (var k = start; k < end; k++) {
      final unit = _unit(k);
      if (unit == _openParen) opened++;
      if (unit == _closeParen) closed++;
    }
    var result = end;
    while (result > floor) {
      final unit = _unit(result - 1);
      if (_isTrailingPunctuation(unit)) {
        result--;
      } else if (unit == _closeParen && closed > opened) {
        closed--;
        result--;
      } else {
        break;
      }
    }
    return result;
  }

  // --- Hosts ---

  /// The dotted chain of labels from [start], or null when none starts there.
  ///
  /// It ends before the first label that is not valid, or before a dot that
  /// no label follows, so `a.com.` is the chain `a.com`.
  _Chain? _chain(int start) {
    var labels = 0;
    var lastStart = start;
    var end = start;
    var from = start;
    while (true) {
      final labelEnd = _labelEnd(from);
      if (labelEnd < 0) break;
      labels++;
      lastStart = from;
      end = labelEnd;
      if (labelEnd < _length && _unit(labelEnd) == _dot) {
        from = labelEnd + 1;
      } else {
        break;
      }
    }
    return labels == 0 ? null : _Chain(end, lastStart, labels);
  }

  /// Where the label starting at [start] ends, or -1 when it is not one: it
  /// starts and ends with a letter or digit, holds `_` and `-` inside, is at
  /// most 63 characters, and is not followed by `_`.
  int _labelEnd(int start) {
    var k = start;
    var end = -1;
    var characters = 0;
    while (k < _length) {
      final unit = _unit(k);
      final int width;
      final bool edge;
      if (unit < 0x80) {
        width = 1;
        edge = _isAsciiAlnum(unit);
        if (!edge && unit != _underscore && unit != _hyphen) break;
      } else {
        final cp = CodePoint.at(text, k);
        if (!_isLabelCodePoint(cp)) break;
        width = CodePoint.width(cp);
        edge = true;
      }
      if (characters == 0 && !edge) return -1;
      characters++;
      if (characters > _maxLabelLength) return -1;
      k += width;
      if (edge) end = k;
    }
    if (end < 0) return -1;
    return end < _length && _unit(end) == _underscore ? -1 : end;
  }

  bool _isTopLevel(_Chain host) {
    final label = text.substring(host.lastStart, host.end);
    if (label.length > 4 && label.toLowerCase().startsWith('xn--')) {
      return _isPunycodeTail(label);
    }
    return IanaTopLevelDomains.contains(label);
  }

  /// Android's `xn\-\-[\w\-]{0,58}\w`: the rest of a punycode label.
  static bool _isPunycodeTail(String label) {
    if (label.length > 63) return false;
    for (var k = 4; k < label.length; k++) {
      final unit = label.codeUnitAt(k);
      if (!_isAsciiAlnum(unit) && unit != _underscore && unit != _hyphen) {
        return false;
      }
    }
    return label.codeUnitAt(label.length - 1) != _hyphen;
  }

  /// Whether [start] to [end] is four dotted decimal octets, the first not 0.
  bool _isIpv4(int start, int end) {
    var octets = 0;
    var k = start;
    while (k < end) {
      var digits = 0;
      var value = 0;
      final first = k;
      while (k < end && _isDigit(_unit(k))) {
        value = value * 10 + (_unit(k) - 0x30);
        digits++;
        k++;
        if (digits > 3) return false;
      }
      if (digits == 0 || value > 255) return false;
      if (digits > 1 && _unit(first) == 0x30) return false;
      if (octets == 0 && value == 0) return false;
      octets++;
      if (k < end) {
        if (_unit(k) != _dot) return false;
        k++;
      }
    }
    return octets == 4;
  }

  // --- Character classes ---

  bool _atBoundary(int i) => i == 0 || !_isWordUnit(_unit(i - 1));

  int _unit(int index) => text.codeUnitAt(index);

  static const int _maxLocalLength = 64;
  static const int _maxUserInfoLength = 90;
  static const int _maxLabelLength = 63;
  static const int _atSign = 0x40;
  static const int _colon = 0x3A;
  static const int _dot = 0x2E;
  static const int _slash = 0x2F;
  static const int _question = 0x3F;
  static const int _percent = 0x25;
  static const int _underscore = 0x5F;
  static const int _hyphen = 0x2D;
  static const int _openParen = 0x28;
  static const int _closeParen = 0x29;

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  static bool _isAsciiAlnum(int unit) =>
      _isDigit(unit) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);

  static bool _isHex(int unit) =>
      _isDigit(unit) ||
      (unit >= 0x41 && unit <= 0x46) ||
      (unit >= 0x61 && unit <= 0x66);

  /// ASCII word characters: where a URL may not start in the middle of.
  static bool _isWordUnit(int unit) =>
      _isAsciiAlnum(unit) || unit == _underscore;

  static bool _isAsciiPunctuation(int unit) =>
      unit < 0x80 && !_isAsciiAlnum(unit);

  static bool _isLocal(int unit) =>
      _isAsciiAlnum(unit) ||
      unit == _underscore ||
      unit == _dot ||
      unit == _percent ||
      unit == 0x2B ||
      unit == _hyphen;

  static bool _isLocalStart(int unit) => _isLocalEdge(unit);

  static bool _isLocalEdge(int unit) =>
      _isAsciiAlnum(unit) || unit == _underscore;

  /// What may sit in `user:password` before an `@`.
  static bool _isUserInfo(int unit) =>
      _isAsciiAlnum(unit) || _userInfoPunctuation.contains(unit);

  static final Set<int> _userInfoPunctuation = r"._~%!$'()*+-".codeUnits
      .toSet();

  /// The ASCII characters of a path or query besides letters and digits.
  static bool _isPathAscii(int unit) =>
      _isAsciiAlnum(unit) || _pathPunctuation.contains(unit);

  static final Set<int> _pathPunctuation = r";/?:@&=#~-.+!*'(),_$".codeUnits
      .toSet();

  /// The "almost link end" characters (desktop `IsAlmostLinkEnd`) and the
  /// quotes that wrap a URL.
  static bool _isTrailingPunctuation(int unit) =>
      unit == _dot ||
      unit == 0x2C ||
      unit == _colon ||
      unit == 0x3B ||
      unit == 0x21 ||
      unit == _question ||
      unit == 0x27 ||
      unit == 0x22;

  /// Letters and digits of every script, as a host label or a path takes
  /// them (Android's `UCS_CHAR`), minus the punctuation, symbol and emoji
  /// blocks that class lets through.
  static bool _isLabelCodePoint(int cp) {
    if (cp < 0x80) return _isAsciiAlnum(cp);
    if (cp < 0xC0) return false; // controls, Latin-1 punctuation and symbols
    if (cp == 0xD7 || cp == 0xF7) return false;
    if (cp >= 0x2000 && cp <= 0x20CF) return false; // punctuation, scripts
    if (cp >= 0x2190 && cp <= 0x2BFF) return false; // arrows to dingbats
    if (cp >= 0x2E00 && cp <= 0x2E7F) return false;
    if (cp >= 0x3000 && cp <= 0x303F) return false; // CJK punctuation
    if (cp >= 0xD800 && cp <= 0xDFFF) return false; // a lone surrogate
    if (cp >= 0xE000 && cp <= 0xF8FF) return false; // private use
    if (cp >= 0xFDD0 && cp <= 0xFDEF) return false;
    if (cp >= 0xFE00 && cp <= 0xFE6F) return false; // variation, small forms
    if (cp >= 0xFF00 && cp <= 0xFF0F) return false; // full-width punctuation
    if (cp >= 0xFF1A && cp <= 0xFF20) return false;
    if (cp >= 0xFF3B && cp <= 0xFF40) return false;
    if (cp >= 0xFF5B && cp <= 0xFF65) return false;
    if (cp >= 0xFFF0 && cp <= 0xFFFF) return false;
    if (cp >= 0x10000 && cp < 0x20000) return false; // emoji and symbols
    return cp <= 0xEFFFD;
  }
}

/// A dotted chain of host labels: where it [end]s, where its last label
/// starts, and how many [labels] it has.
final class _Chain {
  const _Chain(this.end, this.lastStart, this.labels);

  final int end;
  final int lastStart;
  final int labels;
}
