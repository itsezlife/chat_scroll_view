import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

/// The GIF page and the stickers page of the panel, wired to the app's
/// [AppServices]: the one place that says how this host composes
/// `panel_pages`' [GifPage] and [StickersPage].
///
/// Both list what the services publish (the recent ones, then the local
/// sticker corpus or Giphy's clips) and draw through the app's asset cache, so a clip or sticker plays
/// by the same pause policies as the chat's. A tap reports a pick, which the
/// chat's input set turns into a sent message.
abstract final class MediaPanelPages {
  /// Id of the GIF page in the shell.
  static const String gifId = 'gif';

  /// Id of the stickers page in the shell.
  static const String stickersId = 'stickers';

  /// The GIF [PanelPage]. With Giphy (an API key was given) it declares
  /// search and shows Giphy's attribution; without, it declares nothing: no
  /// search, no strip, no actions, so the bottom bar shows the type tabs
  /// alone over it.
  static PanelPage gif({required AppServices services}) {
    final search = services.gifSearch;
    return PanelPage(
      id: gifId,
      tab: const PanelTab(icon: ChromeIconId.gif, labelKey: gifId),
      capabilities: search == null
          ? PageCapabilities.none
          : const PageCapabilities(search: true),
      builder: (context, host) => GifPage(
        host: host,
        source: services.gifPageSource,
        assets: services.assets,
        searchSource: search,
        attribution: services.giphy == null
            ? null
            : AppServices.giphyAttribution,
      ),
    );
  }

  /// The stickers [PanelPage]: a strip of packs over the catalogue.
  static PanelPage stickers({required AppServices services}) => PanelPage(
    id: stickersId,
    tab: const PanelTab(icon: ChromeIconId.stickers, labelKey: stickersId),
    capabilities: StickersPagePolicy.pageCapabilities,
    builder: (context, host) => StickersPage(
      host: host,
      source: services.stickerPageSource,
      assets: services.assets,
    ),
  );
}
