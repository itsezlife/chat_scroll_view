/// The syntax facts the markdown encoder and decoder agree on.
///
/// Internal: not exported from any library.
library;

/// The scheme a mention's link target uses; see ADR 017.
const String mentionScheme = 'mention:';

/// Whether [unit] is an ASCII punctuation code unit, the characters a
/// backslash can escape.
bool isAsciiPunctuation(int unit) =>
    (unit >= 0x21 && unit <= 0x2F) ||
    (unit >= 0x3A && unit <= 0x40) ||
    (unit >= 0x5B && unit <= 0x60) ||
    (unit >= 0x7B && unit <= 0x7E);

/// Whether [unit] counts as part of a word for the underscore rules: an ASCII
/// letter or digit, or any non-ASCII code unit (letters of other scripts and
/// emoji alike), which is how the viewport's markdown library reads it.
bool isWordUnit(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit >= 0x80;
