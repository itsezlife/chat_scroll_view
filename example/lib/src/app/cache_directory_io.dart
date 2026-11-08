import 'dart:io';

import 'package:flutter/services.dart';

const _paths = MethodChannel('chat_scroll_view_example/paths');

/// The folder [name] in the app's cache folder: on Android the one the
/// activity names (`Context.getCacheDir`), elsewhere [userCacheDirectory].
Future<String?> appCacheDirectory(String name) async {
  if (!Platform.isAndroid) return userCacheDirectory(name);
  try {
    final base = await _paths.invokeMethod<String>('cacheDir');
    return base == null ? null : '$base/$name';
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// The folder [name] for this app in the platform's user cache folder, read
/// from the environment: macOS `~/Library/Caches`, Linux `$XDG_CACHE_HOME`
/// else `~/.cache`, Windows `%LOCALAPPDATA%`; null where there is no known
/// folder (Android and iOS name theirs through the platform, not the
/// environment). [operatingSystem] and [environment] default to the running
/// process's.
String? userCacheDirectory(
  String name, {
  String? operatingSystem,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'];
  final (base, separator) = switch (operatingSystem ??
      Platform.operatingSystem) {
    'macos' => (home == null ? null : '$home/Library/Caches', '/'),
    'linux' => (
      env['XDG_CACHE_HOME'] ?? (home == null ? null : '$home/.cache'),
      '/',
    ),
    'windows' => (env['LOCALAPPDATA'], r'\'),
    _ => (null, '/'),
  };
  return base == null
      ? null
      : [base, 'chat_scroll_view_example', name].join(separator);
}
