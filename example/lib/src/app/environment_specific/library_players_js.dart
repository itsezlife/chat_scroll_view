import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_player/mpx_player.dart';

/// The web hook: no device library, so no players.
PlayerPool? $libraryPlayers(MediaLibrary library, {IBytesStore? captures}) =>
    null;

/// The web hook: nothing was made.
void $disposeLibraryPlayers() {}
