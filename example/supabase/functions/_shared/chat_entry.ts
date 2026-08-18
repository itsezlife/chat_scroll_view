/**
 * ChatEntry and LastMessagePreview builders for load_chat / load_chats.
 *
 * Postgres sources:
 * - `chats` row → ChatEntry metadata fields
 * - `chat_last_message` row → nested `last_message` object (null when absent)
 * - `chat_read_state` → derived `unread_count`
 *
 * JSON field names match ChatEntry / LastMessagePreview in protocol.ts.
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { MessageFlags, type MessageRow } from "./protocol.ts";

/** Nested tail preview in ChatEntry JSON (from chat_last_message). */
export interface LastMessagePreviewJson {
  /** chat_last_message.message_id */
  id: number;
  /** chat_last_message.sender_id */
  sender_id: number;
  /** chat_last_message.created_at as Unix seconds */
  created_at: number;
  /** chat_last_message.kind (MessageKind) */
  kind: number;
  /** chat_last_message.flags (MessageFlags) */
  flags: number;
  /** chat_last_message.content_preview (max 100 UTF-8 bytes) */
  content_preview: string;
}

/** Conversation list entry returned by load_chat / load_chats. */
export interface ChatEntryJson {
  /** chats.id */
  id: number;
  /** chats.kind (ChatKind) */
  kind: number;
  /** chats.parent_id */
  parent_id: number | null;
  /** chats.created_at as Unix seconds */
  created_at: number;
  /** chats.updated_at as Unix seconds */
  updated_at: number;
  /** chats.title */
  title: string | null;
  /** chats.avatar_url */
  avatar_url: string | null;
  /** from chat_last_message; null when chat has no messages */
  last_message: LastMessagePreviewJson | null;
  /** max(0, last_message.id - last_read_message_id) */
  unread_count: number;
  /** chats.member_count */
  member_count: number;
}

/** Selected columns from public.chats. */
export interface ChatRow {
  id: number;
  kind: number;
  parent_id: number | null;
  created_at: string;
  updated_at: string;
  title: string | null;
  avatar_url: string | null;
  member_count: number;
}

/** Row from public.chat_last_message (denormalized tail preview). */
export interface ChatLastMessageRow {
  chat_id: number;
  message_id: number;
  sender_id: number;
  created_at: string;
  kind: number;
  flags: number;
  content_preview: string;
}

const PREVIEW_MAX_BYTES = 100;
const DEMO_USER_ID = 1;

function truncateUtf8Preview(content: string, maxBytes: number): string {
  const bytes = new TextEncoder().encode(content);
  if (bytes.length <= maxBytes) {
    return content;
  }
  let end = maxBytes;
  while (end > 0 && (bytes[end]! & 0xc0) === 0x80) {
    end--;
  }
  return new TextDecoder().decode(bytes.subarray(0, end));
}

/** Build LastMessagePreview from a full messages row (fallback / tests). */
export function messageRowToLastMessagePreview(
  row: MessageRow,
): LastMessagePreviewJson {
  const deleted = (row.flags & MessageFlags.DELETED) !== 0;
  const previewSource = deleted ? "" : row.content;
  return {
    id: row.id,
    sender_id: row.sender_id,
    created_at: Math.floor(new Date(row.created_at).getTime() / 1000),
    kind: row.kind,
    flags: row.flags,
    content_preview: truncateUtf8Preview(previewSource, PREVIEW_MAX_BYTES),
  };
}

/** Map chat_last_message row to nested JSON preview. */
export function chatLastMessageRowToPreview(
  row: ChatLastMessageRow,
): LastMessagePreviewJson {
  return {
    id: row.message_id,
    sender_id: row.sender_id,
    created_at: Math.floor(new Date(row.created_at).getTime() / 1000),
    kind: row.kind,
    flags: row.flags,
    content_preview: row.content_preview,
  };
}

async function fetchChatLastMessage(
  supabase: SupabaseClient,
  chatId: number,
): Promise<LastMessagePreviewJson | null> {
  const { data, error } = await supabase
    .from("chat_last_message")
    .select(
      "chat_id, message_id, sender_id, created_at, kind, flags, content_preview",
    )
    .eq("chat_id", chatId)
    .maybeSingle();

  if (error || !data) {
    return null;
  }

  return chatLastMessageRowToPreview(data as ChatLastMessageRow);
}

async function computeUnreadCount(
  supabase: SupabaseClient,
  chatId: number,
  userId: number,
  lastMessageId: number | null,
): Promise<number> {
  if (lastMessageId == null) {
    return 0;
  }

  const { data, error } = await supabase
    .from("chat_read_state")
    .select("last_read_message_id")
    .eq("chat_id", chatId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    return 0;
  }

  const lastRead = data?.last_read_message_id ?? 0;
  return Math.max(0, lastMessageId - lastRead);
}

/** Assemble ChatEntry JSON from chats row and computed fields. */
export function chatRowToEntryJson(
  row: ChatRow,
  lastMessage: LastMessagePreviewJson | null,
  unreadCount: number,
): ChatEntryJson {
  return {
    id: row.id,
    kind: row.kind,
    parent_id: row.parent_id,
    created_at: Math.floor(new Date(row.created_at).getTime() / 1000),
    updated_at: Math.floor(new Date(row.updated_at).getTime() / 1000),
    title: row.title,
    avatar_url: row.avatar_url,
    last_message: lastMessage,
    unread_count: unreadCount,
    member_count: row.member_count,
  };
}

/** Load chat_last_message + unread_count and return full ChatEntry JSON. */
export async function buildChatEntry(
  supabase: SupabaseClient,
  row: ChatRow,
  userId = DEMO_USER_ID,
): Promise<ChatEntryJson> {
  const lastMessage = await fetchChatLastMessage(supabase, row.id);
  const unreadCount = await computeUnreadCount(
    supabase,
    row.id,
    userId,
    lastMessage?.id ?? null,
  );
  return chatRowToEntryJson(row, lastMessage, unreadCount);
}
