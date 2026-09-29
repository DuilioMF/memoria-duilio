-- Applied in Supabase MD as migration 20260929022106.
-- Diagnostic only: a configured 'ready' value does not prove recent delivery.
create view public.memory_executor_health_v
with (security_invoker = true) as
select
  executor_key, display_name, status as configured_status,
  enabled, automatic, last_health_at,
  case
    when not enabled then 'disabled'
    when status <> 'ready' then status
    when last_health_at is null or last_health_at <= now() - interval '15 minutes' then 'stale'
    else 'ready'
  end as effective_status,
  case when last_health_at is null then null else extract(epoch from now() - last_health_at)::bigint end as heartbeat_age_seconds
from public.memory_executor_registry;

revoke all on public.memory_executor_health_v from public, anon, authenticated;
grant select on public.memory_executor_health_v to service_role;
