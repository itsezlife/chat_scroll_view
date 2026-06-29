// ignore_for_file: public_member_api_docs, avoid_classes_with_only_static_members

/// Demo Supabase settings from `--dart-define` / `--dart-define-from-file`.
abstract final class DemoConfig {
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

  static const int demoChatId = int.fromEnvironment(
    'DEMO_CHAT_ID',
    defaultValue: 1,
  );

  static bool get hasSupabasePublishableKey =>
      supabasePublishableKey.isNotEmpty;
}
