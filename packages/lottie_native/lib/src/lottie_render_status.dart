/// What happened to one `LottieRenderJob`.
enum LottieRenderStatus {
  /// The slot holds the frame.
  ok,

  /// An unknown or disposed handle, a null target or an invalid frame.
  badArgument,

  /// A zero edge, an edge over `LottieRenderJob.maxEdge`, or a stride under
  /// the row width.
  badSize,

  /// The renderer failed on this job, or hit an internal error.
  failed,
}
