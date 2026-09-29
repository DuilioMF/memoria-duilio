-- Run after applying 20260928015000_hybrid_brain_v1.sql, as service_role.
-- Read-only assertions and one negative (rejected) transition. Never invent verification.
BEGIN;
DO $smoke$
DECLARE v jsonb; v_prior jsonb; v_vec vector; v_bad boolean:=false;
BEGIN
  v:=public.memory_brain_hybrid_v1('Revisar medios de pago','memoria-duilio','duilio',NULL,5,now(),'sql-server');
  IF v->>'status'<>'ok' OR v->>'retrieval_mode'<>'text_graph_fallback'
     OR v->>'version'<>'hybrid-v1' THEN RAISE EXCEPTION 'text/graph fallback failed: %',v; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v->'text_context') hit
    JOIN public.memory_items item ON item.id=(hit->>'id')::uuid
    WHERE item.owner_key IS DISTINCT FROM 'duilio' OR item.project_id IS DISTINCT FROM
      (SELECT id FROM public.memory_projects
        WHERE project_key='memoria-duilio' AND owner_key='duilio' LIMIT 1)
  ) THEN RAISE EXCEPTION 'project-scoped text retrieval leaked another project'; END IF;
  IF v->'specialists'->>'dispatch_authorized'<>'false' THEN
    RAISE EXCEPTION 'router must never self-dispatch'; END IF;
  v_prior:=public.memory_graph_context_at_v1('duilio','memoria-duilio',now(),2);
  IF jsonb_typeof(v_prior->'nodes')<>'array'
     OR jsonb_typeof(v_prior->'edges')<>'array' THEN
    RAISE EXCEPTION 'temporal graph malformed'; END IF;
  v:=public.memory_brain_hybrid_v1('medios de pago','unknown-project-zz','duilio',NULL,5);
  IF v->>'status'<>'unresolved_scope'
      OR jsonb_array_length(v->'verified_knowledge')<>0 THEN
    RAISE EXCEPTION 'project isolation failed'; END IF;
  v:=public.memory_specialist_candidates_v1('sql-server','memoria-duilio','duilio',15);
  IF v->>'dispatch_authorized'<>'false' THEN
    RAISE EXCEPTION 'candidates must not bypass canonical router'; END IF;
  SELECT e.embedding INTO v_vec FROM public.memory_experiences e
    WHERE e.owner_key='duilio' AND e.embedding_model='gte-small'
      AND e.embedding IS NOT NULL LIMIT 1;
  IF v_vec IS NOT NULL THEN
    v:=public.memory_brain_hybrid_v1('Experiencia anterior','memoria-duilio','duilio',v_vec,5);
    IF v->>'retrieval_mode'<>'text_graph_vector' THEN
      RAISE EXCEPTION 'hybrid vector mode failed: %',v; END IF;
  END IF;
  BEGIN
    PERFORM public.memory_transition_relation_v1(
      'duilio','00000000-0000-0000-0000-000000000000'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid);
  EXCEPTION WHEN OTHERS THEN v_bad:=true;
  END;
  IF NOT v_bad THEN RAISE EXCEPTION 'relation transition accepted invalid evidence'; END IF;
  IF has_function_privilege('anon','public.memory_brain_hybrid_v1(text,text,text,vector,integer,timestamptz,text)','EXECUTE')
      OR has_function_privilege('authenticated','public.memory_specialist_candidates_v1(text,text,text,integer)','EXECUTE')
      OR has_table_privilege('anon','public.memory_executor_specialty_evidence','SELECT')
  THEN RAISE EXCEPTION 'unexpected client privilege'; END IF;
  RAISE NOTICE 'PASS hybrid-v1: scoped fallback, history, specialist safety, vector, negative transition, privileges';
END $smoke$;
ROLLBACK;
