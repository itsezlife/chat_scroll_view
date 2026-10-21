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
  /// the default) or `showcase` (generated rows of the inline layer and the
  /// emoji-only bodies), from `--dart-define=CHAT_SOURCE=showcase`.
  static const String chatSource = String.fromEnvironment(
    'CHAT_SOURCE',
    defaultValue: 'comments',
  );

  /// Whether the Supabase publishable key is set.
  static bool get hasSupabasePublishableKey =>
      supabasePublishableKey.isNotEmpty;
}
