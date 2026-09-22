-- Initial operational control-center view and summary API.
-- Superseded for stale-run semantics by 20260922145434.
create or replace view public.memory_control_center_v with (security_invoker=true) as
with queue_latest as (
 select distinct on(q.project_id) q.project_id,q.id queue_id,q.state queue_state,q.executor_key,q.task_type,q.task_text,q.priority,q.card_url,q.claimed_by,q.claimed_at,q.started_at,q.finished_at,q.result,q.evidence,q.blockers,q.updated_at
 from public.memory_execution_queue q
 order by q.project_id,case when q.state in ('claimed','running','blocked','ready','needs_adapter','pending') then 0 else 1 end,q.updated_at desc
), run_latest as (
 select distinct on(r.project_id) r.project_id,r.id run_id,r.run_key,r.executor run_executor,r.state run_state,r.last_action,r.result run_result,r.blockers run_blockers,r.evidence run_evidence,r.version run_version,r.started_at run_started_at,r.heartbeat_at,r.finished_at run_finished_at
 from public.memory_execution_runs r
 order by r.project_id,case when r.state='running' then 0 else 1 end,coalesce(r.heartbeat_at,r.finished_at,r.started_at) desc
), mem as (
 select project_id,count(*) filter(where status='active') active_memories,count(*) filter(where status='active' and claim_state='verified') verified_memories,count(*) filter(where status='active' and claim_state='recorded') recorded_memories
 from public.memory_items where owner_key='duilio' group by project_id
), learn as (
 select project_id,count(*) filter(where learning_status='pending') pending_experiences,count(*) filter(where learning_status='learned') learned_experiences,count(*) filter(where learning_status='observed') observed_experiences
 from public.memory_experiences where owner_key='duilio' group by project_id
), know as (
 select project_id,count(*) filter(where status='candidate') candidate_knowledge,count(*) filter(where status='active') active_knowledge,count(*) filter(where status='deprecated') deprecated_knowledge
 from public.memory_knowledge where owner_key='duilio' group by project_id
), source_health as (
 select project_id,count(*) filter(where refresh_required and freshness_state='fresh') sources_fresh,count(*) filter(where refresh_required and freshness_state='stale') sources_stale,count(*) filter(where refresh_required and freshness_state='missing') sources_missing
 from public.memory_integrity_source_requirements_v group by project_id
)
select p.id project_id,p.project_key,p.project_name,parent.project_key parent_project_key,parent.project_name parent_project_name,
p.capture_mode,p.connector_status,p.auto_capture_enabled,p.github_repo,p.metadata->>'current_version' current_version,
coalesce(nullif(p.metadata->>'software_version_authority',''),nullif(p.metadata->>'version_authority','')) version_authority,
coalesce(sh.sources_fresh,0) sources_fresh,coalesce(sh.sources_stale,0) sources_stale,coalesce(sh.sources_missing,0) sources_missing,
q.queue_id,q.queue_state,q.executor_key,q.task_type,q.task_text,q.priority,q.card_url queue_card_url,q.claimed_by,q.claimed_at,q.started_at queue_started_at,q.finished_at queue_finished_at,q.result queue_result,q.evidence queue_evidence,q.blockers queue_blockers,
r.run_id,r.run_key,r.run_executor,r.run_state,r.last_action,r.run_result,r.run_blockers,r.run_evidence,r.run_version,r.run_started_at,r.heartbeat_at,r.run_finished_at,
coalesce(m.active_memories,0) active_memories,coalesce(m.verified_memories,0) verified_memories,coalesce(m.recorded_memories,0) recorded_memories,
coalesce(l.pending_experiences,0) pending_experiences,coalesce(l.learned_experiences,0) learned_experiences,coalesce(l.observed_experiences,0) observed_experiences,
coalesce(k.candidate_knowledge,0) candidate_knowledge,coalesce(k.active_knowledge,0) active_knowledge,coalesce(k.deprecated_knowledge,0) deprecated_knowledge,
case when coalesce(sh.sources_missing,0)>0 then 'source_missing' when coalesce(sh.sources_stale,0)>0 then 'source_stale'
when q.queue_state='blocked' or r.run_state='blocked' then 'blocked'
when q.queue_state in('claimed','running') or r.run_state='running' then 'running'
when q.queue_state in('ready','needs_adapter','pending') then 'queued' else 'idle' end operational_state
from public.memory_projects p
left join public.memory_projects parent on parent.id=p.parent_project_id
left join source_health sh on sh.project_id=p.id left join queue_latest q on q.project_id=p.id
left join run_latest r on r.project_id=p.id left join mem m on m.project_id=p.id left join learn l on l.project_id=p.id left join know k on k.project_id=p.id
where p.owner_key='duilio' and p.status='active' order by p.project_name;
revoke all on public.memory_control_center_v from public,anon,authenticated;
grant select on public.memory_control_center_v to service_role;
