-- 20260922143832_memory_execution_learning_loop_v2
-- Queue -> execution_run -> experience -> verification -> knowledge.

create or replace function public.memory_execution_to_experience(p_run_id uuid)
returns uuid
language plpgsql
set search_path to ''
as $function$
declare
  r public.memory_execution_runs%rowtype;
  p public.memory_projects%rowtype;
  v_id uuid;
  v_outcome text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_run_id::text,31));
  select * into r from public.memory_execution_runs where id=p_run_id;
  if not found then raise exception 'execution_run_not_found'; end if;
  if r.state='running' then return null; end if;
  select * into p from public.memory_projects where id=r.project_id;
  select id into v_id from public.memory_experiences
   where metadata->>'execution_run_id'=p_run_id::text limit 1;
  if v_id is not null then return v_id; end if;
  v_outcome := case r.state
    when 'completed' then 'success'
    when 'failed' then 'failure'
    when 'partial' then 'partial'
    when 'blocked' then 'partial'
    else 'unknown'
  end;
  insert into public.memory_experiences(
    owner_key,project_id,problem_type,context,solution,model_name,outcome,
    quality_score,confidence,evidence,metadata,occurred_at,learning_status
  )
  values(
    coalesce(p.owner_key,'duilio'),r.project_id,'execution:'||coalesce(r.run_key,'run'),
    concat_ws(E'\n','Proyecto: '||coalesce(p.project_name,'desconocido'),'Ejecutor: '||coalesce(r.executor,'desconocido'),'Acción: '||coalesce(r.last_action,'')),
    coalesce(nullif(r.result,''),r.last_action,'Sin resultado registrado'),r.executor,v_outcome,
    case when r.state='completed' then 0.8 when r.state='partial' then 0.5 when r.state='blocked' then 0.4 when r.state='failed' then 0.2 else 0.4 end,
    0.6,coalesce(r.evidence,'[]'::jsonb),
    jsonb_build_object('execution_run_id',r.id,'run_key',r.run_key,'card_url',r.card_url,'state',r.state,'version',r.version,'blockers',r.blockers),
    coalesce(r.finished_at,r.heartbeat_at,r.started_at,now()),'pending'
  ) returning id into v_id;
  return v_id;
end
$function$;

create or replace function public.memory_queue_claim_v2(p_executor_key text,p_worker_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_claim jsonb;
  q public.memory_execution_queue%rowtype;
  p public.memory_projects%rowtype;
  v_run jsonb;
  v_run_id uuid;
begin
  v_claim := public.memory_queue_claim(p_executor_key,p_worker_id);
  if coalesce((v_claim->>'claimed')::boolean,false)=false then
    return v_claim || jsonb_build_object('protocol','queue_run_v2');
  end if;
  select * into q from public.memory_execution_queue
   where id=(v_claim->'job'->>'id')::uuid for update;
  select * into p from public.memory_projects where id=q.project_id;
  v_run := public.memory_execution_claim(
    p.project_key,
    coalesce(nullif(q.card_url,''),'queue:'||q.id::text),
    'queue:'||q.id::text,
    q.executor_key,
    left('Queue claim — '||q.task_text,500),
    jsonb_build_array(jsonb_build_object('type','queue_claim','queue_id',q.id,'decision_id',q.decision_id))
  );
  if coalesce((v_run->>'claimed')::boolean,false)=false
     and coalesce((v_run->>'duplicate')::boolean,false)=false then
    update public.memory_execution_queue
       set state='ready',claimed_by=null,claimed_at=null,updated_at=clock_timestamp(),
           metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('run_claim_blocked',v_run)
     where id=q.id;
    update public.memory_orchestrator_decisions
       set status='queued',updated_at=clock_timestamp()
     where id=q.decision_id;
    return jsonb_build_object('ok',false,'claimed',false,'reason','execution_run_not_claimed','queue_id',q.id,'run',v_run,'protocol','queue_run_v2');
  end if;
  v_run_id := (v_run->>'run_id')::uuid;
  update public.memory_execution_queue
     set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('execution_run_id',v_run_id,'protocol','queue_run_v2'),
         updated_at=clock_timestamp()
   where id=q.id;
  return v_claim || jsonb_build_object('execution_run_id',v_run_id,'protocol','queue_run_v2');
end
$function$;

create or replace function public.memory_queue_update_v2(
  p_queue_id uuid,p_worker_id text,p_state text,p_action text,
  p_result jsonb default null,p_evidence jsonb default '[]'::jsonb,
  p_blockers jsonb default '[]'::jsonb,p_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  q public.memory_execution_queue%rowtype;
  r public.memory_execution_runs%rowtype;
  v_queue jsonb;
  v_run jsonb;
  v_result_text text;
begin
  select * into q from public.memory_execution_queue where id=p_queue_id for update;
  if not found then raise exception 'unknown queue job'; end if;
  if q.claimed_by is distinct from p_worker_id then raise exception 'worker mismatch'; end if;
  if coalesce(q.metadata->>'execution_run_id','')='' then raise exception 'queue has no execution run'; end if;
  select * into r from public.memory_execution_runs
   where id=(q.metadata->>'execution_run_id')::uuid for update;
  if not found then raise exception 'execution run missing'; end if;
  v_result_text := case
    when p_result is null then null
    when jsonb_typeof(p_result)='string' then trim(both '"' from p_result::text)
    when coalesce(p_result->>'summary','')<>'' then p_result->>'summary'
    when coalesce(p_result->>'result','')<>'' then p_result->>'result'
    else p_result::text
  end;
  v_queue := public.memory_queue_update(p_queue_id,p_worker_id,p_state,p_result,p_evidence,p_blockers);
  v_run := public.memory_execution_update(r.id,r.lease_token,p_state,p_action,v_result_text,p_evidence,p_blockers,p_version);
  return jsonb_build_object('ok',true,'queue',v_queue,'run',v_run,'protocol','queue_run_v2');
end
$function$;

create or replace function public.memory_queue_verify_and_learn(
  p_queue_id uuid,p_test_key text,p_result text,p_evidence jsonb,p_verified_by text,p_source_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  q public.memory_execution_queue%rowtype;
  v_run_id uuid;
  v_learning jsonb;
begin
  if p_result not in ('success','failure','partial') then
    raise exception 'verification result must be success, failure or partial';
  end if;
  select * into q from public.memory_execution_queue where id=p_queue_id;
  if not found then raise exception 'unknown queue job'; end if;
  if coalesce(q.metadata->>'execution_run_id','')='' then raise exception 'queue has no execution run'; end if;
  v_run_id := (q.metadata->>'execution_run_id')::uuid;
  v_learning := public.memory_verify_execution_and_learn(
    v_run_id,p_test_key,p_result,p_evidence,p_verified_by,
    coalesce(nullif(p_source_ref,''),nullif(q.card_url,''),'queue:'||q.id::text)
  );
  update public.memory_execution_queue
     set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
       'verified_at',clock_timestamp(),'verification_result',p_result,'learning',v_learning
     ),
     updated_at=clock_timestamp()
   where id=q.id;
  return jsonb_build_object('ok',true,'queue_id',q.id,'run_id',v_run_id,'learning',v_learning);
end
$function$;
