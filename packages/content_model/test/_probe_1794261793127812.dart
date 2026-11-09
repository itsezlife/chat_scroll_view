import 'package:content_model/content_model.dart';

Future<RecentsStore> make(KeyValueStore storage) =>
    KeyValueRecentsStore.load(storage, namespace: 'host');
