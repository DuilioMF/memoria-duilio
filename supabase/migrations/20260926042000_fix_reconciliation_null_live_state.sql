-- Null-safe live-execution evaluation discovered by verification on 2026-09-26.
create or replace view public.memory_state_reconciliation_v
with (security_invoker = true) as
select
  e.id,e.title,e.card_url,e.list_name,e.state,e.executor,e.heartbeat_at,e.lease_until,e.integrity_state,
  case
    when e.list_name='En ejecución' and not live.is_live then 'running_without_live_execution'
    when e.list_name<>'En ejecución' and live.is_live then 'live_execution_outside_running'
    when e.list_name='En prueba' and upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
      then 'waiting_duilio_outside_waiting_column'
    else 'consistent_or_requires_description_check'
  end as reconciliation_result,
  case
    when e.list_name='En ejecución' and not live.is_live
      and (upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
        or upper(coalesce(m.content,'')) like '%ESPERANDO PRUEBA DE DUILIO%')
      then 'MOVE_TO_ESPERA_DE_VOS'
    when e.list_name='En ejecución' and not live.is_live then 'MOVE_TO_POR_HACER'
    when e.list_name<>'En ejecución' and live.is_live then 'MOVE_TO_EN_EJECUCION'
    when e.list_name='En prueba' and upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
      then 'MOVE_TO_ESPERA_DE_VOS'
    else 'NO_AUTOMATIC_MOVE'
  end as proposed_action,
  case
    when e.list_name='En ejecución' and not live.is_live
      and (upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
        or upper(coalesce(m.content,'')) like '%ESPERANDO PRUEBA DE DUILIO%')
      then 'Espera de vos'
    when e.list_name='En ejecución' and not live.is_live then 'Por hacer'
    when e.list_name<>'En ejecución' and live.is_live then 'En ejecución'
    when e.list_name='En prueba' and upper(coalesce(m.content,'')) like '%ESPERANDO A DUILIO%'
      then 'Espera de vos'
    else null
  end as target_list
from public.memory_execution_integrity_v e
join public.memory_items m on m.id=e.id
cross join lateral (
  select coalesce(
    e.state in ('running','claimed')
    and e.heartbeat_at > now()-interval '15 minutes'
    and e.lease_until > now(),
    false
  ) as is_live
) live;
