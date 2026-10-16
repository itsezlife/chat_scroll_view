/// Build-time half of the emoji catalog pack: reads the pinned Unicode and
/// CLDR sources and produces the shipped assets.
///
/// Pure Dart with no I/O, so every step runs on fixtures. Downloading, hashing
/// and writing files is the job of `tool/generate.dart`.
library;

export 'src/generator/asset_generator.dart';
export 'src/generator/cldr_annotations.dart';
export 'src/generator/emoji_test_file.dart';
export 'src/generator/inputs_lock.dart';
export 'src/generator/keyword_pack_builder.dart';
export 'src/generator/structure_builder.dart';
