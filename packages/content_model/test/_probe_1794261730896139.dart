import 'package:content_model/content_model.dart';

Future<PreferenceStore> make(KeyValueStore storage) =>
    KeyValuePreferenceStore.load(storage, namespace: 'host');
