/// Fakes for the loading seam of `emoji_data`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them. The seam fakes of the sources themselves
/// (`FakeCollectionSource` and the like) live in `content_model/testing.dart`.
library;

export 'src/testing/fake_emoji_asset_loader.dart';
