/**
 * Chat protocol row ↔ JSON mapping for Edge Functions.
 *
 * Enum and bitfield value tables live in `./protocol_enums.ts` (import from there
 * when validating or documenting flags/kinds).
 *
 * Timestamp rule: Postgres `timestamptz` → JSON Unix seconds (floor ms/1000).
 */

import { hasMessageFlag, MessageFlags } from "./protocol_enums.ts";

export {
  ChatKind,
  ChatRole,
  defaultPermissions,
  hasMessageFlag,
  hasReservedMessageFlags,
  hasUserFlag,
  MESSAGE_FLAGS_ALLOWED_MASK,
  MessageFlags,
  MessageKind,
  parseChatKind,
  parseMessageKind,
  Permission,
  RICH_STYLE_RESERVED_FROM,
  RichStyle,
  richStyleHasMeta,
  USER_FLAGS_ALLOWED_MASK,
  UserFlags,
} from "./protocol_enums.ts";

/** Demo conversation id (single-chat v1). */
export const DEMO_CHAT_ID = 1;

/** Row shape from `select *` on public.messages. */
export interface MessageRow {
  chat_id: number;
  id: number;
  sender_id: number;
  created_at: string;
  updated_at: string;
  /** MessageKind — see protocol_enums.ts (0 Text … 3 System). */
  kind: number;
  /** MessageFlags bitfield — see protocol_enums.ts; bits 8–15 reserved. */
  flags: number;
  reply_to_id: number | null;
  /** Cleared to "" in JSON when DELETED flag set. */
  content: string;
  /** Array of RichSpan objects when present; each span has style (RichStyle bits). */
  rich_content: unknown | null;
  extra: Record<string, unknown> | null;
}

/** Message object returned by load_messages and send_message. */
export interface MessageJson {
  id: number;
  chat_id: number;
  sender_id: number;
  created_at: number;
  updated_at: number;
  kind: number;
  flags: number;
  reply_to_id: number | null;
  content: string;
  rich_content: unknown | null;
  extra: Record<string, unknown> | null;
}

/** Paginated history response from load_messages. */
export interface MessageBatchJson {
  messages: MessageJson[];
  has_more: boolean;
  has_older: boolean;
  has_newer: boolean;
  oldest_id: number | null;
  newest_id: number | null;
  requested_from: number;
  requested_to: number;
}

/**
 * Convert Postgres row to JSON.
 *
 * Design: DELETED tombstone never leaks raw content on the wire — content becomes
 * "" even if the row still holds text in Postgres.
 */
export function rowToMessageJson(row: MessageRow): MessageJson {
  const deleted = hasMessageFlag(row.flags, MessageFlags.DELETED);
  return {
    id: row.id,
    chat_id: row.chat_id,
    sender_id: row.sender_id,
    created_at: Math.floor(new Date(row.created_at).getTime() / 1000),
    updated_at: Math.floor(new Date(row.updated_at).getTime() / 1000),
    kind: row.kind,
    flags: row.flags,
    reply_to_id: row.reply_to_id,
    content: deleted ? "" : row.content,
    rich_content: row.rich_content,
    extra: row.extra,
  };
}
