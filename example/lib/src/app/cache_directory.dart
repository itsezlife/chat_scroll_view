import 'package:chat_scroll_view_example/src/app/cache_directory_stub.dart'
    if (dart.library.io) 'package:chat_scroll_view_example/src/app/cache_directory_io.dart'
    as platform;

/// The folder [name] in this platform's cache folder for the app, or null
/// where there is none (the web, or a platform that does not say): what is
/// cached there is then kept in memory only.
///
/// The platform may clear it under storage pressure; only caches go there.
Future<String?> appCacheDirectory(String name) =>
    platform.appCacheDirectory(name);
