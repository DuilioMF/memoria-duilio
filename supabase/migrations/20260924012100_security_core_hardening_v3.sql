-- Memoria Duilio 0.6.2
-- Security + Core hardening v3
-- Aplicado y verificado con Supabase advisors el 23/09/2026.

do $$
declare t text;
begin
  foreach t in array array[
    'memory_performance_samples','memory_gc_runs','memory_project_restore_points',
    'memory_project_safety_policy','memory_decision_events','memory_decision_policy',
    'project_version_sync_registry','project_version_sync_events','memory_connector_instances',
    'memory_project_connector_bindings','memory_project_intake_events',
    'memory_connector_providers','memory_project_provision_jobs'
  ]
  loop
    execute format('drop policy if exists %I on public.%I','backend_only_deny_clients_'||t,t);
    execute format(
      'create policy %I on public.%I for all to anon, authenticated using (false) with check (false)',
      'backend_only_deny_clients_'||t,t
    );
  end loop;
end $$;

create or replace view public.memory_connector_topology_v
with (security_invoker=true)
as
select ci.id as connector_instance_id,
       ci.provider,ci.instance_key,ci.display_name as connector_instance_name,
       ci.status as connector_status,ci.discovery_enabled,p.id as project_id,
       p.project_key,p.canonical_name,b.resource_type,b.resource_ref,b.resource_name,
       b.role,b.status as binding_status,b.automatic
from public.memory_connector_instances ci
left join public.memory_project_connector_bindings b on b.connector_instance_id=ci.id
left join public.memory_projects p on p.id=b.project_id;

create or replace view public.memory_duplicate_candidates_v
with (security_invoker=true)
as
select a.id as item_id,a.title as item_title,b.id as candidate_id,b.title as candidate_title,
       1::double precision - (a.embedding <=> b.embedding) as similarity,a.project_id
from public.memory_items a
join public.memory_items b
  on not a.project_id is distinct from b.project_id
 and a.id < b.id
 and a.embedding is not null
 and b.embedding is not null
 and a.status='active' and b.status='active'
where (1::double precision - (a.embedding <=> b.embedding)) >= 0.90::double precision
order by (1::double precision - (a.embedding <=> b.embedding)) desc;

alter function public.memory_capture(text,text,text,text,text,text,text,smallint,text,text,text,text,jsonb)
  set search_path to 'public','pg_temp';
alter function public.memory_evaluate_batch(integer)
  set search_path to 'public','pg_temp';
alter function public.memory_evaluate_one(uuid)
  set search_path to 'public','pg_temp';
alter function public.memory_normalize_key(text)
  set search_path to 'public','pg_temp';
alter function public.memory_search_semantic(vector,integer,text,double precision)
  set search_path to 'public','pg_temp';

revoke execute on function public.memory_auto_process_project_intake() from public,anon,authenticated;
grant execute on function public.memory_auto_process_project_intake() to service_role;
revoke execute on function public.memory_auto_verify_finished_execution() from public,anon,authenticated;
grant execute on function public.memory_auto_verify_finished_execution() to service_role;
revoke execute on function public.memory_bind_project_connector(text,text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.memory_bind_project_connector(text,text,text,text,text,text,text,jsonb) to service_role;
revoke execute on function public.memory_can_modify_project(text,text) from public,anon,authenticated;
grant execute on function public.memory_can_modify_project(text,text) to service_role;
revoke execute on function public.memory_consolidate_execution_knowledge(text) from public,anon,authenticated;
grant execute on function public.memory_consolidate_execution_knowledge(text) to service_role;
revoke execute on function public.memory_decision_gate(text,numeric,text,text) from public,anon,authenticated;
grant execute on function public.memory_decision_gate(text,numeric,text,text) to service_role;
revoke execute on function public.memory_dispatch_effective_failures(text,interval) from public,anon,authenticated;
grant execute on function public.memory_dispatch_effective_failures(text,interval) to service_role;
revoke execute on function public.memory_efficiency_snapshot(text) from public,anon,authenticated;
grant execute on function public.memory_efficiency_snapshot(text) to service_role;
revoke execute on function public.memory_enqueue_manual_supabase_project() from public,anon,authenticated;
grant execute on function public.memory_enqueue_manual_supabase_project() to service_role;
revoke execute on function public.memory_enqueue_missing_project_provisioning(uuid,text) from public,anon,authenticated;
grant execute on function public.memory_enqueue_missing_project_provisioning(uuid,text) to service_role;
revoke execute on function public.memory_garbage_collector_v1(text,boolean) from public,anon,authenticated;
grant execute on function public.memory_garbage_collector_v1(text,boolean) to service_role;
revoke execute on function public.memory_improvement_scan(text) from public,anon,authenticated;
grant execute on function public.memory_improvement_scan(text) to service_role;
revoke execute on function public.memory_ingest_project_event(text,text,text,text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.memory_ingest_project_event(text,text,text,text,text,text,text,text,text,jsonb) to service_role;
revoke execute on function public.memory_latency_snapshot(text) from public,anon,authenticated;
grant execute on function public.memory_latency_snapshot(text) to service_role;
revoke execute on function public.memory_learn_verified_pending(text,integer) from public,anon,authenticated;
grant execute on function public.memory_learn_verified_pending(text,integer) to service_role;
revoke execute on function public.memory_prepare_domain_learning(text) from public,anon,authenticated;
grant execute on function public.memory_prepare_domain_learning(text) to service_role;
revoke execute on function public.memory_process_project_intake(bigint) from public,anon,authenticated;
grant execute on function public.memory_process_project_intake(bigint) to service_role;
revoke execute on function public.memory_register_connector_instance(text,text,text,text,text,text,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.memory_register_connector_instance(text,text,text,text,text,text,text,jsonb,boolean) to service_role;
revoke execute on function public.memory_register_connector_instance(text,text,text,text,text,text,text,jsonb,boolean,text,text,text,text[],boolean) from public,anon,authenticated;
grant execute on function public.memory_register_connector_instance(text,text,text,text,text,text,text,jsonb,boolean,text,text,text,text[],boolean) to service_role;

create index if not exists cognitive_questions_answer_memory_id_idx
  on public.cognitive_questions(answer_memory_id);
create index if not exists cognitive_questions_related_goal_id_idx
  on public.cognitive_questions(related_goal_id);
create index if not exists memory_items_duplicate_of_idx
  on public.memory_items(duplicate_of);
create index if not exists memory_project_intake_events_matched_project_id_idx
  on public.memory_project_intake_events(matched_project_id);
create index if not exists memory_project_provision_jobs_connector_instance_id_idx
  on public.memory_project_provision_jobs(connector_instance_id);
