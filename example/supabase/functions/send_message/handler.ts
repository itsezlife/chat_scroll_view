/**
 * send_message handler — INSERT plain-text Message and return MessageJson.
 *
 * POST body: `{ chat_id, content, sender_id? }` (sender_id defaults to 1).
 * Inserts messages with kind=0 (Text), flags=0; chat_last_message trigger maintains tail.
 * Response: `{ message: MessageJson }`.
 * Errors: malformed_frame, message_too_large, chat_not_found, database_error.
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { errorResponse, jsonResponse } from "../_shared/errors.ts";
import { MessageKind, rowToMessageJson } from "../_shared/protocol.ts";

export interface SendRequest {
  chat_id?: number;
  content?: string;
  sender_id?: number;
}

const MAX_CONTENT_LENGTH = 32_000;

export async function handleSendMessage(
  supabase: SupabaseClient,
  body: SendRequest,
): Promise<Response> {
  const chatId = body.chat_id;
  const content = body.content?.trim() ?? "";
  const senderId = body.sender_id ?? 1;

  if (chatId == null || !Number.isInteger(chatId)) {
    return errorResponse("malformed_frame", "chat_id required");
  }
  if (!content) {
    return errorResponse("malformed_frame", "content required");
  }
  if (content.length > MAX_CONTENT_LENGTH) {
    return errorResponse("message_too_large", "Message exceeds size limit");
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

  const { data: maxRow } = await supabase
    .from("messages")
    .select("id")
    .eq("chat_id", chatId)
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle();

  const nextId = (maxRow?.id ?? 0) + 1;
  const now = new Date().toISOString();

  const { data: inserted, error } = await supabase
    .from("messages")
    .insert({
      chat_id: chatId,
      id: nextId,
      sender_id: senderId,
      created_at: now,
      updated_at: now,
      kind: MessageKind.Text,
      flags: 0,
      content,
    })
    .select("*")
    .single();

  if (error) {
    return errorResponse("database_error", error.message);
  }

  return jsonResponse({ message: rowToMessageJson(inserted) });
}
