import 'package:content_model/testing.dart';

void main() {
  RecentsStoreContract.run(
    ({required capacity}) async => FakeRecentsStore(capacity: capacity),
  );
}
