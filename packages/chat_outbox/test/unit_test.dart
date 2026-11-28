/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'diagnostics/outbox_debug_snapshot_test.dart'
    as diagnostics_outbox_debug_snapshot_test;
import 'message/outgoing_message_test.dart' as message_outgoing_message_test;
import 'message/outgoing_payload_codec_test.dart'
    as message_outgoing_payload_codec_test;
import 'message/outgoing_status_test.dart' as message_outgoing_status_test;
import 'outbox/chat_outbox_capabilities_test.dart'
    as outbox_chat_outbox_capabilities_test;
import 'outbox/chat_outbox_projection_test.dart'
    as outbox_chat_outbox_projection_test;
import 'outbox/chat_outbox_send_origin_test.dart'
    as outbox_chat_outbox_send_origin_test;
import 'outbox/chat_outbox_send_test.dart' as outbox_chat_outbox_send_test;
import 'outbox/chat_outbox_test.dart' as outbox_chat_outbox_test;
import 'transfers/outbox_transfers_test.dart'
    as transfers_outbox_transfers_test;

void main() {
  group(
    'diagnostics/outbox_debug_snapshot_test.dart',
    diagnostics_outbox_debug_snapshot_test.main,
  );
  group(
    'message/outgoing_message_test.dart',
    message_outgoing_message_test.main,
  );
  group(
    'message/outgoing_payload_codec_test.dart',
    message_outgoing_payload_codec_test.main,
  );
  group('message/outgoing_status_test.dart', message_outgoing_status_test.main);
  group(
    'outbox/chat_outbox_capabilities_test.dart',
    outbox_chat_outbox_capabilities_test.main,
  );
  group(
    'outbox/chat_outbox_projection_test.dart',
    outbox_chat_outbox_projection_test.main,
  );
  group(
    'outbox/chat_outbox_send_origin_test.dart',
    outbox_chat_outbox_send_origin_test.main,
  );
  group('outbox/chat_outbox_send_test.dart', outbox_chat_outbox_send_test.main);
  group('outbox/chat_outbox_test.dart', outbox_chat_outbox_test.main);
  group(
    'transfers/outbox_transfers_test.dart',
    transfers_outbox_transfers_test.main,
  );
}
