-- Persistencia de la política de severidad de integridad.
-- version_drift y authority_observation_missing siguen bloqueando.
-- authority_observation_stale y automatic_connector_not_connected son warning.

create or replace function public.memory_refresh_integrity(p_owner_key text default 'duilio'::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_now timestamptz := now();
  v_open integer;
begin
  insert into public.memory_integrity_incidents(
    owner_key,project_id,project_key,inconsistency_type,severity,status,fingerprint,summary,details,detected_at,last_seen_at
  )
  select
    p_owner_key,v.project_id,v.project_key,'version_drift','blocking','open',
    'version_drift:'||v.project_key,
    'Las versiones observadas no coinciden con la fuente autoritativa.',
    jsonb_build_object('canonical_version',v.canonical_version,'version_authority',v.version_authority,'sources',v.sources),
    v_now,v_now
  from public.memory_project_version_consistency_v v
  join public.memory_projects p on p.id=v.project_id
  where p.owner_key=p_owner_key and p.status='active'
    and v.canonical_version is not null and v.consistent=false
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='blocking',summary=excluded.summary,details=excluded.details,
    last_seen_at=v_now,resolved_at=null,resolution='{}'::jsonb;

  insert into public.memory_integrity_incidents(
    owner_key,project_id,project_key,inconsistency_type,severity,status,fingerprint,summary,details,detected_at,last_seen_at
  )
  select
    p_owner_key,r.project_id,r.project_key,'authority_observation_missing','blocking','open',
    'authority_observation_missing:'||r.project_key||':'||r.version_authority,
    'Falta una observación fresca de la fuente autoritativa; no se puede declarar consistencia.',
    jsonb_build_object('version_authority',r.version_authority,'authority_ref',r.authority_ref,'freshness_state',r.freshness_state),
    v_now,v_now
  from public.memory_integrity_source_requirements_v r
  where r.refresh_required=true and r.freshness_state='missing'
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='blocking',summary=excluded.summary,details=excluded.details,
    last_seen_at=v_now,resolved_at=null,resolution='{}'::jsonb;

  insert into public.memory_integrity_incidents(
    owner_key,project_id,project_key,inconsistency_type,severity,status,fingerprint,summary,details,detected_at,last_seen_at
  )
  select
    p_owner_key,r.project_id,r.project_key,'authority_observation_stale','warning','open',
    'authority_observation_stale:'||r.project_key||':'||r.version_authority,
    'La observación de la fuente autoritativa está vencida; conviene refrescarla, pero no bloquea el trabajo.',
    jsonb_build_object('version_authority',r.version_authority,'authority_ref',r.authority_ref,'observed_at',r.observed_at,'freshness_state',r.freshness_state),
    v_now,v_now
  from public.memory_integrity_source_requirements_v r
  where r.refresh_required=true and r.freshness_state='stale'
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='warning',summary=excluded.summary,details=excluded.details,
    last_seen_at=v_now,resolved_at=null,resolution='{}'::jsonb;

  insert into public.memory_integrity_incidents(
    owner_key,project_id,project_key,inconsistency_type,severity,status,fingerprint,summary,details,detected_at,last_seen_at
  )
  select
    p_owner_key,p.id,p.project_key,'automatic_capture_without_connector','blocking','open',
    'automatic_capture_without_connector:'||p.project_key,
    'El proyecto declara captura automática pero no tiene un conector automático conectado.',
    jsonb_build_object('capture_mode',p.capture_mode,'connector_status',p.connector_status),
    v_now,v_now
  from public.memory_projects p
  where p.owner_key=p_owner_key and p.status='active' and p.auto_capture_enabled=true
    and not exists (
      select 1 from public.memory_project_connectors c
      where c.project_id=p.id and c.automatic=true and c.status='connected'
    )
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='blocking',summary=excluded.summary,details=excluded.details,
    last_seen_at=v_now,resolved_at=null,resolution='{}'::jsonb;

  insert into public.memory_integrity_incidents(
    owner_key,project_id,project_key,inconsistency_type,severity,status,fingerprint,summary,details,detected_at,last_seen_at
  )
  select
    p_owner_key,p.id,p.project_key,'automatic_connector_not_connected','warning','open',
    'automatic_connector_not_connected:'||p.project_key||':'||c.connector_type||':'||c.connector_name,
    'Un conector marcado automático no está conectado; se registra como advertencia y no bloquea el flujo.',
    jsonb_build_object('connector_type',c.connector_type,'connector_name',c.connector_name,'status',c.status),
    v_now,v_now
  from public.memory_project_connectors c
  join public.memory_projects p on p.id=c.project_id
  where p.owner_key=p_owner_key and p.status='active'
    and c.automatic=true and c.status<>'connected'
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='warning',summary=excluded.summary,details=excluded.details,
    last_seen_at=v_now,resolved_at=null,resolution='{}'::jsonb;

  update public.memory_integrity_incidents i
     set status='resolved',
         resolved_at=v_now,
         resolution=jsonb_build_object('reason','condition_no_longer_present','resolved_at',v_now)
   where i.owner_key=p_owner_key and i.status='open'
     and i.inconsistency_type in (
       'version_drift','authority_observation_missing','authority_observation_stale',
       'automatic_capture_without_connector','automatic_connector_not_connected'
     )
     and not (
       (i.inconsistency_type='version_drift' and exists (
          select 1 from public.memory_project_version_consistency_v v
          where v.project_key=i.project_key and v.canonical_version is not null and v.consistent=false
       ))
       or
       (i.inconsistency_type='authority_observation_missing' and exists (
          select 1 from public.memory_integrity_source_requirements_v r
          where r.project_key=i.project_key and r.refresh_required=true and r.freshness_state='missing'
       ))
       or
       (i.inconsistency_type='authority_observation_stale' and exists (
          select 1 from public.memory_integrity_source_requirements_v r
          where r.project_key=i.project_key and r.refresh_required=true and r.freshness_state='stale'
       ))
       or
       (i.inconsistency_type='automatic_capture_without_connector' and exists (
          select 1 from public.memory_projects p
          where p.project_key=i.project_key and p.owner_key=p_owner_key
            and p.auto_capture_enabled=true
            and not exists (
              select 1 from public.memory_project_connectors c
              where c.project_id=p.id and c.automatic=true and c.status='connected'
            )
       ))
       or
       (i.inconsistency_type='automatic_connector_not_connected' and exists (
          select 1 from public.memory_project_connectors c
          join public.memory_projects p on p.id=c.project_id
          where p.project_key=i.project_key and p.owner_key=p_owner_key
            and c.automatic=true and c.status<>'connected'
       ))
     );

  select count(*) into v_open
  from public.memory_integrity_incidents
  where owner_key=p_owner_key and status='open' and severity='blocking';

  return jsonb_build_object('checked_at',v_now,'blocking_open',v_open,'passed',(v_open=0));
end;
$function$;
