/// Discriminator for photo vs video layout inputs.
///
/// Geometry is identical for both variants: [computeSingleMediaSize] and
/// [GroupedMessages.calculate] share one aspect → box path. Hosts still pass
/// [kind] so a later chrome layer (play affordance, duration) can read the
/// same member model without inventing a parallel aspect type.
enum MediaKind {
  /// Still image — same layout box as [video] for a given aspect.
  photo,

  /// Motion media — same layout box as [photo]; play/duration chrome is out
  /// of this package’s ownership.
  video,
}
