import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { MessageFlags, rowToMessageJson } from "../_shared/protocol.ts";
import { validateLoadRequest } from "../_shared/load_request.ts";

Deno.test("load_messages validation rejects invalid range", () => {
  assertEquals(
    validateLoadRequest({ chat_id: 1, from_id: 5, to_id: 3 }),
    "chat_id, from_id, to_id required; from_id >= 1; to_id >= from_id",
  );
  assertEquals(
    validateLoadRequest({ chat_id: 1, from_id: 0, to_id: 10 }),
    "chat_id, from_id, to_id required; from_id >= 1; to_id >= from_id",
  );
  assertEquals(
    validateLoadRequest({ chat_id: 1, from_id: 1, to_id: 64 }),
    null,
  );
});

Deno.test("rowToMessageJson exposes required protocol fields", () => {
  const json = rowToMessageJson({
    chat_id: 1,
    id: 65,
    sender_id: 1,
    created_at: "2020-03-02T00:19:16.000Z",
    updated_at: "2020-03-02T00:19:16.000Z",
    kind: 0,
    flags: 0,
    reply_to_id: null,
    content: "hello",
    rich_content: null,
    extra: { legacy_sender: "alice" },
  });

  assertEquals(json.id, 65);
  assertEquals(json.chat_id, 1);
  assertEquals(json.sender_id, 1);
  assertEquals(typeof json.created_at, "number");
  assertEquals(typeof json.updated_at, "number");
  assertEquals(json.kind, 0);
  assertEquals(json.flags, 0);
  assertEquals(json.content, "hello");
  assertEquals(json.extra?.legacy_sender, "alice");
});

Deno.test("rowToMessageJson tombstone clears content when DELETED", () => {
  const json = rowToMessageJson({
    chat_id: 1,
    id: 99,
    sender_id: 1,
    created_at: "2020-03-02T00:19:16.000Z",
    updated_at: "2020-03-02T00:19:16.000Z",
    kind: 0,
    flags: MessageFlags.DELETED,
    reply_to_id: null,
    content: "should be hidden",
    rich_content: null,
    extra: null,
  });

  assertEquals(json.content, "");
  assertEquals((json.flags & MessageFlags.DELETED) !== 0, true);
});
