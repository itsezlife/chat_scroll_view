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

  /// Add more media: a camera's viewer goes back to the camera for another
  /// shot.
  static const ChromeIconId addPhoto = ChromeIconId('addPhoto');

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

  /// Locked: an input the user may not use here.
  static const ChromeIconId lock = ChromeIconId('lock');

  /// Move up: what a choice of position moves above the text.
  static const ChromeIconId moveUp = ChromeIconId('moveUp');

  /// Move down: what a choice of position moves below the text.
  static const ChromeIconId moveDown = ChromeIconId('moveDown');

  /// Enlarge, such as a preview's media.
  static const ChromeIconId enlarge = ChromeIconId('enlarge');

  /// Shrink, such as a preview's media.
  static const ChromeIconId shrink = ChromeIconId('shrink');

  /// Delete or remove.
  static const ChromeIconId delete = ChromeIconId('delete');

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
    addPhoto,
    search,
    close,
    backspace,
    reply,
    edit,
    lock,
    moveUp,
    moveDown,
    enlarge,
    shrink,
    delete,
  ];
}
