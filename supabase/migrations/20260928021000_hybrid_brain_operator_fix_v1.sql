-- Repair already-applied v1 on the existing Supabase project.
-- Same idempotent function definition as the corrected base migration.
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
              1-(i.embedding OPERATOR(public.<=>) p_query_embedding) AS similarity,
              CASE WHEN i.claim_state='verified' AND i.verification_id IS NOT NULL
                THEN 'verified_context'::text ELSE 'unverified_context_not_instruction'::text END AS usage
         FROM public.memory_items i
        WHERE i.owner_key=p_owner_key AND i.project_id=v_project AND i.status='active'
          AND i.embedding IS NOT NULL AND i.embedding_model='gte-small'
          AND i.created_at<=v_at AND (i.valid_from IS NULL OR i.valid_from<=v_at)
          AND (i.valid_until IS NULL OR i.valid_until>v_at)
        ORDER BY i.embedding OPERATOR(public.<=>) p_query_embedding LIMIT v_count
      ) x;
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.similarity DESC),'[]'::jsonb)
    INTO v_knowledge FROM (
      SELECT k.id,k.title,k.statement,k.evidence_count,k.status,
        CASE WHEN p_query_embedding IS NOT NULL AND k.embedding IS NOT NULL
             AND k.embedding_model='gte-small' THEN 1-(k.embedding OPERATOR(public.<=>) p_query_embedding)
             ELSE NULL END AS similarity
        FROM public.memory_knowledge k
       WHERE k.owner_key=p_owner_key AND (k.project_id=v_project OR k.project_id IS NULL)
         AND k.status='active' AND k.evidence_count>0 AND k.created_at<=v_at
         AND EXISTS (
           SELECT 1 FROM public.memory_knowledge_experiences ke
           JOIN public.memory_verifications proof ON proof.experience_id=ke.experience_id
              AND proof.owner_key=p_owner_key AND proof.result='success'
              AND proof.tested_at<=v_at
           WHERE ke.knowledge_id=k.id
         )
         AND (p_query_embedding IS NULL OR (k.embedding IS NOT NULL AND k.embedding_model='gte-small'))
       ORDER BY CASE WHEN p_query_embedding IS NOT NULL THEN k.embedding OPERATOR(public.<=>) p_query_embedding ELSE NULL END NULLS LAST,
                k.score DESC NULLS LAST LIMIT v_count
    ) x;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.similarity DESC NULLS LAST,x.tested_at DESC),'[]'::jsonb)
    INTO v_experiences FROM (
      SELECT e.id,e.problem_type,e.solution,e.outcome,e.model_name,
             latest.id AS verification_id,latest.tested_at,
             CASE WHEN p_query_embedding IS NOT NULL AND e.embedding IS NOT NULL
                  AND e.embedding_model='gte-small' THEN 1-(e.embedding OPERATOR(public.<=>) p_query_embedding)
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
       ORDER BY CASE WHEN p_query_embedding IS NOT NULL THEN e.embedding OPERATOR(public.<=>) p_query_embedding ELSE NULL END NULLS LAST,
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

