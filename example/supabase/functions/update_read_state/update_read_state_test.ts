import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { handleUpdateReadState } from "./handler.ts";

type UpsertPayload = Record<string, unknown>;

function mockSupabase(handlers: {
  chatCount?: number;
  newestId?: number;
  messageExists?: boolean;
  upserted?: Record<string, unknown>;
}): SupabaseClient {
  const from = (table: string) => {
    const state = {
      filters: [] as Array<[string, unknown]>,
      head: false,
      orderDesc: false,
      limitOne: false,
    };

    const builder = {
      select(_cols: string, opts?: { count?: string; head?: boolean }) {
        state.head = opts?.head === true;
        return builder;
      },
      eq(column: string, value: unknown) {
        state.filters.push([column, value]);
        return builder;
      },
      order(_column: string, opts?: { ascending?: boolean }) {
        state.orderDesc = opts?.ascending === false;
        return builder;
      },
      limit(_n: number) {
        state.limitOne = true;
        return builder;
      },
      maybeSingle() {
        if (table === "messages" && state.orderDesc) {
          return Promise.resolve({
            data: handlers.newestId != null ? { id: handlers.newestId } : null,
            error: null,
          });
        }
        return Promise.resolve({ data: null, error: null });
      },
      upsert(payload: UpsertPayload, _opts?: { onConflict: string }) {
        return {
          select(_cols: string) {
            return {
              single() {
                return Promise.resolve({
                  data: handlers.upserted ?? payload,
                  error: null,
                });
              },
            };
          },
        };
      },
      then(
        resolve: (value: { count: number | null; error: null }) => void,
      ) {
        if (state.head && table === "chats") {
          resolve({ count: handlers.chatCount ?? 0, error: null });
          return;
        }
        if (state.head && table === "messages") {
          resolve({ count: handlers.messageExists ? 1 : 0, error: null });
          return;
        }
        resolve({ count: 0, error: null });
      },
    };

    return builder;
  };

  return { from } as unknown as SupabaseClient;
}

Deno.test("update_read_state upserts at tail id", async () => {
  const supabase = mockSupabase({
    chatCount: 1,
    newestId: 10004,
    messageExists: true,
    upserted: {
      chat_id: 1,
      user_id: 1,
      last_read_message_id: 10004,
      updated_at: "2024-03-09T12:00:01.000Z",
    },
  });

  const response = await handleUpdateReadState(supabase, {
    chat_id: 1,
    user_id: 1,
    last_read_message_id: 10004,
  });
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.last_read_message_id, 10004);
  assertEquals(typeof body.updated_at, "number");
});

Deno.test("update_read_state rejects id ahead of newest", async () => {
  const supabase = mockSupabase({
    chatCount: 1,
    newestId: 10004,
    messageExists: true,
  });

  const response = await handleUpdateReadState(supabase, {
    chat_id: 1,
    user_id: 1,
    last_read_message_id: 10005,
  });
  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error.slug, "malformed_frame");
});

Deno.test("update_read_state missing message returns message_not_found", async () => {
  const supabase = mockSupabase({
    chatCount: 1,
    newestId: 10004,
    messageExists: false,
  });

  const response = await handleUpdateReadState(supabase, {
    chat_id: 1,
    user_id: 1,
    last_read_message_id: 9999,
  });
  assertEquals(response.status, 404);
  const body = await response.json();
  assertEquals(body.error.slug, "message_not_found");
});
