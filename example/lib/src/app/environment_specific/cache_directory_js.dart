/// The web hook: no files here, so what is cached is kept in memory only.
Future<String?> $appCacheDirectory(
  String name, {
  String? operatingSystem,
  Map<String, String>? environment,
}) async => null;

/// The web hook: no user cache folder.
String? $userCacheDirectory(
  String name, {
  String? operatingSystem,
  Map<String, String>? environment,
}) => null;
