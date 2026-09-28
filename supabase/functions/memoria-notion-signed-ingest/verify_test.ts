import { verifyNotionSignature, verifiedEventToIngestRow } from "./verify.ts";

const eq = (a: unknown, b: unknown) => { if (a !== b) throw Error(JSON.stringify({ expected: b, got: a })); };
async function sign(raw: string, secret: string) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(raw)));
  return "sha256=" + Array.from(bytes, (n) => n.toString(16).padStart(2, "0")).join("");
}
const event = {
  id: "c7ae1911-1111-4111-8111-111111111111",
  type: "page.content_updated",
  timestamp: "2026-09-27T21:45:10.000Z",
  entity: { id: "3d0277d8-646b-818f-92ca-c1b62319cbd3", type: "page" },
};

Deno.test("accepts authentic signature over exact unchanged bytes", async () => {
  const raw = JSON.stringify(event);
  eq(await verifyNotionSignature(raw, await sign(raw, "notion-test-token"), "notion-test-token"), true);
});
Deno.test("rejects mutated and reserialized payload despite unchanged metadata", async () => {
  const raw = JSON.stringify(event);
  const header = await sign(raw, "notion-test-token");
  eq(await verifyNotionSignature(raw + " ", header, "notion-test-token"), false);
  eq(await verifyNotionSignature(raw.replace("content_updated", "deleted"), header, "notion-test-token"), false);
});
Deno.test("rejects wrong token, unsigned request, short and malformed signature", async () => {
  const raw = JSON.stringify(event);
  const header = await sign(raw, "notion-test-token");
  for (const candidate of [null, "", "sha256=xyz", header.slice(0, -2)]) {
    eq(await verifyNotionSignature(raw, candidate, "notion-test-token"), false);
  }
  eq(await verifyNotionSignature(raw, header, "wrong-token"), false);
  eq(await verifyNotionSignature(raw, header, ""), false);
});
Deno.test("normalizes metadata only and preserves unique Notion event identity", () => {
  const row = verifiedEventToIngestRow(event);
  eq(row.source_type, "notion");
  eq(row.owner_key, "duilio");
  eq(row.external_id, "notion:" + event.id);
  eq(row.event_type, "page.content_updated");
  eq(row.occurred_at, event.timestamp);
  eq(row.metadata.signature_verified, true);
  if (row.content.includes("verification_token")) throw Error("secret field leaked into memory event");
});
Deno.test("rejects malformed or non-Notion events", () => {
  for (const invalid of [null, {}, { ...event, id: "bad-id" },
    { ...event, entity: { id: "bad" } }, { ...event, timestamp: "invalid" }]) {
    let thrown = false;
    try { verifiedEventToIngestRow(invalid); } catch { thrown = true; }
    eq(thrown, true);
  }
});
