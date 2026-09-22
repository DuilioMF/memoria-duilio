alter view public.memory_schedule_run_diagnostics_v set (security_invoker=true);
alter view public.memory_integrity_source_requirements_v set (security_invoker=true);
alter view public.v_memory_items_usage_health set (security_invoker=true);
revoke all on public.memory_schedule_run_diagnostics_v from public,anon,authenticated;
revoke all on public.memory_integrity_source_requirements_v from public,anon,authenticated;
revoke all on public.v_memory_items_usage_health from public,anon,authenticated;
grant select on public.memory_schedule_run_diagnostics_v to service_role;
grant select on public.memory_integrity_source_requirements_v to service_role;
grant select on public.v_memory_items_usage_health to service_role;
