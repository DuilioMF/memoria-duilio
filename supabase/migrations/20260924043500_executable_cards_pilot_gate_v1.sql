-- Memoria Duilio 0.6.6: three-card pilot gate.
-- This migration is equivalent to deployed executable_cards_pilot_closure_gate_v1.
create table if not exists public.memory_card_delivery_gates(
card_url text primary key check(card_url ~ '^https://trello[.]com/c/[A-Za-z0-9]+$'),
project_key text not null,
delivery_kind text not null check(delivery_kind in ('software','field_validation','document_validation')),
specification_ref text not null,
specification_status text not null default 'pilot' check(specification_status in ('pilot','ready','needs_clarification')),
required_case_ids text[] not null default array[]::text[],
requires_ci boolean not null default false,
requires_release boolean not null default false,
requires_rollback boolean not null default false,
requires_human_approval boolean not null default true,
intended_executor_key text null references public.memory_executor_registry(executor_key),
case_evidence jsonb not null default '[]'::jsonb check(jsonb_typeof(case_evidence)='array'),
ci_evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(ci_evidence)='object'),
release_evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(release_evidence)='object'),
rollback_evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(rollback_evidence)='object'),
human_approval jsonb not null default '{}'::jsonb check(jsonb_typeof(human_approval)='object'),
incident_history jsonb not null default '[]'::jsonb check(jsonb_typeof(incident_history)='array'),
created_at timestamptz not null default now(),updated_at timestamptz not null default now());
alter table public.memory_card_delivery_gates enable row level security;
revoke all on public.memory_card_delivery_gates from public,anon,authenticated;
grant select,insert,update on public.memory_card_delivery_gates to service_role;
CREATE OR REPLACE FUNCTION public.memory_card_closure_gate(p_card_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  g public.memory_card_delivery_gates%rowtype;
  v_url text;
  v_missing text[]:=array[]::text[];
  v_case text;
  v_e jsonb;
begin
  v_url:=substring(p_card_url from '^https?://trello[.]com/c/[A-Za-z0-9]+');
  if v_url is null then
    return jsonb_build_object('allowed',false,'reasons',jsonb_build_array('invalid_trello_card_url'));
  end if;
  select * into g from public.memory_card_delivery_gates where card_url=v_url;
  if not found then
    return jsonb_build_object('allowed',false,'card_url',v_url,
      'reasons',jsonb_build_array('missing_executable_contract'));
  end if;

  if g.specification_status<>'ready' then
    v_missing:=array_append(v_missing,'specification_not_approved_for_execution');
  end if;

  if g.intended_executor_key is null then
    v_missing:=array_append(v_missing,'executor_not_resolved_from_registry');
  elsif not exists(select 1 from public.memory_executor_registry e
    where e.executor_key=g.intended_executor_key and e.enabled
      and e.status='ready') then
    v_missing:=array_append(v_missing,'executor_currently_not_available');
  end if;

  foreach v_case in array g.required_case_ids loop
    if not exists (
      select 1 from jsonb_array_elements(g.case_evidence) x
      where x->>'case_id'=v_case and lower(x->>'result')='pass'
        and length(btrim(coalesce(x->>'evidence_ref','')))>0
    ) then
      v_missing:=array_append(v_missing,'case_unverified:'||v_case);
    end if;
  end loop;

  if cardinality(g.required_case_ids)=0 then
    v_missing:=array_append(v_missing,'missing_acceptance_test_cases');
  end if;

  if g.requires_ci and not (
    lower(g.ci_evidence->>'result')='success'
    and length(btrim(coalesce(g.ci_evidence->>'run_url','')))>0
    and length(btrim(coalesce(g.ci_evidence->>'source_sha','')))>0
  ) then
    v_missing:=array_append(v_missing,'ci_evidence_missing_or_failed');
  end if;

  if g.requires_release and not (
    lower(g.release_evidence->>'result')='success'
    and lower(g.release_evidence->>'smoke_test')='pass'
    and length(btrim(coalesce(g.release_evidence->>'url','')))>0
    and length(btrim(coalesce(g.release_evidence->>'source_sha','')))>0
  ) then
    v_missing:=array_append(v_missing,'release_and_smoke_test_unverified');
  end if;

  if g.requires_rollback and not (
    lower(g.rollback_evidence->>'result')='verified'
    and length(btrim(coalesce(g.rollback_evidence->>'restore_ref','')))>0
  ) then
    v_missing:=array_append(v_missing,'rollback_not_verified');
  end if;

  if g.requires_human_approval and not (
    lower(g.human_approval->>'result')='approved'
    and length(btrim(coalesce(g.human_approval->>'actor','')))>0
    and length(btrim(coalesce(g.human_approval->>'evidence_ref','')))>0
  ) then
    v_missing:=array_append(v_missing,'explicit_human_approval_missing');
  end if;

  return jsonb_build_object(
    'allowed',cardinality(v_missing)=0,
    'card_url',v_url,'project_key',g.project_key,
    'delivery_kind',g.delivery_kind,
    'reasons',to_jsonb(v_missing),
    'human_gate_required',g.requires_human_approval,
    'specification_ref',g.specification_ref
  );
end $function$

revoke execute on function public.memory_card_closure_gate(text) from public,anon,authenticated;
grant execute on function public.memory_card_closure_gate(text) to service_role;
create or replace view public.memory_card_closure_audit_v with (security_invoker=true)
as select g.card_url,g.project_key,g.delivery_kind,g.specification_status,
public.memory_card_closure_gate(g.card_url) as decision from public.memory_card_delivery_gates g;
revoke all on public.memory_card_closure_audit_v from public,anon,authenticated;
grant select on public.memory_card_closure_audit_v to service_role;
