/// Whether focusing the field may bring up the platform's on-screen keyboard.
enum SoftKeyboardMode {
  /// The platform decides: focus shows the on-screen keyboard where there is
  /// one.
  auto,

  /// Focus and the caret work, but the on-screen keyboard stays down. A host
  /// sets this while another surface (a panel) stands in for the keyboard.
  suppressed,
}
