/// Where an outgoing message stands, as its media cells show it.
///
/// The host reads it from its outbox (or whatever sends the message) and
/// passes it to the view; an incoming message, or one sent and published,
/// is [none].
enum MediaSendState {
  /// Not an outgoing message on its way: the cells show downloads only.
  none,

  /// Being sent: an item's uploads show on its status control, a cancel
  /// there is the item's cross (`MessageMediaView.onItemCancelled`).
  sending,

  /// The send failed: the cells show no status control; the error badge
  /// and Retry / Delete are the host's chrome and menu.
  failed,
}
