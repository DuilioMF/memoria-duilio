-- 0.6.7: human approval MUST originate from a verified authorized Trello member.
alter table public.memory_card_delivery_gates
 add column if not exists required_approver text not null default 'duilio';
alter table public.memory_card_delivery_gates
 add column if not exists trello_approver_member_id text;
update public.memory_card_delivery_gates
set required_approver='duilio',
 trello_approver_member_id='ari:cloud:trello::user/5fab1bda9c115e314ae3193d'
where card_url in (
 'https://trello.com/c/Gk6jvAIY',
 'https://trello.com/c/Ju1hmWW9',
 'https://trello.com/c/T2xmrKV5'
);
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
    and lower(g.human_approval->>'actor')=lower(g.required_approver)
    and g.human_approval->>'source'='trello_member_verified'
    and coalesce(g.human_approval->>'member_id','')=coalesce(g.trello_approver_member_id,'')
    and g.trello_approver_member_id is not null
    and (g.human_approval->>'evidence_ref') ~ '^https://trello[.]com/c/[A-Za-z0-9]+'
    and (g.human_approval->>'verified_at') is not null
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
end $function$;

revoke execute on function public.memory_card_closure_gate(text) from public,anon,authenticated;
grant execute on function public.memory_card_closure_gate(text) to service_role;
