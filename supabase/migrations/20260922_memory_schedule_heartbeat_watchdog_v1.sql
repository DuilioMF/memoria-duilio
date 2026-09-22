-- Memoria Duilio: heartbeat real + watchdog de runs programados.
-- 22/09/2026
--
-- Problema:
-- public.memory_schedule_dispatch_event registraba actividad pero no actualizaba
-- memory_scheduled_runs.last_heartbeat_at. Una corrida podía estar trabajando y
-- parecer stale, o quedar started/running para siempre si el flujo se cortaba.
--
-- Fix:
-- 1) Cada dispatch actualiza heartbeat, step y started->running.
-- 2) Watchdog cierra como incomplete runs sin heartbeat por >30 minutos.
-- 3) pg_cron ejecuta el watchdog cada 15 minutos.

create or replace function public.memory_schedule_dispatch_event(
  p_schedule_key text,
  p_run_key text,
  p_stage text,
  p_target_system text,
  p_operation text,
  p_status text,
  p_request_ref text default null,
  p_response_code text default null,
  p_response_summary text default null,
  p_error_message text default null,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_id uuid;
begin
  if p_status not in ('sent','received','ok','error','timeout','missing') then
    raise exception 'invalid dispatch status %',p_status;
  end if;

  insert into public.memory_schedule_dispatch_events(
    owner_key,schedule_key,run_key,stage,target_system,operation,status,
    request_ref,response_code,response_summary,error_message,details
  ) values(
    'duilio',p_schedule_key,p_run_key,p_stage,p_target_system,p_operation,p_status,
    p_request_ref,p_response_code,p_response_summary,p_error_message,coalesce(p_details,'{}'::jsonb)
  ) returning id into v_id;

  update public.memory_scheduled_runs
  set last_heartbeat_at=now(),
      status=case when status='started' then 'running' else status end,
      step=p_stage,
      updated_at=now()
  where owner_key='duilio'
    and run_key=p_run_key
    and finished_at is null;

  return jsonb_build_object(
    'ok',true,'id',v_id,'run_key',p_run_key,'stage',p_stage,
    'status',p_status,'recorded_at',now()
  );
end;
$function$;

create or replace function public.memory_reconcile_stale_schedule_runs(
  p_owner_key text default 'duilio',
  p_stale_after interval default interval '30 minutes'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_now timestamptz := now();
  v_count integer := 0;
begin
  update public.memory_scheduled_runs
  set status='incomplete',
      step='watchdog_timeout',
      summary='Cierre automático: corrida sin heartbeat dentro del umbral esperado.',
      details=coalesce(details,'{}'::jsonb) || jsonb_build_object(
        'watchdog_closed_at',v_now,
        'watchdog_reason','stale_heartbeat',
        'stale_after',p_stale_after::text
      ),
      finished_at=v_now,
      updated_at=v_now
  where owner_key=p_owner_key
    and status in ('started','running')
    and finished_at is null
    and last_heartbeat_at < (v_now - p_stale_after);

  get diagnostics v_count = row_count;

  return jsonb_build_object(
    'checked_at',v_now,
    'stale_after',p_stale_after::text,
    'closed_runs',v_count
  );
end;
$function$;

select cron.schedule(
  'memoria-duilio-run-watchdog',
  '*/15 * * * *',
  $$select public.memory_reconcile_stale_schedule_runs('duilio', interval '30 minutes');$$
);
