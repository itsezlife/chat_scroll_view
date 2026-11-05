import 'dart:ffi';

/// A symbol the shipped library does not export, bound to the same asset as
/// the real ones: calling it fails the way a library of another version would.
@Native<Uint32 Function()>(
  assetId: 'package:lottie_native/src/native/chat_lottie_symbols.dart',
  symbol: 'chat_lottie_symbol_that_does_not_exist',
)
external int missingAbiVersion();
