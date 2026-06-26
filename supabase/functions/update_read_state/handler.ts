/**
 * update_read_state handler — upsert last_read_message_id for a user in a chat.
 *
 * POST body: `{ chat_id, user_id, last_read_message_id }` (all required positive ints).
 * Validates message id exists and does not exceed newest id in chat.
 * Response: same shape as get_read_state success body.
 * Errors: malformed_frame, chat_not_found, message_not_found, database_error.
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { errorResponse, jsonResponse } from "../_shared/errors.ts";

export interface UpdateReadStateRequest {
  chat_id?: number;
  user_id?: number;
  last_read_message_id?: number;
}

export async function handleUpdateReadState(
  supabase: SupabaseClient,
  body: UpdateReadStateRequest,
): Promise<Response> {
  const chatId = body.chat_id;
  const userId = body.user_id;
  const lastReadId = body.last_read_message_id;

  if (
    chatId == null || userId == null || lastReadId == null ||
    !Number.isInteger(chatId) || !Number.isInteger(userId) ||
    !Number.isInteger(lastReadId) || chatId < 1 || userId < 1 ||
    lastReadId < 1
  ) {
    return errorResponse(
      "malformed_frame",
      "chat_id, user_id, last_read_message_id required positive integers",
    );
  }

  const { count: chatCount, error: chatErr } = await supabase
    .from("chats")
    .select("id", { count: "exact", head: true })
    .eq("id", chatId);

  if (chatErr) {
    return errorResponse("database_error", chatErr.message);
  }
  if (!chatCount) {
    return errorResponse("chat_not_found", `Chat ${chatId} does not exist`);
  }

  const { data: maxRow, error: maxErr } = await supabase
    .from("messages")
    .select("id")
    .eq("chat_id", chatId)
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (maxErr) {
    return errorResponse("database_error", maxErr.message);
  }

  const newestId = maxRow?.id ?? 0;
  if (lastReadId > newestId) {
    return errorResponse(
      "malformed_frame",
      `last_read_message_id ${lastReadId} exceeds newest id ${newestId}`,
    );
  }

  const { count: messageCount, error: msgErr } = await supabase
    .from("messages")
    .select("id", { count: "exact", head: true })
    .eq("chat_id", chatId)
    .eq("id", lastReadId);

  if (msgErr) {
    return errorResponse("database_error", msgErr.message);
  }
  if (!messageCount) {
    return errorResponse(
      "message_not_found",
      `Message ${lastReadId} not found in chat ${chatId}`,
    );
  }

  const now = new Date().toISOString();
  const { data: upserted, error: upsertErr } = await supabase
    .from("chat_read_state")
    .upsert(
      {
        chat_id: chatId,
        user_id: userId,
        last_read_message_id: lastReadId,
        updated_at: now,
      },
      { onConflict: "chat_id,user_id" },
    )
    .select("chat_id, user_id, last_read_message_id, updated_at")
    .single();

  if (upsertErr) {
    return errorResponse("database_error", upsertErr.message);
  }

  return jsonResponse({
    chat_id: upserted.chat_id,
    user_id: upserted.user_id,
    last_read_message_id: upserted.last_read_message_id,
    updated_at: Math.floor(new Date(upserted.updated_at).getTime() / 1000),
  });
}
