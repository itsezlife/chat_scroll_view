/// The CLDR cardinal plural category of an integer in Russian, which picks
/// the form of a counted noun.
///
/// [one] for 1, 21, 31, ... (not 11); [few] for 2-4, 22-24, ... (not 12-14);
/// [many] otherwise, zero included. Fractions are not covered: the demo
/// counts whole things.
enum RussianPlural {
  /// 1, 21, 31, ...: «1 стикер».
  one,

  /// 2-4, 22-24, ...: «2 стикера».
  few,

  /// Everything else, zero included: «5 стикеров».
  many;

  /// The category of [n].
  static RussianPlural of(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }

  /// The form of [n]'s noun among [one], [few] and [many].
  static String wordOf(int n, String one, String few, String many) =>
      switch (of(n)) {
        RussianPlural.one => one,
        RussianPlural.few => few,
        RussianPlural.many => many,
      };
}
