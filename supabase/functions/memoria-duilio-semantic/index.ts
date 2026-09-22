import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabase = createClient(supabaseUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const embeddingSession = new Supabase.ai.Session("gte-small");

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-memory-sync-token, x-memory-ui-token, x-memory-capture-token",
  "access-control-allow-methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });

const clampLimit = (value: unknown, fallback = 50) =>
  Math.min(Math.max(Number(value ?? fallback) || fallback, 1), 100);

const isServiceRequest = (req: Request) => {
  if (!serviceKey) return false;
  const apikey = req.headers.get("apikey") ?? "";
  const bearer = (req.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  return apikey === serviceKey || bearer === serviceKey;
};

const capabilityHeader = (req: Request, capability: string) => {
  if (capability === "sync") return req.headers.get("x-memory-sync-token") ?? "";
  if (capability === "search") return req.headers.get("x-memory-ui-token") ?? "";
  if (capability === "capture") return req.headers.get("x-memory-capture-token") ?? "";
  return "";
};

const authorized = async (req: Request, capability: string) => {
  if (isServiceRequest(req)) return true;
  const token = capabilityHeader(req, capability);
  if (!token) return false;
  const { data, error } = await supabase.rpc("memory_verify_capability_token", {
    p_capability: capability,
    p_token: token,
  });
  return !error && data === true;
};

const embed = async (input: string) =>
  await embeddingSession.run(input, { mean_pool: true, normalize: true });

const embedChunks = async (limit: number) => {
  const { data, error } = await supabase
    .from("memory_chunks")
    .select("memory_item_id,chunk_index,content")
    .is("embedding", null)
    .limit(limit);
  if (error) throw error;

  let completed = 0;
  for (const chunk of data ?? []) {
    const vector = await embed(String(chunk.content ?? ""));
    const updated = await supabase
      .from("memory_chunks")
      .update({
        embedding: vector,
        embedding_model: "gte-small",
        embedding_dimensions: 384,
      })
      .eq("memory_item_id", chunk.memory_item_id)
      .eq("chunk_index", chunk.chunk_index);
    if (updated.error) throw updated.error;
    completed += 1;
  }
  return completed;
};

const embedLearning = async (limit: number) => {
  let completed = 0;
  const { data: experiences, error: experienceError } = await supabase
    .from("memory_experiences")
    .select("id,problem_type,context,solution")
    .is("embedding", null)
    .limit(limit);
  if (experienceError) throw experienceError;

  for (const experience of experiences ?? []) {
    const vector = await embed(
      [experience.problem_type, experience.context, experience.solution]
        .filter(Boolean)
        .join("\n"),
    );
    const updated = await supabase
      .from("memory_experiences")
      .update({
        embedding: vector,
        embedding_model: "gte-small",
        embedding_dimensions: 384,
      })
      .eq("id", experience.id);
    if (updated.error) throw updated.error;
    completed += 1;
  }

  const remaining = Math.max(0, limit - completed);
  if (remaining > 0) {
    const { data: knowledge, error: knowledgeError } = await supabase
      .from("memory_knowledge")
      .select("id,problem_type,title,statement")
      .is("embedding", null)
      .neq("status", "deprecated")
      .limit(remaining);
    if (knowledgeError) throw knowledgeError;

    for (const item of knowledge ?? []) {
      const vector = await embed(
        [item.problem_type, item.title, item.statement]
          .filter(Boolean)
          .join("\n"),
      );
      const updated = await supabase
        .from("memory_knowledge")
        .update({
          embedding: vector,
          embedding_model: "gte-small",
          embedding_dimensions: 384,
        })
        .eq("id", item.id);
      if (updated.error) throw updated.error;
      completed += 1;
    }
  }
  return completed;
};

const runSync = async (limit: number) => {
  const promoted = await supabase.rpc("memory_promote_pending_ingest_events", {
    p_limit: limit,
  });
  if (promoted.error) throw promoted.error;

  const learned = await supabase.rpc("memory_learn_pending_experiences", {
    p_limit: limit,
  });
  if (learned.error) throw learned.error;

  const rules = await supabase.rpc("memory_reinforce_pending_rules", {
    p_owner_key: "duilio",
    p_limit: limit,
  });
  if (rules.error) throw rules.error;

  const affect = await supabase.rpc("memory_process_affect_and_affinity", {
    p_limit: limit,
  });
  if (affect.error) throw affect.error;

  const chunksEmbedded = await embedChunks(limit);
  const learningEmbedded = await embedLearning(limit);

  return {
    promoted: promoted.data,
    learned: learned.data,
    rules_reinforced: rules.data,
    affect: affect.data,
    chunks_embedded: chunksEmbedded,
    learning_embedded: learningEmbedded,
  };
};

const sanitizeMetadata = (value: unknown) => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const blocked = new Set([
    "password",
    "passwords",
    "token",
    "tokens",
    "secret",
    "secrets",
    "api_key",
    "apikey",
    "authorization",
    "credential",
    "credentials",
    "private_key",
    "service_role",
  ]);
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).filter(
      ([key]) => !blocked.has(key.toLowerCase()),
    ),
  );
};

const credentialPattern =
  /(-----BEGIN [A-Z ]*PRIVATE KEY-----|\bsk-[A-Za-z0-9_-]{20,}|\bsb_secret_[A-Za-z0-9_-]{16,}|\bBearer\s+[A-Za-z0-9._~-]{20,}|\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})/i;

const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((part) => part.toString(16).padStart(2, "0"))
    .join("");
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  try {
    const body = await req.json().catch(() => ({}));
    const action = String(
      body.action ?? (body.query ? "search" : "learning_sync"),
    ).toLowerCase();

    if (action === "health") {
      return json({ status: "ok", version: 11, phase: 6 });
    }

    if (action === "sync" || action === "learning_sync") {
      if (!(await authorized(req, "sync"))) return json({ error: "unauthorized" }, 401);
      const result = await runSync(clampLimit(body.limit));
      return json({ action, ...result });
    }

    if (action === "daily") {
      if (!(await authorized(req, "sync"))) return json({ error: "unauthorized" }, 401);
      const daily = await supabase.rpc("memory_run_daily_consolidation", {
        p_owner_key: "duilio",
        p_day: body.day ?? null,
      });
      if (daily.error) throw daily.error;
      return json({ action, result: daily.data });
    }

    if (action === "project_health" || action === "resume" || action === "snapshot") {
      if (!(await authorized(req, "search"))) return json({ error: "unauthorized" }, 401);
      const rpc = action === "project_health" ? "memory_project_health" : action === "resume" ? "memory_resume_project" : "memory_phase6_snapshot";
      if (action === "resume" && !body.project_key) return json({ error: "project_key required" }, 400);
      const args = action === "resume" ? {p_owner_key: "duilio", p_project_key: String(body.project_key)} : {p_owner_key: "duilio"};
      const result = await supabase.rpc(rpc, args);
      if (result.error) throw result.error;
      return json({action, result: result.data});
    }


    if (action === "mark_used") {
      if (!(await authorized(req, "search"))) return json({ error: "unauthorized" }, 401);
      const rawIds = Array.isArray(body.memory_item_ids) ? body.memory_item_ids : [];
      const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      const ids = [...new Set(rawIds.map((id: unknown) => String(id ?? "").trim()).filter((id: string) => uuidPattern.test(id)))];
      if (!ids.length) return json({ action, marked_count: 0, marked: [] });

      let projectId: string | null = body.project_id ? String(body.project_id) : null;
      if (!projectId && body.project_key) {
        const project = await supabase
          .from("memory_projects")
          .select("id")
          .eq("owner_key", "duilio")
          .eq("project_key", String(body.project_key))
          .eq("status", "active")
          .maybeSingle();
        if (project.error) throw project.error;
        if (!project.data) return json({ error: "project not found" }, 404);
        projectId = project.data.id;
      }

      const marked = await supabase.rpc("fn_mark_memory_used", {
        p_memory_item_ids: ids,
        p_owner_key: "duilio",
        p_actor: String(body.actor ?? "n8n").slice(0, 80),
        p_action: String(body.usage_action ?? "used_in_response").slice(0, 120),
        p_project_id: projectId,
      });
      if (marked.error) throw marked.error;

      return json({
        action,
        requested_count: ids.length,
        marked_count: marked.data?.length ?? 0,
        marked: marked.data ?? [],
        project_id: projectId,
      });
    }

    if (action === "project_memories") {
      if (!(await authorized(req, "search"))) return json({error:"unauthorized"},401);
      const key=String(body.project_key ?? "");
      if (!key) return json({error:"project_key required"},400);
      const project=await supabase.from("memory_projects").select("id").eq("owner_key","duilio").eq("project_key",key).eq("status","active").maybeSingle();
      if(project.error) throw project.error;
      if(!project.data) return json({error:"project not found"},404);
      const offset=Math.max(0,Math.floor(Number(body.offset)||0));
      let query=supabase.from("memory_items").select("id,title,content,created_at",{count:"exact"}).eq("owner_key","duilio").eq("project_id",project.data.id).eq("status","active").neq("category","trello_card");
      const importantTypes=["decision","preference","rule","architecture","lesson","specification","goal","security","profile","system_capability"];
      query=body.kind==="history"?query.not("memory_type","in","("+importantTypes.join(",")+")"):query.in("memory_type",importantTypes);
      const result=await query.order("created_at",{ascending:false}).order("id").range(offset,offset+49);
      if(result.error) throw result.error;
      return json({memories:result.data,total:result.count,next_offset:offset+(result.data?.length??0)<(result.count??0)?offset+(result.data?.length??0):null});
    }


    if (action === "tasks") {
      if (!(await authorized(req,"search"))) return json({error:"unauthorized"},401);
      const result=await supabase.from("memory_items").select("id,title,content,metadata").eq("owner_key","duilio").eq("status","active").eq("category","trello_card").order("title").limit(1000);
      if(result.error) throw result.error;
      const project=await supabase.from("memory_projects").select("metadata").eq("owner_key","duilio").eq("project_key","memoria-duilio").single();
      if(project.error) throw project.error;
      return json({tasks:(result.data??[]).map(m=>({id:m.id,title:m.title,description:m.content,url:m.metadata?.card_url,state:m.metadata?.list_name??"Sin lista",updated_at:m.metadata?.last_activity_at})),synced_at:project.data?.metadata?.trello_sync?.last_sync_at??null,source:"trello_snapshot"});
    }

    if (action === "projects") {
      if (!(await authorized(req, "search"))) return json({ error: "unauthorized" }, 401);
      const projects = await supabase.from("memory_projects")
        .select("id,project_key,project_name,capture_mode,connector_status,auto_capture_enabled,last_memory_at")
        .eq("owner_key", "duilio").eq("status", "active").order("project_name");
      if (projects.error) throw projects.error;
      const ids = (projects.data ?? []).map(p => p.id);
      const connectors = ids.length ? await supabase.from("memory_project_connectors")
        .select("project_id,connector_type,connector_name,status,automatic,last_event_at").in("project_id", ids)
        : { data: [], error: null };
      if (connectors.error) throw connectors.error;
      const items = await supabase.from("memory_items").select("project_id").eq("owner_key", "duilio").eq("status", "active");
      if (items.error) throw items.error;
      const executions = await supabase.rpc("memory_execution_overview");
      if (executions.error) throw executions.error;
      // Never send lease tokens or raw project metadata to the browser.
      const executionMap = new Map((executions.data ?? []).map((p: {project_key: string; runs: Array<Record<string, unknown>>}) => [
        p.project_key, p.runs.map(r => ({
          id: r.id, card_url: r.card_url, executor: r.executor,
          state: r.observed_state, last_action: r.last_action, result: r.result,
          blockers: r.blockers, evidence: r.evidence, version: r.version,
          started_at: r.started_at, heartbeat_at: r.heartbeat_at,
          lease_until: r.lease_until, finished_at: r.finished_at,
        })),
      ]));
      const visibleProjects = (projects.data ?? []).map(p => ({
        ...p,
        memory_count: (items.data ?? []).filter(i => i.project_id === p.id).length,
        connectors: (connectors.data ?? []).filter(c => c.project_id === p.id),
        executions: executionMap.get(p.project_key) ?? [],
      }));
      return json({
        ok: true,
        projects: visibleProjects,
        data: visibleProjects,
        result: visibleProjects,
        totals: { projects: ids.length, memories: items.data?.length ?? 0,
          global_memories: (items.data ?? []).filter(i => !i.project_id).length },
        as_of: new Date().toISOString(),
      });
    }

    if (action === "verify_experience") {
      // Capture/search credentials cannot certify their own assertions.
      if (!isServiceRequest(req)) return json({error: "service verification required"}, 403);
      const result = await supabase.rpc("memory_record_verification", {
        p_experience_id: body.experience_id, p_source_ref: body.source_ref,
        p_test_key: body.test_key, p_result: body.result, p_evidence: body.evidence,
        p_verified_by: body.verified_by, p_tested_at: body.tested_at ?? new Date().toISOString(),
      });
      if (result.error) throw result.error;
      return json({action, verification_id: result.data});
    }

    if (action === "search" || action === "learning_search") {
      if (!(await authorized(req, "search"))) return json({ error: "unauthorized" }, 401);
      const query = String(body.query ?? "").trim();
      if (!query) return json({ error: "query required" }, 400);
      let resolvedProjectId: string | null = null;
      let resolvedProjectKey: string | null = null;
      if (body.project_id || body.project_key) {
        let lookup = supabase.from("memory_projects").select("id,project_key").eq("owner_key", "duilio").eq("status", "active");
        if (body.project_id) lookup = lookup.eq("id", body.project_id);
        if (body.project_key) lookup = lookup.eq("project_key", body.project_key);
        const project = await lookup.maybeSingle();
        if (project.error) return json({error: "invalid project scope"}, 400);
        if (!project.data) return json({error: "project not found or scope mismatch"}, 404);
        resolvedProjectId = project.data.id;
        resolvedProjectKey = project.data.project_key;
      }
      await embedChunks(20);
      await embedLearning(20);
      const vector = await embed(query);
      const count = Math.min(Math.max(Number(body.limit ?? 10), 1), 30);

      const knowledge = await supabase.rpc("memory_match_knowledge", {
        query_embedding: vector,
        p_owner_key: "duilio",
        p_project_id: resolvedProjectId,
        match_threshold: Number(body.learning_threshold ?? 0.45),
        match_count: count,
      });
      if (knowledge.error) throw knowledge.error;

      if (action === "learning_search") {
        const logged = await supabase.from("memory_retrieval_events").insert({owner_key:"duilio",project_id:resolvedProjectId,action,result_count:(knowledge.data ?? []).length});
        if (logged.error) throw logged.error;
        return json({ action, query, results: knowledge.data ?? [], interpretation: "Candidate and review entries are not validated procedures." });
      }

      const memories = resolvedProjectKey
        ? await supabase.rpc("memory_match_project_chunks", {
            query_embedding: vector,
            match_threshold: Number(body.threshold ?? 0.45),
            match_count: count,
            filter_category: body.category ?? null,
            filter_project_key: resolvedProjectKey,
          })
        : await supabase.rpc("memory_match_chunks", {
            query_embedding: vector,
            match_threshold: Number(body.threshold ?? 0.45),
            match_count: count,
            filter_category: body.category ?? null,
          });
      if (memories.error) throw memories.error;

      const ids = [...new Set((memories.data ?? []).map((m: {memory_item_id:string}) => m.memory_item_id))];
      const details = ids.length ? await supabase.from("memory_items").select("id,claim_state,verification_id,valid_from,valid_until,subject_key,updated_at").in("id",ids) : {data:[],error:null};
      if (details.error) throw details.error;
      const detailMap = new Map((details.data ?? []).map((m) => [m.id,m]));
      const logged = await supabase.from("memory_retrieval_events").insert({owner_key:"duilio",project_id:resolvedProjectId,action,result_count:(memories.data ?? []).length});
      if (logged.error) throw logged.error;
      return json({
        action,
        query,
        interpretation: "Only claim_state=verified certifies a recorded successful test; recorded/requested/executed do not certify completion.",
        results: (memories.data ?? []).map((m: {memory_item_id:string}) => ({...m,...detailMap.get(m.memory_item_id)})),
        learned: knowledge.data ?? [],
      });
    }

    if (action === "capture") {
      if (!(await authorized(req, "capture"))) return json({ error: "unauthorized" }, 401);
      const projectKey = String(body.project_key ?? "").trim();
      const title = String(body.title ?? "").trim();
      const content = String(body.content ?? "").trim();
      const sourceType = String(body.source_type ?? "chatgpt").trim();
      const sourceName = String(body.source_name ?? "work-session").trim();
      const eventType = String(body.event_type ?? "project_activity").trim();

      if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(projectKey) || projectKey.length > 80) {
        return json({ error: "invalid project_key" }, 400);
      }
      if (!title || !content) return json({ error: "title and content are required" }, 400);
      if (credentialPattern.test(`${title}\n${content}\n${body.summary ?? ""}`)) {
        return json({ error: "sensitive credential-like content rejected" }, 400);
      }

      const externalId = String(
        body.external_id ??
          `work:${await sha256(`${projectKey}|${eventType}|${title}|${content}`)}`,
      ).slice(0, 240);
      const row = {
        owner_key: "duilio",
        project_key: projectKey,
        project_name: String(body.project_name ?? projectKey).trim().slice(0, 160),
        source_type: sourceType.slice(0, 40),
        source_name: sourceName.slice(0, 160),
        external_id: externalId,
        event_type: eventType.slice(0, 80),
        title: title.slice(0, 300),
        content: content.slice(0, 12000),
        summary: body.summary ? String(body.summary).slice(0, 2000) : null,
        source_url: body.source_url ? String(body.source_url).slice(0, 2000) : null,
        category: String(body.category ?? "project_activity").slice(0, 100),
        memory_type: String(body.memory_type ?? "observation").slice(0, 100),
        importance: Math.min(Math.max(Number(body.importance ?? 6), 1), 10),
        occurred_at: body.occurred_at ?? new Date().toISOString(),
        metadata: sanitizeMetadata(body.metadata),
      };
      if ((row.metadata as Record<string, unknown>).claim_state === "verified") return json({error:"capture cannot verify"},400);
      const captured = await supabase.rpc("memory_capture_v6", {p_event: row});
      if (captured.error) return json({error: captured.error.message},409);
      if (captured.data?.status !== "processed") return json({action,captured:captured.data},422);
      return json({ action, captured: captured.data }, captured.data?.duplicate ? 200 : 201);
    }

    return json({ error: "unsupported action" }, 400);
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
