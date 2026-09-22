-- Fix falsos positivos diarios de authority_observation_stale.
-- Contexto:
-- - GitHub se refresca aproximadamente a las 11:00 UTC (08:00 ART).
-- - memory_check_startup también ejecuta el gate de integridad a las 06:20 UTC.
-- - El umbral anterior era 2 horas, incompatible con una fuente de refresco diario.
-- Política nueva:
-- - stale después de 26 horas.
-- - A las 06:20 UTC una observación del refresh de las 11:00 UTC del día anterior sigue fresh (~19h).
-- - Si se pierde un refresh diario completo, el siguiente chequeo sí la marca stale (>26h).

create or replace view public.memory_integrity_source_requirements_v as
with p as (
  select
    mp.id as project_id,
    mp.project_key,
    mp.project_name,
    mp.status,
    mp.source_system,
    mp.source_ref,
    mp.metadata,
    lower(coalesce(
      nullif(mp.metadata ->> 'software_version_authority',''),
      nullif(mp.metadata ->> 'version_authority',''),
      'github'
    )) as version_authority,
    coalesce(
      nullif(mp.metadata ->> 'github_repo',''),
      case when mp.source_ref like 'https://github.com/%' then mp.source_ref else null end
    ) as github_repo
  from public.memory_projects mp
  where mp.owner_key='duilio'
    and mp.status='active'
)
select
  p.project_id,
  p.project_key,
  p.project_name,
  p.version_authority,
  case
    when p.version_authority='github' then p.github_repo
    else p.source_ref
  end as authority_ref,
  o.version as observed_version,
  o.observed_at,
  case
    when p.version_authority='github'
      and p.github_repo is not null
      and coalesce(p.metadata ->> 'github_repository_status','') <> 'pending_creation'
      then true
    when p.version_authority<>'github'
      and nullif(p.source_ref,'') is not null
      and p.source_ref <> all(array[
        'supervision','doinglio','conexion','oleum','puente-ia',
        'redes-revalsoftia','n8n-sql-automatizaciones','revalsoft-saas'
      ])
      and p.source_ref <> p.project_key
      then true
    else false
  end as refresh_required,
  case
    when not (
      (
        p.version_authority='github'
        and p.github_repo is not null
        and coalesce(p.metadata ->> 'github_repository_status','') <> 'pending_creation'
      )
      or
      (
        p.version_authority<>'github'
        and nullif(p.source_ref,'') is not null
        and p.source_ref <> all(array[
          'supervision','doinglio','conexion','oleum','puente-ia',
          'redes-revalsoftia','n8n-sql-automatizaciones','revalsoft-saas'
        ])
        and p.source_ref <> p.project_key
      )
    ) then 'not_applicable'
    when o.id is null then 'missing'
    when o.observed_at < (now() - interval '26 hours') then 'stale'
    else 'fresh'
  end as freshness_state
from p
left join public.memory_project_version_observations o
  on o.project_id=p.project_id
 and o.source_system=p.version_authority;

comment on view public.memory_integrity_source_requirements_v is
'Determina si la observacion de la fuente autoritativa requiere refresh. Umbral stale=26h para fuentes diarias como GitHub, evitando falsos positivos antes del refresh de las 08:00 ART y detectando un refresh diario perdido.';
