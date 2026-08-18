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

  /// Whether the Supabase publishable key is set.
  static bool get hasSupabasePublishableKey =>
      supabasePublishableKey.isNotEmpty;
}
