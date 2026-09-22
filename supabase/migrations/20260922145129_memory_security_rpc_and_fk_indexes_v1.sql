do $$
declare r record;
begin
 for r in
  select p.oid::regprocedure::text fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and p.proname=any(array[
   'memory_add_domain_knowledge','memory_auto_repair_safe_inconsistencies','memory_backfill_verified_execution_evidence',
   'memory_classify_nonlearnable_observations','memory_enqueue_trello_card','memory_integrity_gate',
   'memory_promote_knowledge_candidates','memory_queue_claim_v2','memory_queue_update_v2','memory_queue_verify_and_learn',
   'memory_reconcile_stale_schedule_runs','memory_record_project_version','memory_refresh_integrity',
   'memory_schedule_dispatch_event','memory_schedule_run_start','memory_schedule_run_step','memory_supersede_knowledge'])
 loop
  execute format('revoke execute on function %s from public, anon, authenticated',r.fn);
  execute format('grant execute on function %s to service_role',r.fn);
 end loop;
end $$;
create index if not exists memory_affective_events_experience_id_idx on public.memory_affective_events(experience_id);
create index if not exists memory_evaluations_project_id_idx on public.memory_evaluations(project_id);
create index if not exists memory_execution_queue_decision_id_idx on public.memory_execution_queue(decision_id);
create index if not exists memory_execution_queue_executor_key_idx on public.memory_execution_queue(executor_key);
create index if not exists memory_execution_queue_project_id_idx on public.memory_execution_queue(project_id);
create index if not exists memory_experiences_linked_knowledge_id_idx on public.memory_experiences(linked_knowledge_id);
create index if not exists memory_experiences_memory_item_id_idx on public.memory_experiences(memory_item_id);
create index if not exists memory_integrity_incidents_project_id_idx on public.memory_integrity_incidents(project_id);
create index if not exists memory_knowledge_supersedes_id_idx on public.memory_knowledge(supersedes_id);
create index if not exists memory_knowledge_experiences_experience_id_idx on public.memory_knowledge_experiences(experience_id);
create index if not exists memory_orchestrator_decisions_selected_executor_idx on public.memory_orchestrator_decisions(selected_executor);
create index if not exists memory_trainer_findings_related_knowledge_id_idx on public.memory_trainer_findings(related_knowledge_id);
