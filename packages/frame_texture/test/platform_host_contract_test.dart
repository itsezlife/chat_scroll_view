import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/host_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final table = HostTable.compile();
  if (table == null) {
    test('FrameTextureHost contract', () {}, skip: HostTable.skipReason);
    return;
  }

  group('over the texture table, packed rows', () {
    FrameTextureHostContract.run(() => FakeTexturePlatform(table).host());
  });

  group('over the texture table, padded rows', () {
    FrameTextureHostContract.run(
      () => FakeTexturePlatform(table, rowPadding: 16).host(),
    );
  });
}
