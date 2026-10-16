/// A **chrome icon**: the semantic name of an icon, resolved to a painter by a
/// `ChromeIconRegistry`.
///
/// Composer actions and panel tabs refer to icons by id, never by glyph, so a
/// host can restyle one id everywhere with a single registration. The stock
/// ids below are what the chrome itself uses; a host adds its own by
/// registering a painter for any other string.
extension type const ChromeIconId._(String value) {
  /// A semantic icon id. Must not be empty.
  const ChromeIconId(this.value)
    : assert(value != '', 'an icon id must not be empty');

  /// The emoji page, or the emoji-panel toggle at rest.
  static const ChromeIconId emoji = ChromeIconId('emoji');

  /// The keyboard: the toggle that leaves the panel for the keyboard.
  static const ChromeIconId keyboard = ChromeIconId('keyboard');

  /// The stickers page.
  static const ChromeIconId stickers = ChromeIconId('stickers');

  /// The animated-image page.
  static const ChromeIconId gif = ChromeIconId('gif');

  /// Send.
  static const ChromeIconId send = ChromeIconId('send');

  /// Confirm, such as saving an edit.
  static const ChromeIconId confirm = ChromeIconId('confirm');

  /// Record a voice message.
  static const ChromeIconId voice = ChromeIconId('voice');

  /// Attach.
  static const ChromeIconId attach = ChromeIconId('attach');

  /// Search.
  static const ChromeIconId search = ChromeIconId('search');

  /// Close or dismiss.
  static const ChromeIconId close = ChromeIconId('close');

  /// Delete the previous character.
  static const ChromeIconId backspace = ChromeIconId('backspace');

  /// Reply.
  static const ChromeIconId reply = ChromeIconId('reply');

  /// Edit.
  static const ChromeIconId edit = ChromeIconId('edit');

  /// Every id the stock registry paints.
  static const List<ChromeIconId> stockIds = [
    emoji,
    keyboard,
    stickers,
    gif,
    send,
    confirm,
    voice,
    attach,
    search,
    close,
    backspace,
    reply,
    edit,
  ];
}
