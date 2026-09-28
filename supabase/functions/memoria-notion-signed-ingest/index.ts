import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { verifyNotionSignature, verifiedEventToIngestRow } from "./verify.ts";

// Dedicated server-to-server ingress. The legacy n8n workflow remains untouched
// until the private Notion verification token has been installed in Supabase.
const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  } });
const MAX_WRAPPED_BYTES = 70_000;
const MAX_RAW_BYTES = 60_000;
const enc = new TextEncoder();

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405);
  const token = Deno.env.get("NOTION_WEBHOOK_VERIFICATION_TOKEN") ?? "";
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  // A missing token NEVER turns this endpoint into an unsigned ingestion path.
  if (!token || !url || !service) return json({ ok: false, error: "NOT_CONFIGURED" }, 503);
  if (!(req.headers.get("content-type") ?? "").toLowerCase().startsWith("application/json"))
    return json({ ok: false, error: "JSON_REQUIRED" }, 415);
  if (Number(req.headers.get("content-length") ?? 0) > MAX_WRAPPED_BYTES)
    return json({ ok: false, error: "PAYLOAD_TOO_LARGE" }, 413);

  let envelope: unknown;
  try {
    const bytes = new Uint8Array(await req.arrayBuffer());
    if (bytes.byteLength > MAX_WRAPPED_BYTES) return json({ ok: false, error: "PAYLOAD_TOO_LARGE" }, 413);
    envelope = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch { return json({ ok: false, error: "INVALID_JSON" }, 400); }
  if (!envelope || typeof envelope !== "object" || Array.isArray(envelope))
    return json({ ok: false, error: "INVALID_ENVELOPE" }, 400);

  const { raw_body, signature } = envelope as Record<string, unknown>;
  if (typeof raw_body !== "string" || enc.encode(raw_body).byteLength > MAX_RAW_BYTES ||
      typeof signature !== "string")
    return json({ ok: false, error: "INVALID_ENVELOPE" }, 400);

  const verified = await verifyNotionSignature(raw_body, signature, token);
  if (!verified) return json({ ok: false, error: "UNAUTHORIZED_SIGNATURE" }, 401);
  let row;
  try { row = verifiedEventToIngestRow(JSON.parse(raw_body)); }
  catch { return json({ ok: false, error: "INVALID_SIGNED_EVENT" }, 400); }

  // The database already has a unique index on owner/source/external_id/event_type.
  // Ignore authentic delivery retries without modifying previously processed events.
  const endpoint = new URL(url + "/rest/v1/memory_ingest_events");
  endpoint.searchParams.set("on_conflict", "owner_key,source_type,external_id,event_type");
  try {
    const r = await fetch(endpoint, {
      method: "POST",
      headers: {
        apikey: service,
        authorization: "Bearer " + service,
        "content-type": "application/json",
        prefer: "resolution=ignore-duplicates,return=minimal",
      },
      body: JSON.stringify(row),
      signal: AbortSignal.timeout(8_000),
    });
    if (!r.ok) {
      console.error("Notion signed ingestion insert failed", r.status);
      return json({ ok: false, error: "INGEST_FAILED" }, 502);
    }
    return json({ ok: true, authenticated: true, external_id: row.external_id }, 200);
  } catch {
    console.error("Notion signed ingestion transport failed");
    return json({ ok: false, error: "INGEST_UNAVAILABLE" }, 502);
  }
});
