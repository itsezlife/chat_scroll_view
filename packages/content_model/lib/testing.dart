/// Fakes and contract suites for the seams of `content_model`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them. Hosts and adapter packages run the `run...Contract`
/// suites against their own implementations and use the fakes in their tests.
library;

export 'src/testing/fake_key_value_store.dart';
export 'src/testing/fake_preference_store.dart';
export 'src/testing/fake_recents_store.dart';
export 'src/testing/key_value_store_contract.dart';
export 'src/testing/preference_store_contract.dart';
export 'src/testing/recents_store_contract.dart';
