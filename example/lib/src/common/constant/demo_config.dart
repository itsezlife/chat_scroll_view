/// Demo Supabase settings from `--dart-define` / `--dart-define-from-file`.
abstract final class DemoConfig {
  /// Supabase URL from `--dart-define`.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  static const String _supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Publishable (preferred) or legacy JWT anon key from `--dart-define-from-file`.
  static String get supabasePublishableKey => _supabasePublishableKey.isNotEmpty
      ? _supabasePublishableKey
      : _supabaseAnonKey;

  /// Demo chat id from `--dart-define`.
  static const int demoChatId = int.fromEnvironment(
    'DEMO_CHAT_ID',
    defaultValue: 1,
  );

  /// The most code points of plain text a message may have: the demo
  /// backend's `message_length_max` (Telegram's default is 4096), from
  /// `--dart-define=MESSAGE_LENGTH_MAX`.
  ///
  /// The unit is the plain text, not the markdown body: delimiters and
  /// formatting cost nothing, and nothing is truncated to fit. The composer
  /// shows what remains and refuses a send over it.
  static const int messageLengthMax = int.fromEnvironment(
    'MESSAGE_LENGTH_MAX',
    defaultValue: 4096,
  );

  /// Which messages the app opens: `comments` (the bundled issue comments,
  /// the default), `showcase` (generated rows of the inline layer and the
  /// emoji-only bodies) or `comments+showcase` (the comments, then one round
  /// of the showcase bodies as the newest messages), from
  /// `--dart-define=CHAT_SOURCE=showcase`.
  static const String chatSource = String.fromEnvironment(
    'CHAT_SOURCE',
    defaultValue: 'comments+showcase',
  );

  /// Where the app starts: `list` (the chat list, a chat pushed from a row,
  /// the default) or `chat` (straight into the chat), from
  /// `--dart-define=START_AT=chat`.
  static const String startAt = String.fromEnvironment(
    'START_AT',
    defaultValue: 'list',
  );

  /// Which wallpaper the chats show: `mask` (the freeform gradient seen
  /// through the pattern, the default), `softLight` (the pattern over the
  /// gradient), `freeform`, `linear`, `solid` or `none`, from
  /// `--dart-define=WALLPAPER=freeform`. On-device suites compare them.
  static const String wallpaper = String.fromEnvironment(
    'WALLPAPER',
    defaultValue: 'mask',
  );

  /// Whether glass paints flat, as under a host's low-power mode, from
  /// `--dart-define=GLASS_LITE=true`. On-device suites use it to tell the
  /// glass's share of a frame from the wallpaper's.
  static const bool glassLite = bool.fromEnvironment('GLASS_LITE');

  /// Whether the Supabase publishable key is set.
  static bool get hasSupabasePublishableKey =>
      supabasePublishableKey.isNotEmpty;
}
