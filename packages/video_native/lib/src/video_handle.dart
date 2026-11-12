/// An opaque reference to an open video.
///
/// An integer, not a pointer, so a fake and a later web binding can issue
/// them too.
extension type const VideoHandle(int id) {}
