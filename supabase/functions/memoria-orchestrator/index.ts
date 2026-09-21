import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { "content-type": "application/json" },
});

async function rpc(name: string, payload: Record<string, unknown> = {}) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "apikey": SERVICE_ROLE,
      "authorization": `Bearer ${SERVICE_ROLE}`,
    },
    body: JSON.stringify(payload),
  });
  const text = await r.text();
  let data: unknown = text;
  try { data = text ? JSON.parse(text) : null; } catch {}
  if (!r.ok) throw { status: r.status, data };
  return data;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE) return json({ ok: false, error: "SERVER_NOT_CONFIGURED" }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json({ ok: false, error: "INVALID_JSON" }, 400); }
  const action = String(body?.action || "").trim();

  try {
    if (action === "status") {
      return json(await rpc("memory_orchestrator_payload"));
    }
    if (action === "route") {
      if (!body?.request) return json({ ok:false, error:"REQUEST_REQUIRED" },400);
      return json(await rpc("memory_select_executor_v2", {
        p_request: String(body.request),
        p_project_key: body?.project_key ?? null,
        p_prefer_executor: body?.prefer_executor ?? null,
      }));
    }
    if (action === "orchestrate") {
      if (!body?.request) return json({ ok:false, error:"REQUEST_REQUIRED" },400);
      return json(await rpc("memory_orchestrate_request", {
        p_request: String(body.request),
        p_project_key: body?.project_key ?? null,
        p_card_url: body?.card_url ?? null,
        p_prefer_executor: body?.prefer_executor ?? null,
        p_priority: Number.isInteger(body?.priority) ? body.priority : 50,
      }));
    }
    if (action === "heartbeat") {
      if (!body?.executor_key) return json({ ok:false, error:"EXECUTOR_KEY_REQUIRED" },400);
      return json(await rpc("memory_executor_heartbeat", {
        p_executor_key: String(body.executor_key),
        p_status: body?.status ?? "ready",
        p_metadata: body?.metadata ?? {},
      }));
    }
    if (action === "claim") {
      if (!body?.executor_key || !body?.worker_id) return json({ ok:false, error:"EXECUTOR_AND_WORKER_REQUIRED" },400);
      return json(await rpc("memory_queue_claim", {
        p_executor_key: String(body.executor_key),
        p_worker_id: String(body.worker_id),
      }));
    }
    if (action === "update") {
      if (!body?.queue_id || !body?.worker_id || !body?.state) return json({ ok:false, error:"QUEUE_WORKER_STATE_REQUIRED" },400);
      return json(await rpc("memory_queue_update", {
        p_queue_id: String(body.queue_id),
        p_worker_id: String(body.worker_id),
        p_state: String(body.state),
        p_result: body?.result ?? null,
        p_evidence: Array.isArray(body?.evidence) ? body.evidence : [],
        p_blockers: Array.isArray(body?.blockers) ? body.blockers : [],
      }));
    }
    return json({ ok:false, error:"INVALID_ACTION" },400);
  } catch (e: any) {
    return json({ ok:false, error:e?.data ?? String(e), action }, e?.status ?? 500);
  }
});
