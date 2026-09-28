/** Minimal Notion signature and metadata validation. No credentials are stored here. */
const utf8 = new TextEncoder();
const HEX = /^[0-9a-f]{64}$/i;
const UUID = /^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$/i;

export async function verifyNotionSignature(
  originalBody: string, header: string | null, verificationToken: string,
): Promise<boolean> {
  if (!originalBody || !verificationToken || !header?.startsWith("sha256=")) return false;
  const hex = header.slice(7);
  if (!HEX.test(hex)) return false;
  const signature = new Uint8Array(hex.match(/../g)!.map((pair) => Number.parseInt(pair, 16)));
  const key = await crypto.subtle.importKey(
    "raw", utf8.encode(verificationToken), { name: "HMAC", hash: "SHA-256" },
    false, ["verify"],
  );
  // WebCrypto verifies the exact original bytes without re-serializing the payload.
  return await crypto.subtle.verify("HMAC", key, signature, utf8.encode(originalBody));
}

type InputEvent = Record<string, unknown>;
export type IngestRow = {
  owner_key: "duilio";
  source_type: "notion";
  source_name: string;
  external_id: string;
  event_type: string;
  title: string;
  content: string;
  summary: string;
  category: "documentation";
  memory_type: "observation";
  importance: 6;
  occurred_at: string;
  metadata: Record<string, unknown>;
};

export function verifiedEventToIngestRow(payload: unknown): IngestRow {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("INVALID_EVENT");
  }
  const event = payload as InputEvent;
  const id = event.id;
  const type = event.type;
  const timestamp = event.timestamp;
  const entity = event.entity;
  if (typeof id !== "string" || !UUID.test(id) ||
      typeof type !== "string" || !/^[a-z_]+\.[a-z_]+$/.test(type) ||
      typeof timestamp !== "string" || Number.isNaN(Date.parse(timestamp)) ||
      !entity || typeof entity !== "object" || Array.isArray(entity)) {
    throw new Error("INVALID_EVENT");
  }
  const entityId = (entity as Record<string, unknown>).id;
  const entityType = (entity as Record<string, unknown>).type;
  if (typeof entityId !== "string" || !UUID.test(entityId)) throw new Error("INVALID_ENTITY");
  return {
    owner_key: "duilio",
    source_type: "notion",
    source_name: "Espacio de duilio",
    external_id: "notion:" + id,
    event_type: type,
    // Notion webhook events contain metadata, not the current page contents.
    title: "Evento Notion: " + type,
    content: JSON.stringify({ id, type, timestamp, entity: { id: entityId, type: entityType ?? null } }),
    summary: "Evento autenticado de Notion; recuperar página con conexión autorizada antes de resumir contenido.",
    category: "documentation",
    memory_type: "observation",
    importance: 6,
    occurred_at: new Date(timestamp).toISOString(),
    metadata: { signature_verified: true, webhook_version: 2, entity_id: entityId,
      entity_type: typeof entityType === "string" ? entityType : null },
  };
}
