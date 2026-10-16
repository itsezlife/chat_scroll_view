/// What a page tells the glyph bake about the surface it draws on.
///
/// The narrow seam between a page and whatever bakes glyphs for it (the glyph
/// atlas): the viewport names no atlas, so the page forwards the catalogue's
/// activity through this port. A host that bakes nothing passes no port.
///
/// ## Motion is a union
///
/// Several surfaces can share one baker, so [reportScrolling] names its
/// [reporter] and the baker treats motion as the union over reporters: one
/// surface that settles does not resume baking under another that still
/// moves. [reporter] is any object that is the same for every report of one
/// surface.
abstract interface class BakeActivityPort {
  /// Tells the baker whether the surface [reporter] is moving.
  ///
  /// Reported `false` again when it settles and when the surface goes away.
  void reportScrolling({required Object reporter, required bool scrolling});

  /// Says which glyphs are on screen, most important first, so the baker works
  /// on the pages holding them before the others. Called when scrolling
  /// settles.
  void prioritise(List<String> glyphs);
}
