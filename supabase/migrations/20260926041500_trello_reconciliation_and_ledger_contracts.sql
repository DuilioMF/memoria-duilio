-- Permanent Trello state reconciliation and hardened execution/ledger contracts.
-- 2026-09-26

create or replace view public.memory_state_reconciliation_v
with (security_invoker = true) as
select
  e.id,
  e.title,
  e.card_url,
  e.list_name,
  e.state,
  e.executor,
  e.heartbeat_at,
  e.lease_until,
  e.integrity_state,
  case
    when e.list_name = 'En ejecución'
      and not (
        e.state in ('running','claimed')
        and e.heartbeat_at > now() - interval '15 minutes'
        and e.lease_until > now()
      )
      then 'running_without_live_execution'
    when e.list_name <> 'En ejecución'
      and e.state in ('running','claimed')
      and e.heartbeat_at > now() - interval '15 minutes'
      and e.lease_until > now()
      then 'live_execution_outside_running'
    when e.list_name = 'En prueba'
      and upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
      then 'waiting_duilio_outside_waiting_column'
    else 'consistent_or_requires_description_check'
  end as reconciliation_result,
  case
    when e.list_name = 'En ejecución'
      and not (
        e.state in ('running','claimed')
        and e.heartbeat_at > now() - interval '15 minutes'
        and e.lease_until > now()
      )
      and (
        upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
        or upper(coalesce(m.content,'')) like '%ESPERANDO PRUEBA DE DUILIO%'
      )
      then 'MOVE_TO_ESPERA_DE_VOS'
    when e.list_name = 'En ejecución'
      and not (
        e.state in ('running','claimed')
        and e.heartbeat_at > now() - interval '15 minutes'
        and e.lease_until > now()
      )
      then 'MOVE_TO_POR_HACER'
    when e.list_name <> 'En ejecución'
      and e.state in ('running','claimed')
      and e.heartbeat_at > now() - interval '15 minutes'
      and e.lease_until > now()
      then 'MOVE_TO_EN_EJECUCION'
    when e.list_name = 'En prueba'
      and upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
      then 'MOVE_TO_ESPERA_DE_VOS'
    else 'NO_AUTOMATIC_MOVE'
  end as proposed_action,
  case
    when e.list_name = 'En ejecución'
      and not (
        e.state in ('running','claimed')
        and e.heartbeat_at > now() - interval '15 minutes'
        and e.lease_until > now()
      )
      and (
        upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
        or upper(coalesce(m.content,'')) like '%ESPERANDO PRUEBA DE DUILIO%'
      )
      then 'Espera de vos'
    when e.list_name = 'En ejecución'
      and not (
        e.state in ('running','claimed')
        and e.heartbeat_at > now() - interval '15 minutes'
        and e.lease_until > now()
      )
      then 'Por hacer'
    when e.list_name <> 'En ejecución'
      and e.state in ('running','claimed')
      and e.heartbeat_at > now() - interval '15 minutes'
      and e.lease_until > now()
      then 'En ejecución'
    when e.list_name = 'En prueba'
      and upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
      then 'Espera de vos'
    else null
  end as target_list
from public.memory_execution_integrity_v e
join public.memory_items m on m.id=e.id;

create table if not exists public.memory_trello_reconciliation_actions (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  memory_item_id uuid not null references public.memory_items(id) on delete cascade,
  card_url text not null,
  source_list text not null,
  target_list text not null check (target_list in ('Por hacer','En ejecución','En prueba','Espera de vos')),
  reconciliation_result text not null,
  proposed_action text not null,
  run_key text,
  status text not null default 'pending' check (status in ('pending','claimed','applied','failed','superseded')),
  detected_at timestamptz not null default now(),
  claimed_at timestamptz,
  completed_at timestamptz,
  worker_id text,
  evidence jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence)='array'),
  error_message text
);

create unique index if not exists ux_memory_trello_reconciliation_open_card
on public.memory_trello_reconciliation_actions(card_url)
where status in ('pending','claimed');

create index if not exists ix_memory_trello_reconciliation_status
on public.memory_trello_reconciliation_actions(status, detected_at);

alter table public.memory_trello_reconciliation_actions enable row level security;
revoke all on public.memory_trello_reconciliation_actions from public, anon, authenticated;
grant select, insert, update on public.memory_trello_reconciliation_actions to service_role;

create or replace function public.memory_plan_trello_state_reconciliation(
  p_run_key text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_inserted integer;
begin
  insert into public.memory_trello_reconciliation_actions(
    memory_item_id,card_url,source_list,target_list,reconciliation_result,proposed_action,run_key
  )
  select id,card_url,list_name,target_list,reconciliation_result,proposed_action,p_run_key
  from public.memory_state_reconciliation_v
  where proposed_action <> 'NO_AUTOMATIC_MOVE'
    and target_list is not null
    and target_list <> list_name
  on conflict do nothing;

  get diagnostics v_inserted = row_count;

  return jsonb_build_object(
    'ok',true,
    'inserted',v_inserted,
    'pending',coalesce((
      select jsonb_agg(jsonb_build_object(
        'action_id',a.id,
        'memory_item_id',a.memory_item_id,
        'card_url',a.card_url,
        'source_list',a.source_list,
        'target_list',a.target_list,
        'proposed_action',a.proposed_action
      ) order by a.detected_at)
      from public.memory_trello_reconciliation_actions a
      where a.status='pending'
    ),'[]'::jsonb)
  );
end;
$$;

create or replace function public.memory_claim_trello_reconciliation(
  p_worker_id text
) returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_action public.memory_trello_reconciliation_actions%rowtype;
begin
  if nullif(trim(p_worker_id),'') is null then
    raise exception 'worker_id is required';
  end if;

  select * into v_action
  from public.memory_trello_reconciliation_actions
  where status='pending'
  order by detected_at
  for update skip locked
  limit 1;

  if not found then
    return jsonb_build_object('ok',true,'claimed',false);
  end if;

  update public.memory_trello_reconciliation_actions
  set status='claimed',claimed_at=now(),worker_id=p_worker_id
  where id=v_action.id
  returning * into v_action;

  return jsonb_build_object('ok',true,'claimed',true,'action',to_jsonb(v_action));
end;
$$;

create or replace function public.memory_complete_trello_reconciliation(
  p_action_id uuid,
  p_worker_id text,
  p_status text,
  p_evidence jsonb default '[]'::jsonb,
  p_error_message text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_action public.memory_trello_reconciliation_actions%rowtype;
begin
  if p_status not in ('applied','failed') then
    raise exception 'status must be applied or failed';
  end if;
  if jsonb_typeof(coalesce(p_evidence,'null'::jsonb)) <> 'array' then
    raise exception 'evidence must be a JSON array';
  end if;
  if p_status='applied' and jsonb_array_length(p_evidence)=0 then
    raise exception 'applied requires evidence';
  end if;

  update public.memory_trello_reconciliation_actions
  set status=p_status,
      completed_at=now(),
      evidence=p_evidence,
      error_message=p_error_message
  where id=p_action_id
    and status='claimed'
    and worker_id=p_worker_id
  returning * into v_action;

  if not found then raise exception 'action not claimed by worker'; end if;
  return jsonb_build_object('ok',true,'action',to_jsonb(v_action));
end;
$$;

create or replace view public.memory_schedule_unfinished_dispatches_v
with (security_invoker = true) as
with sent as (
  select e.*,
         row_number() over (
           partition by schedule_key,run_key,stage,target_system,operation,coalesce(request_ref,'')
           order by occurred_at,id
         ) as seq
  from public.memory_schedule_dispatch_events e
  where status='sent'
), terminal as (
  select e.*,
         row_number() over (
           partition by schedule_key,run_key,stage,target_system,operation,coalesce(request_ref,'')
           order by occurred_at,id
         ) as seq
  from public.memory_schedule_dispatch_events e
  where status in ('ok','error','timeout','missing')
)
select s.id,s.schedule_key,s.run_key,s.stage,s.target_system,s.operation,s.request_ref,
       s.occurred_at as sent_at
from sent s
left join terminal t
  on t.schedule_key=s.schedule_key
 and t.run_key=s.run_key
 and t.stage=s.stage
 and t.target_system=s.target_system
 and t.operation=s.operation
 and coalesce(t.request_ref,'')=coalesce(s.request_ref,'')
 and t.seq=s.seq
where t.id is null;

create or replace function public.memory_queue_update_v2(
  p_queue_id uuid,
  p_worker_id text,
  p_state text,
  p_action text,
  p_result jsonb default null,
  p_evidence jsonb default '[]'::jsonb,
  p_blockers jsonb default '[]'::jsonb,
  p_version text default null
) returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  q public.memory_execution_queue%rowtype;
  r public.memory_execution_runs%rowtype;
  v_queue jsonb;
  v_run jsonb;
  v_result_text text;
begin
  if p_state not in ('running','blocked','completed','failed') then
    raise exception 'state must be running, blocked, completed or failed';
  end if;
  if jsonb_typeof(coalesce(p_evidence,'null'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_blockers,'null'::jsonb)) <> 'array' then
    raise exception 'evidence and blockers must be JSON arrays';
  end if;
  if p_state='completed' and jsonb_array_length(p_evidence)=0 then
    raise exception 'completed requires evidence';
  end if;
  if p_state='completed' and jsonb_array_length(p_blockers)>0 then
    raise exception 'completed requires empty blockers';
  end if;

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

  v_queue := public.memory_queue_update(
    p_queue_id,p_worker_id,p_state,p_result,p_evidence,p_blockers
  );
  v_run := public.memory_execution_update(
    r.id,r.lease_token,p_state,p_action,v_result_text,p_evidence,p_blockers,p_version
  );

  return jsonb_build_object('ok',true,'queue',v_queue,'run',v_run,'protocol','queue_run_v2');
end;
$$;

revoke all on function public.memory_plan_trello_state_reconciliation(text) from public,anon,authenticated;
revoke all on function public.memory_claim_trello_reconciliation(text) from public,anon,authenticated;
revoke all on function public.memory_complete_trello_reconciliation(uuid,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.memory_plan_trello_state_reconciliation(text) to service_role;
grant execute on function public.memory_claim_trello_reconciliation(text) to service_role;
grant execute on function public.memory_complete_trello_reconciliation(uuid,text,text,jsonb,text) to service_role;

comment on table public.memory_trello_reconciliation_actions is
'Outbox idempotente: decisiones de memory_state_reconciliation_v que un adaptador Trello debe aplicar y confirmar con evidencia.';
comment on view public.memory_schedule_unfinished_dispatches_v is
'Detecta eventos sent sin terminal usando occurred_at, la columna temporal canónica del ledger.';
