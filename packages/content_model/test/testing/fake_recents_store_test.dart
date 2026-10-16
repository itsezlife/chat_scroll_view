import 'package:content_model/testing.dart';

void main() {
  runRecentsStoreContract(
    ({required capacity}) async => FakeRecentsStore(capacity: capacity),
  );
}
