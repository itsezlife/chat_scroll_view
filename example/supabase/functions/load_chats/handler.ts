/**
 * load_chats handler — returns inbox list of ChatEntry objects.
 *
 * POST body: `{ user_id?: number }` (defaults to 1 for unread_count).
 * Response: `{ chats: ChatEntryJson[] }` ordered by chat id ascending.
 * Errors: malformed_frame, database_error.
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { buildChatEntry, type ChatRow } from "../_shared/chat_entry.ts";
import { errorResponse, jsonResponse } from "../_shared/errors.ts";

export interface LoadChatsRequest {
  user_id?: number;
}

export async function handleLoadChats(
  supabase: SupabaseClient,
  body: LoadChatsRequest,
): Promise<Response> {
  const userId = body.user_id ?? 1;
  if (!Number.isInteger(userId) || userId < 1) {
    return errorResponse(
      "malformed_frame",
      "user_id must be a positive integer when provided",
    );
  }

  const { data: rows, error } = await supabase
    .from("chats")
    .select(
      "id, kind, parent_id, created_at, updated_at, title, avatar_url, member_count",
    )
    .order("id", { ascending: true });

  if (error) {
    return errorResponse("database_error", error.message);
  }

  const chats = [];
  for (const row of rows ?? []) {
    chats.push(await buildChatEntry(supabase, row as ChatRow, userId));
  }

  return jsonResponse({ chats });
}
