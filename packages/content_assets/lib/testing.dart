/// Fakes and contract suites for the seams of `content_assets`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/embed/testing/compositing_embed_contract.dart';
export 'src/embed/testing/fake_inline_embed.dart';
export 'src/embed/testing/inline_embed_contract.dart';
export 'src/embed/testing/inline_embed_resolver_contract.dart';
export 'src/embed/testing/playable_embed_contract.dart';
