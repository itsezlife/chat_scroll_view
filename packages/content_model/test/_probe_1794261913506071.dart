import 'package:content_model/content_model.dart';

Future<ContentLibrary> make(LibraryStorage storage) =>
    StoredContentLibrary.load(
      storage,
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
    );
