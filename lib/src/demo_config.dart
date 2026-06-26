/// Demo backend URL from `--dart-define=DEMO_BACKEND_URL=...`.
abstract final class DemoConfig {
  static const String backendUrl = String.fromEnvironment(
    'DEMO_BACKEND_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );
}
