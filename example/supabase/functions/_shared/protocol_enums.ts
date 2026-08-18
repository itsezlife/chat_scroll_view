/**
 * Protocol enumerations and bitfields — canonical value tables for the demo backend.
 *
 * Storage types in Postgres:
 * - Discrete enums (ChatKind, MessageKind, ChatRole): int2, single value 0–N
 * - Bitfields (MessageFlags, UserFlags, Permission, RichStyle): int2/int4, OR-combined bits
 *
 * JSON responses echo the same numeric values as numbers.
 *
 * @example Check deleted tombstone before rendering content
 * ```ts
 * if (hasMessageFlag(row.flags, MessageFlags.DELETED)) {
 *   // content is ""; content_preview is "" in chat_last_message
 * }
 * ```
 *
 * @example Validate kind before insert (reject unknown values)
 * ```ts
 * const kind = parseMessageKind(body.kind ?? MessageKind.Text);
 * if (kind === null) return errorResponse("malformed_frame", "invalid message kind");
 * ```
 */

// -----------------------------------------------------------------------------
// ChatKind — chats.kind (int2), ChatEntry.kind (JSON number)
// Discrete enum; NOT a bitfield. Unknown values MUST be rejected on write.
// -----------------------------------------------------------------------------

export const ChatKind = {
  /** Direct message — exactly two participants; title is null. */
  Direct: 0,
  /** Group conversation — demo chat id 1 is Group. */
  Group: 1,
  /** Broadcast channel nested under a Group; parent_id required. */
  Channel: 2,
} as const;

export type ChatKindValue = (typeof ChatKind)[keyof typeof ChatKind];

/** Valid ChatKind values: 0, 1, 2. Returns null for unknown. */
export function parseChatKind(value: number): ChatKindValue | null {
  if (
    value === ChatKind.Direct || value === ChatKind.Group ||
    value === ChatKind.Channel
  ) {
    return value;
  }
  return null;
}

// -----------------------------------------------------------------------------
// ChatRole — member privilege (not stored in demo v1; used in Permission defaults)
// Discrete enum u8/int2. Ordered: Member < Moderator < Admin < Owner.
// -----------------------------------------------------------------------------

export const ChatRole = {
  Member: 0,
  Moderator: 1,
  Admin: 2,
  Owner: 3,
} as const;

export type ChatRoleValue = (typeof ChatRole)[keyof typeof ChatRole];

// -----------------------------------------------------------------------------
// Permission — per-member capability bitfield (u32 / int4 when stored)
// NULL in DB means "use role × chat-kind defaults" (see defaultPermissions).
// Bit ranges are intentional gaps for future flags.
// -----------------------------------------------------------------------------

export const Permission = {
  // Messages (bits 0–5)
  SEND_MESSAGES: 1 << 0,
  SEND_MEDIA: 1 << 1,
  SEND_LINKS: 1 << 2,
  PIN_MESSAGES: 1 << 3,
  EDIT_OWN_MESSAGES: 1 << 4,
  DELETE_OWN_MESSAGES: 1 << 5,
  // bits 6–9 reserved
  // Moderation (bits 10–12)
  DELETE_OTHERS_MESSAGES: 1 << 10,
  MUTE_MEMBERS: 1 << 11,
  BAN_MEMBERS: 1 << 12,
  // bits 13–19 reserved
  // Management (bits 20–23)
  INVITE_MEMBERS: 1 << 20,
  KICK_MEMBERS: 1 << 21,
  MANAGE_CHAT_INFO: 1 << 22,
  MANAGE_ROLES: 1 << 23,
  // bits 24–29 reserved
  // Owner (bits 30–31)
  TRANSFER_OWNERSHIP: 1 << 30,
  DELETE_CHAT: 1 << 31,
} as const;

/**
 * Default permission mask when no per-member override is stored.
 *
 * Channel + Member → empty (read-only). Owner → all bits set.
 */
export function defaultPermissions(
  role: ChatRoleValue,
  chatKind: ChatKindValue,
): number {
  const p = Permission;
  switch (role) {
    case ChatRole.Owner:
      return p.SEND_MESSAGES | p.SEND_MEDIA | p.SEND_LINKS | p.PIN_MESSAGES |
        p.EDIT_OWN_MESSAGES | p.DELETE_OWN_MESSAGES | p.DELETE_OTHERS_MESSAGES |
        p.MUTE_MEMBERS | p.BAN_MEMBERS | p.INVITE_MEMBERS | p.KICK_MEMBERS |
        p.MANAGE_CHAT_INFO | p.MANAGE_ROLES | p.TRANSFER_OWNERSHIP |
        p.DELETE_CHAT;
    case ChatRole.Admin:
      return p.SEND_MESSAGES | p.SEND_MEDIA | p.SEND_LINKS | p.PIN_MESSAGES |
        p.EDIT_OWN_MESSAGES | p.DELETE_OWN_MESSAGES | p.DELETE_OTHERS_MESSAGES |
        p.MUTE_MEMBERS | p.BAN_MEMBERS | p.INVITE_MEMBERS | p.KICK_MEMBERS |
        p.MANAGE_CHAT_INFO | p.MANAGE_ROLES;
    case ChatRole.Moderator:
      return p.SEND_MESSAGES | p.SEND_MEDIA | p.SEND_LINKS | p.PIN_MESSAGES |
        p.EDIT_OWN_MESSAGES | p.DELETE_OWN_MESSAGES | p.DELETE_OTHERS_MESSAGES |
        p.MUTE_MEMBERS;
    case ChatRole.Member:
      if (chatKind === ChatKind.Channel) return 0;
      return p.SEND_MESSAGES | p.SEND_MEDIA | p.SEND_LINKS |
        p.EDIT_OWN_MESSAGES |
        p.DELETE_OWN_MESSAGES;
    default:
      return 0;
  }
}

// -----------------------------------------------------------------------------
// MessageKind — messages.kind, chat_last_message.kind (int2)
// Discrete enum. System messages SHOULD also set MessageFlags.SYSTEM (0x0020).
// -----------------------------------------------------------------------------

export const MessageKind = {
  /** Plain text — demo send_message always inserts 0. */
  Text: 0,
  Image: 1,
  File: 2,
  /** Join/leave etc.; pair with MessageFlags.SYSTEM. */
  System: 3,
} as const;

export type MessageKindValue = (typeof MessageKind)[keyof typeof MessageKind];

/** Valid MessageKind: 0–3. Returns null for unknown (e.g. 4+). */
export function parseMessageKind(value: number): MessageKindValue | null {
  if (value >= MessageKind.Text && value <= MessageKind.System) {
    return value as MessageKindValue;
  }
  return null;
}

// -----------------------------------------------------------------------------
// MessageFlags — messages.flags, chat_last_message.flags (int2 / u16 bitfield)
// Combinable with bitwise OR. Reserved: 0x0100–0x8000 (bits 8–15) MUST be 0.
// -----------------------------------------------------------------------------

export const MessageFlags = {
  /** 0x0001 — edited at least once; UI shows "edited". */
  EDITED: 0x0001,
  /** 0x0002 — soft delete; content forced to ""; preview cleared in trigger. */
  DELETED: 0x0002,
  /** 0x0004 — forwarded; origin chat in extra JSON. */
  FORWARDED: 0x0004,
  /** 0x0008 — pinned in this chat. */
  PINNED: 0x0008,
  /** 0x0010 — suppress push notification. */
  SILENT: 0x0010,
  /** 0x0020 — system event; pair with MessageKind.System. */
  SYSTEM: 0x0020,
  /** 0x0040 — sender is bot; server sets for bot users. */
  BOT: 0x0040,
  /** 0x0080 — reply; reply_to_id MUST be set. */
  REPLY: 0x0080,
} as const;

/** Bits 8–15 reserved; mask of allowed flags for validation. */
export const MESSAGE_FLAGS_ALLOWED_MASK = 0x00ff;

export function hasMessageFlag(flags: number, bit: number): boolean {
  return (flags & bit) !== 0;
}

/** True when any reserved bit (0x0100+) is set. */
export function hasReservedMessageFlags(flags: number): boolean {
  return (flags & ~MESSAGE_FLAGS_ALLOWED_MASK) !== 0;
}

// -----------------------------------------------------------------------------
// UserFlags — users.flags (int2 / u16 bitfield)
// 0x0008–0x8000 reserved. BOT causes server to set MessageFlags.BOT on sends.
// -----------------------------------------------------------------------------

export const UserFlags = {
  /** 0x0001 — system account (server-generated). */
  SYSTEM: 0x0001,
  /** 0x0002 — bot account. */
  BOT: 0x0002,
  /** 0x0004 — premium subscriber badge. */
  PREMIUM: 0x0004,
} as const;

export const USER_FLAGS_ALLOWED_MASK = 0x0007;

export function hasUserFlag(flags: number, bit: number): boolean {
  return (flags & bit) !== 0;
}

// -----------------------------------------------------------------------------
// RichStyle — rich_content span style (u16 bitfield in JSON spans)
// Inline styles combinable. CODE_BLOCK / BLOCKQUOTE are block-level: when set,
// clients ignore inline style bits on that span. LINK/MENTION/COLOR/CODE_BLOCK
// require meta JSON on the span object.
// -----------------------------------------------------------------------------

export const RichStyle = {
  // Inline (combinable)
  BOLD: 0x0001,
  ITALIC: 0x0002,
  UNDERLINE: 0x0004,
  STRIKE: 0x0008,
  SPOILER: 0x0010,
  CODE: 0x0020,
  // With meta JSON
  LINK: 0x0040,
  MENTION: 0x0080,
  COLOR: 0x0100,
  // Block-level (exclusive on span)
  CODE_BLOCK: 0x0200,
  BLOCKQUOTE: 0x0400,
} as const;

/** 0x0800–0x8000 reserved for future rich styles. */
export const RICH_STYLE_RESERVED_FROM = 0x0800;

export function richStyleHasMeta(style: number): boolean {
  return (style &
    (RichStyle.LINK | RichStyle.MENTION | RichStyle.COLOR |
      RichStyle.CODE_BLOCK)) !== 0;
}
