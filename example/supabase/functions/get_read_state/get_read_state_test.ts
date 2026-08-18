import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { handleGetReadState } from "./handler.ts";

type QueryResult = {
  data?: unknown;
  error?: { message: string } | null;
  count?: number | null;
};

function mockSupabase(handlers: {
  chatCount?: number;
  readState?: Record<string, unknown> | null;
  readStateError?: string;
}): SupabaseClient {
  const from = (table: string) => {
    const builder = {
      _filters: [] as Array<[string, unknown]>,
      select(_cols: string, opts?: { count?: string; head?: boolean }) {
        if (opts?.head) {
          return {
            eq(column: string, _value: unknown) {
              if (table === "chats" && column === "id") {
                return Promise.resolve(
                  {
                    count: handlers.chatCount ?? 0,
                    error: null,
                  } satisfies QueryResult,
                );
              }
              return Promise.resolve({ count: 0, error: null });
            },
          };
        }
        return builder;
      },
      eq(column: string, value: unknown) {
        builder._filters.push([column, value]);
        return builder;
      },
      maybeSingle() {
        if (table !== "chat_read_state") {
          return Promise.resolve({ data: null, error: null });
        }
        if (handlers.readStateError) {
          return Promise.resolve({
            data: null,
            error: { message: handlers.readStateError },
          });
        }
        return Promise.resolve({
          data: handlers.readState ?? null,
          error: null,
        });
      },
    };
    return builder;
  };

  return { from } as unknown as SupabaseClient;
}

Deno.test("get_read_state returns seeded last_read_message_id", async () => {
  const supabase = mockSupabase({
    chatCount: 1,
    readState: {
      chat_id: 1,
      user_id: 1,
      last_read_message_id: 9951,
      updated_at: "2024-03-09T12:00:00.000Z",
    },
  });

  const response = await handleGetReadState(supabase, {
    chat_id: 1,
    user_id: 1,
  });
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.last_read_message_id, 9951);
  assertEquals(body.chat_id, 1);
  assertEquals(body.user_id, 1);
  assertEquals(typeof body.updated_at, "number");
});

Deno.test("get_read_state returns null when no row", async () => {
  const supabase = mockSupabase({ chatCount: 1, readState: null });

  const response = await handleGetReadState(supabase, {
    chat_id: 1,
    user_id: 1,
  });
  const body = await response.json();
  assertEquals(body.last_read_message_id, null);
  assertEquals(body.updated_at, null);
});

Deno.test("get_read_state unknown chat returns chat_not_found", async () => {
  const supabase = mockSupabase({ chatCount: 0 });

  const response = await handleGetReadState(supabase, {
    chat_id: 99,
    user_id: 1,
  });
  assertEquals(response.status, 404);
  const body = await response.json();
  assertEquals(body.error.slug, "chat_not_found");
});

Deno.test("get_read_state invalid ids return malformed_frame", async () => {
  const supabase = mockSupabase({ chatCount: 1 });

  const response = await handleGetReadState(supabase, {
    chat_id: 0,
    user_id: 1,
  });
  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error.slug, "malformed_frame");
});
