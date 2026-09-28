-- MD hybrid brain v1: additive only; legacy brain_router and graph stay unchanged.
-- Project-scoped, service_role-only APIs. No synthetic verification or automatic closing.
CREATE OR REPLACE FUNCTION public.memory_graph_context_at_v1(
  p_owner_key text, p_project_key text,
  p_at timestamptz DEFAULT now(), p_depth integer DEFAULT 2
) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = '' AS $fn$
DECLARE
  v_root uuid;
  v_at timestamptz := coalesce(p_at,now());
  v_depth integer := least(greatest(coalesce(p_depth,2),1),3);
  v_out jsonb;
BEGIN
  IF nullif(btrim(p_project_key),'') IS NULL THEN
    RETURN jsonb_build_object('root',null,'nodes','[]'::jsonb,'edges','[]'::jsonb,
                              'reason','project_required','as_of',v_at);
  END IF;
  SELECT e.id INTO v_root FROM public.memory_entities e
   WHERE e.owner_key=p_owner_key AND e.external_ids->>'project_key'=p_project_key
     AND e.created_at<=v_at
   ORDER BY e.created_at DESC LIMIT 1;
  IF v_root IS NULL THEN
    RETURN jsonb_build_object('root',null,'nodes','[]'::jsonb,'edges','[]'::jsonb,
                              'reason','project_not_found','as_of',v_at);
  END IF;
  WITH RECURSIVE walk(entity_id,depth,path) AS (
    SELECT v_root,0,ARRAY[v_root]::uuid[]
    UNION ALL
    SELECT CASE WHEN r.source_entity_id=w.entity_id THEN r.target_entity_id ELSE r.source_entity_id END,
           w.depth+1,
           w.path || CASE WHEN r.source_entity_id=w.entity_id THEN r.target_entity_id ELSE r.source_entity_id END
      FROM walk w
      JOIN public.memory_relations r ON r.owner_key=p_owner_key
       AND (r.source_entity_id=w.entity_id OR r.target_entity_id=w.entity_id)
       AND r.created_at<=v_at AND (r.valid_from IS NULL OR r.valid_from<=v_at)
       AND (r.valid_until IS NULL OR r.valid_until>v_at)
     WHERE w.depth<v_depth
       AND NOT (CASE WHEN r.source_entity_id=w.entity_id THEN r.target_entity_id ELSE r.source_entity_id END=ANY(w.path))
  ), ids AS (SELECT DISTINCT entity_id FROM walk),
  nodes AS (
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'name',e.canonical_name,
      'type',e.entity_type) ORDER BY e.canonical_name),'[]'::jsonb) j
      FROM public.memory_entities e JOIN ids i ON i.entity_id=e.id
     WHERE e.owner_key=p_owner_key AND e.created_at<=v_at
  ), edges AS (
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,
      'source_id',r.source_entity_id,'target_id',r.target_entity_id,
      'relation',r.relation_type,'confidence',r.confidence,
      'source_item_id',r.memory_item_id,
      'valid_from',r.valid_from,'valid_until',r.valid_until)
      ORDER BY r.created_at),'[]'::jsonb) j
      FROM public.memory_relations r
     WHERE r.owner_key=p_owner_key
       AND r.source_entity_id IN (SELECT entity_id FROM ids)
       AND r.target_entity_id IN (SELECT entity_id FROM ids)
       AND r.created_at<=v_at AND (r.valid_from IS NULL OR r.valid_from<=v_at)
       AND (r.valid_until IS NULL OR r.valid_until>v_at)
  )
  SELECT jsonb_build_object('root',v_root,'depth',v_depth,'as_of',v_at,
       'nodes',nodes.j,'edges',edges.j,'historical_names_available',false)
    INTO v_out FROM nodes,edges;
  RETURN v_out;
END $fn$;

-- A specialty is earned from a real successful verification, never from a claimed skill.
CREATE TABLE IF NOT EXISTS public.memory_executor_specialty_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_key text NOT NULL,
  executor_key text NOT NULL REFERENCES public.memory_executor_registry(executor_key),
  project_key text NULL,
  specialty text NOT NULL CHECK (specialty ~ '^[a-z0-9][a-z0-9_-]{0,79}$'),
  verification_id uuid NOT NULL REFERENCES public.memory_verifications(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NULL,
  UNIQUE (executor_key,specialty,verification_id)
);
ALTER TABLE public.memory_executor_specialty_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.memory_executor_specialty_evidence FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.memory_executor_specialty_evidence TO service_role;

CREATE OR REPLACE FUNCTION public.memory_specialist_candidates_v1(
 p_specialty text,p_project_key text,p_owner_key text DEFAULT 'duilio',
 p_max_health_minutes integer DEFAULT 15
) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = '' AS $fn$
DECLARE v_candidates jsonb;
BEGIN
  IF nullif(btrim(p_specialty),'') IS NULL OR nullif(btrim(p_project_key),'') IS NULL THEN
    RETURN jsonb_build_object('status','missing_scope','eligible','[]'::jsonb,'eligible_count',0);
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.evidence_count DESC,s.executor_key),'[]'::jsonb)
    INTO v_candidates FROM (
      SELECT e.executor_key,e.display_name, lower(btrim(p_specialty)) AS specialty,
             count(DISTINCT ev.verification_id) AS evidence_count, max(v.tested_at) AS last_verified_at
        FROM public.memory_executor_registry e
        JOIN public.memory_executor_specialty_evidence ev ON ev.executor_key=e.executor_key
        JOIN public.memory_verifications v ON v.id=ev.verification_id
         AND v.owner_key=ev.owner_key AND v.result='success'
       WHERE ev.owner_key=p_owner_key AND lower(ev.specialty)=lower(btrim(p_specialty))
         AND (ev.project_key=p_project_key OR ev.project_key IS NULL)
         AND (ev.expires_at IS NULL OR ev.expires_at>now())
         AND e.enabled IS TRUE AND e.automatic IS TRUE AND e.status='ready'
         AND e.last_health_at>=now()-make_interval(mins=>least(greatest(coalesce(p_max_health_minutes,15),1),1440))
       GROUP BY e.executor_key,e.display_name
    ) s;
  RETURN jsonb_build_object('status',CASE WHEN jsonb_array_length(v_candidates)>0
     THEN 'eligible' ELSE 'no_verified_live_specialist' END,
    'eligible',v_candidates,'eligible_count',jsonb_array_length(v_candidates),
    'routing_authority','memory_select_executor_v2','dispatch_authorized',false);
END $fn$;

-- Optional gte-small query vector supplied by the existing semantic Edge Function.
-- Read-only, scoped retrieval; NEVER promotes candidates or dispatches an executor.
CREATE OR REPLACE FUNCTION public.memory_brain_hybrid_v1(
 p_request text,p_project_key text,p_owner_key text DEFAULT 'duilio',
 p_query_embedding vector DEFAULT NULL,p_match_count integer DEFAULT 8,
 p_as_of timestamptz DEFAULT now(),p_specialty text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = '' AS $fn$
DECLARE
 v_base jsonb;
 v_graph jsonb;
 v_items jsonb := '[]'::jsonb;
 v_knowledge jsonb := '[]'::jsonb;
 v_experiences jsonb := '[]'::jsonb;
 v_specialists jsonb := jsonb_build_object('status','not_requested','eligible','[]'::jsonb,'dispatch_authorized',false);
 v_project uuid;
 v_count integer:=least(greatest(coalesce(p_match_count,8),1),12);
 v_at timestamptz:=coalesce(p_as_of,now());
BEGIN
  IF nullif(btrim(p_request),'') IS NULL OR nullif(btrim(p_project_key),'') IS NULL THEN
    RETURN jsonb_build_object('status','invalid_scope','reason','request_and_project_required');
  END IF;
  v_base:=public.memory_brain_router(p_request,p_project_key,p_owner_key);
  IF v_base->'project'->>'project_key' IS DISTINCT FROM p_project_key THEN
    RETURN jsonb_build_object('status','unresolved_scope','project_key',p_project_key,
      'verified_knowledge','[]'::jsonb,'verified_experiences','[]'::jsonb,
      'semantic_memories','[]'::jsonb,'specialists',v_specialists);
  END IF;
  v_project:=(v_base->'project'->>'id')::uuid;
  v_graph:=public.memory_graph_context_at_v1(p_owner_key,p_project_key,v_at,2);
  IF p_query_embedding IS NOT NULL THEN
    SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.similarity DESC),'[]'::jsonb)
      INTO v_items FROM (
       SELECT i.id,i.title,i.category,i.claim_state,i.verification_id,
              1-(i.embedding <=> p_query_embedding) AS similarity,
              'unverified_context_not_instruction'::text AS usage
         FROM public.memory_items i
        WHERE i.owner_key=p_owner_key AND i.project_id=v_project AND i.status='active'
          AND i.embedding IS NOT NULL AND i.embedding_model='gte-small'
          AND i.created_at<=v_at AND (i.valid_from IS NULL OR i.valid_from<=v_at)
          AND (i.valid_until IS NULL OR i.valid_until>v_at)
        ORDER BY i.embedding <=> p_query_embedding LIMIT v_count
      ) x;
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.similarity DESC),'[]'::jsonb)
    INTO v_knowledge FROM (
      SELECT k.id,k.title,k.statement,k.evidence_count,k.status,
        CASE WHEN p_query_embedding IS NOT NULL AND k.embedding IS NOT NULL
             AND k.embedding_model='gte-small' THEN 1-(k.embedding <=> p_query_embedding)
             ELSE NULL END AS similarity
        FROM public.memory_knowledge k
       WHERE k.owner_key=p_owner_key AND (k.project_id=v_project OR k.project_id IS NULL)
         AND k.status='active' AND k.evidence_count>0 AND k.created_at<=v_at
         AND (p_query_embedding IS NULL OR (k.embedding IS NOT NULL AND k.embedding_model='gte-small'))
       ORDER BY CASE WHEN p_query_embedding IS NOT NULL THEN k.embedding <=> p_query_embedding ELSE NULL END NULLS LAST,
                k.score DESC NULLS LAST LIMIT v_count
    ) x;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.similarity DESC NULLS LAST,x.tested_at DESC),'[]'::jsonb)
    INTO v_experiences FROM (
      SELECT e.id,e.problem_type,e.solution,e.outcome,e.model_name,
             latest.id AS verification_id,latest.tested_at,
             CASE WHEN p_query_embedding IS NOT NULL AND e.embedding IS NOT NULL
                  AND e.embedding_model='gte-small' THEN 1-(e.embedding <=> p_query_embedding)
                  ELSE NULL END AS similarity
        FROM public.memory_experiences e
        JOIN LATERAL (
          SELECT v.id,v.result,v.tested_at FROM public.memory_verifications v
           WHERE v.experience_id=e.id AND v.owner_key=p_owner_key AND v.tested_at<=v_at
           ORDER BY v.tested_at DESC,v.recorded_at DESC LIMIT 1
        ) latest ON latest.result='success'
       WHERE e.owner_key=p_owner_key AND e.project_id=v_project
         AND e.occurred_at<=v_at
         AND (p_query_embedding IS NULL OR (e.embedding IS NOT NULL AND e.embedding_model='gte-small'))
       ORDER BY CASE WHEN p_query_embedding IS NOT NULL THEN e.embedding <=> p_query_embedding ELSE NULL END NULLS LAST,
                latest.tested_at DESC LIMIT v_count
    ) x;
  IF nullif(btrim(p_specialty),'') IS NOT NULL THEN
    v_specialists:=public.memory_specialist_candidates_v1(p_specialty,p_project_key,p_owner_key,15);
  END IF;
  RETURN jsonb_build_object(
    'status','ok','version','hybrid-v1','project',v_base->'project',
    'as_of',v_at,'graph_as_of',v_graph,
    'text_context',coalesce(v_base->'retrieved_memory','[]'::jsonb),
    'semantic_memories',v_items,'verified_knowledge',v_knowledge,
    'verified_experiences',v_experiences,'specialists',v_specialists,
    'retrieval_mode',CASE WHEN p_query_embedding IS NULL THEN 'text_graph_fallback' ELSE 'text_graph_vector' END,
    'policy',jsonb_build_object('verified_only_for_actions',true,
      'do_not_execute_from_candidates',true,'no_automatic_closure',true,
      'historical_entity_names_not_snapshotted',true,
      'router_decision_still_authoritative',true));
END $fn$;

-- No public client access to backend-only context or specialist proofs.
REVOKE ALL ON FUNCTION public.memory_graph_context_at_v1(text,text,timestamptz,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.memory_specialist_candidates_v1(text,text,text,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.memory_brain_hybrid_v1(text,text,text,vector,integer,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.memory_graph_context_at_v1(text,text,timestamptz,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.memory_specialist_candidates_v1(text,text,text,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.memory_brain_hybrid_v1(text,text,text,vector,integer,timestamptz,text) TO service_role;
