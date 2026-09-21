-- Memoria Duilio - migraciones recuperadas desde supabase_migrations.schema_migrations
-- Generado como snapshot de recuperación. No contiene migraciones detectadas con literales de credenciales.
-- Mantener orden por version.

-- ============================================================================
-- 20260901033308_add_memory_ingest_pipeline
-- ============================================================================
create schema if not exists private;

create table if not exists public.memory_ingest_events (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  source_type text not null,
  source_name text not null,
  external_id text not null,
  event_type text not null,
  title text not null,
  content text not null,
  summary text,
  source_url text,
  category text not null default 'project_activity',
  memory_type text not null default 'observation',
  importance smallint not null default 6 check (importance between 1 and 10),
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  payload_hash text,
  status text not null default 'pending' check (status in ('pending','processed','failed','ignored')),
  memory_item_id uuid references public.memory_items(id) on delete set null,
  error_message text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (owner_key, source_type, external_id, event_type)
);

alter table public.memory_ingest_events enable row level security;
revoke all on public.memory_ingest_events from anon, authenticated;
grant select, insert, update on public.memory_ingest_events to service_role;

create or replace function private.memory_process_ingest_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_source_id uuid;
  v_memory_id uuid;
  v_fingerprint text;
  v_chunk_content text;
begin
  if length(trim(new.title)) = 0 or length(trim(new.content)) = 0 then
    new.status := 'ignored';
    new.error_message := 'title and content are required';
    new.processed_at := now();
    return new;
  end if;

  v_fingerprint := encode(
    digest(
      concat_ws('|', new.owner_key, new.source_type, new.external_id, new.event_type, new.title, new.content),
      'sha256'
    ),
    'hex'
  );
  new.payload_hash := v_fingerprint;

  insert into public.memory_sources (
    source_type, source_name, external_ref, source_url, captured_at, metadata
  ) values (
    new.source_type,
    new.source_name,
    new.source_name,
    new.source_url,
    new.occurred_at,
    jsonb_build_object('automated_capture', true)
  )
  on conflict (source_type, external_ref) do update
  set source_name = excluded.source_name,
      source_url = coalesce(excluded.source_url, memory_sources.source_url),
      captured_at = greatest(memory_sources.captured_at, excluded.captured_at),
      metadata = memory_sources.metadata || excluded.metadata
  returning id into v_source_id;

  insert into public.memory_items (
    owner_key, source_id, memory_type, category, title, content, summary,
    importance, confidence, fingerprint, valid_from, metadata
  ) values (
    new.owner_key,
    v_source_id,
    new.memory_type,
    new.category,
    new.title,
    new.content,
    new.summary,
    new.importance,
    1,
    v_fingerprint,
    new.occurred_at,
    new.metadata || jsonb_build_object(
      'automated_capture', true,
      'external_id', new.external_id,
      'event_type', new.event_type,
      'source_url', new.source_url
    )
  )
  on conflict (owner_key, fingerprint) do update
  set source_id = excluded.source_id,
      title = excluded.title,
      content = excluded.content,
      summary = excluded.summary,
      importance = excluded.importance,
      valid_from = excluded.valid_from,
      metadata = memory_items.metadata || excluded.metadata,
      status = 'active',
      updated_at = now()
  returning id into v_memory_id;

  v_chunk_content := concat_ws(E'\n\n', new.title, new.summary, new.content);
  insert into public.memory_chunks (
    memory_item_id, chunk_index, content, embedding, embedding_model,
    embedding_dimensions, metadata
  ) values (
    v_memory_id, 0, v_chunk_content, null, 'gte-small', 384,
    jsonb_build_object('auto_generated', true, 'source', 'memory_ingest_events')
  )
  on conflict (memory_item_id, chunk_index) do update
  set content = excluded.content,
      embedding = case when memory_chunks.content = excluded.content then memory_chunks.embedding else null end,
      embedding_model = excluded.embedding_model,
      embedding_dimensions = excluded.embedding_dimensions,
      metadata = memory_chunks.metadata || excluded.metadata;

  insert into public.memory_events (
    event_type, memory_item_id, source_id, owner_key, actor, details, occurred_at
  ) values (
    'captured_external',
    v_memory_id,
    v_source_id,
    new.owner_key,
    new.source_type,
    jsonb_build_object(
      'external_id', new.external_id,
      'source_name', new.source_name,
      'origin_event_type', new.event_type
    ),
    new.occurred_at
  );

  new.memory_item_id := v_memory_id;
  new.status := 'processed';
  new.processed_at := now();
  new.error_message := null;
  return new;
exception when others then
  new.status := 'failed';
  new.error_message := left(sqlerrm, 500);
  new.processed_at := now();
  return new;
end;
$$;

revoke all on function private.memory_process_ingest_event() from public, anon, authenticated;
grant execute on function private.memory_process_ingest_event() to service_role;

drop trigger if exists memory_ingest_events_process on public.memory_ingest_events;
create trigger memory_ingest_events_process
before insert or update of title, content, summary, importance, metadata
on public.memory_ingest_events
for each row execute function private.memory_process_ingest_event();

comment on table public.memory_ingest_events is
'Bandeja idempotente para capturar eventos durables desde GitHub, Sites, n8n y sesiones de trabajo.';

-- ============================================================================
-- 20260901033350_fix_memory_ingest_digest_schema
-- ============================================================================
create or replace function private.memory_process_ingest_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_source_id uuid;
  v_memory_id uuid;
  v_fingerprint text;
  v_chunk_content text;
begin
  if length(trim(new.title)) = 0 or length(trim(new.content)) = 0 then
    new.status := 'ignored';
    new.error_message := 'title and content are required';
    new.processed_at := now();
    return new;
  end if;

  v_fingerprint := encode(
    extensions.digest(
      concat_ws('|', new.owner_key, new.source_type, new.external_id, new.event_type, new.title, new.content),
      'sha256'
    ),
    'hex'
  );
  new.payload_hash := v_fingerprint;

  insert into public.memory_sources (
    source_type, source_name, external_ref, source_url, captured_at, metadata
  ) values (
    new.source_type, new.source_name, new.source_name, new.source_url, new.occurred_at,
    jsonb_build_object('automated_capture', true)
  )
  on conflict (source_type, external_ref) do update
  set source_name = excluded.source_name,
      source_url = coalesce(excluded.source_url, memory_sources.source_url),
      captured_at = greatest(memory_sources.captured_at, excluded.captured_at),
      metadata = memory_sources.metadata || excluded.metadata
  returning id into v_source_id;

  insert into public.memory_items (
    owner_key, source_id, memory_type, category, title, content, summary,
    importance, confidence, fingerprint, valid_from, metadata
  ) values (
    new.owner_key, v_source_id, new.memory_type, new.category, new.title, new.content,
    new.summary, new.importance, 1, v_fingerprint, new.occurred_at,
    new.metadata || jsonb_build_object(
      'automated_capture', true, 'external_id', new.external_id,
      'event_type', new.event_type, 'source_url', new.source_url
    )
  )
  on conflict (owner_key, fingerprint) do update
  set source_id = excluded.source_id,
      title = excluded.title,
      content = excluded.content,
      summary = excluded.summary,
      importance = excluded.importance,
      valid_from = excluded.valid_from,
      metadata = memory_items.metadata || excluded.metadata,
      status = 'active',
      updated_at = now()
  returning id into v_memory_id;

  v_chunk_content := concat_ws(E'\n\n', new.title, new.summary, new.content);
  insert into public.memory_chunks (
    memory_item_id, chunk_index, content, embedding, embedding_model,
    embedding_dimensions, metadata
  ) values (
    v_memory_id, 0, v_chunk_content, null, 'gte-small', 384,
    jsonb_build_object('auto_generated', true, 'source', 'memory_ingest_events')
  )
  on conflict (memory_item_id, chunk_index) do update
  set content = excluded.content,
      embedding = case when memory_chunks.content = excluded.content then memory_chunks.embedding else null end,
      embedding_model = excluded.embedding_model,
      embedding_dimensions = excluded.embedding_dimensions,
      metadata = memory_chunks.metadata || excluded.metadata;

  insert into public.memory_events (
    event_type, memory_item_id, source_id, owner_key, actor, details, occurred_at
  ) values (
    'captured_external', v_memory_id, v_source_id, new.owner_key, new.source_type,
    jsonb_build_object(
      'external_id', new.external_id, 'source_name', new.source_name,
      'origin_event_type', new.event_type
    ),
    new.occurred_at
  );

  new.memory_item_id := v_memory_id;
  new.status := 'processed';
  new.processed_at := now();
  new.error_message := null;
  return new;
exception when others then
  new.status := 'failed';
  new.error_message := left(sqlerrm, 500);
  new.processed_at := now();
  return new;
end;
$$;

revoke all on function private.memory_process_ingest_event() from public, anon, authenticated;
grant execute on function private.memory_process_ingest_event() to service_role;

-- ============================================================================
-- 20260901033647_index_memory_ingest_pipeline
-- ============================================================================
create index if not exists memory_ingest_events_memory_item_id_idx on public.memory_ingest_events(memory_item_id); create index if not exists memory_ingest_events_status_received_idx on public.memory_ingest_events(status, received_at desc);

-- ============================================================================
-- 20260901034010_enable_memory_sync_scheduler
-- ============================================================================
create extension if not exists pg_net; create extension if not exists pg_cron with schema pg_catalog; grant usage on schema cron to postgres; grant all privileges on all tables in schema cron to postgres;

-- ============================================================================
-- 20260903213910_memoria_duilio_learning_engine_v1
-- ============================================================================
create table if not exists public.memory_experiences (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  project_id uuid null references public.memory_projects(id) on delete set null,
  memory_item_id uuid null references public.memory_items(id) on delete set null,
  problem_type text not null,
  context text null,
  solution text not null,
  model_name text null,
  outcome text not null default 'unknown' check (outcome in ('success','failure','partial','unknown')),
  quality_score numeric(5,4) not null default 0.5000 check (quality_score between 0 and 1),
  confidence numeric(5,4) not null default 0.5000 check (confidence between 0 and 1),
  evidence jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.memory_knowledge (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  project_id uuid null references public.memory_projects(id) on delete set null,
  knowledge_type text not null default 'rule',
  title text not null,
  statement text not null,
  status text not null default 'candidate' check (status in ('candidate','active','deprecated','rejected')),
  confidence numeric(5,4) not null default 0.5000 check (confidence between 0 and 1),
  use_count integer not null default 0 check (use_count >= 0),
  success_count integer not null default 0 check (success_count >= 0),
  failure_count integer not null default 0 check (failure_count >= 0),
  partial_count integer not null default 0 check (partial_count >= 0),
  score numeric(12,6) not null default 0,
  last_used_at timestamptz null,
  last_validated_at timestamptz null,
  supersedes_id uuid null references public.memory_knowledge(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.memory_knowledge_experiences (
  knowledge_id uuid not null references public.memory_knowledge(id) on delete cascade,
  experience_id uuid not null references public.memory_experiences(id) on delete cascade,
  relation_type text not null default 'supports' check (relation_type in ('supports','contradicts','derived_from','tests')),
  weight numeric(5,4) not null default 1.0000 check (weight between 0 and 1),
  created_at timestamptz not null default now(),
  primary key (knowledge_id, experience_id, relation_type)
);

create table if not exists public.memory_evaluations (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  project_id uuid null references public.memory_projects(id) on delete set null,
  experience_id uuid null references public.memory_experiences(id) on delete cascade,
  knowledge_id uuid null references public.memory_knowledge(id) on delete cascade,
  evaluator text not null default 'system',
  result text not null check (result in ('success','failure','partial','unknown')),
  score numeric(5,4) not null default 0.5000 check (score between 0 and 1),
  notes text null,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (experience_id is not null or knowledge_id is not null)
);

create index if not exists idx_memory_experiences_project_time on public.memory_experiences(project_id, occurred_at desc);
create index if not exists idx_memory_experiences_problem_type on public.memory_experiences(problem_type);
create index if not exists idx_memory_experiences_outcome on public.memory_experiences(outcome);
create index if not exists idx_memory_knowledge_project_status_score on public.memory_knowledge(project_id, status, score desc);
create index if not exists idx_memory_knowledge_title on public.memory_knowledge using gin (to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(statement,'')));
create index if not exists idx_memory_evaluations_knowledge on public.memory_evaluations(knowledge_id, created_at desc);
create index if not exists idx_memory_evaluations_experience on public.memory_evaluations(experience_id, created_at desc);

create or replace function public.memory_calculate_knowledge_score(
  p_success_count integer,
  p_failure_count integer,
  p_partial_count integer,
  p_use_count integer,
  p_confidence numeric,
  p_last_used_at timestamptz
) returns numeric
language sql
stable
as $$
  select round((
    case
      when greatest(coalesce(p_success_count,0)+coalesce(p_failure_count,0)+coalesce(p_partial_count,0),1) = 0 then 0
      else (coalesce(p_success_count,0) + 0.5 * coalesce(p_partial_count,0))::numeric /
           greatest(coalesce(p_success_count,0)+coalesce(p_failure_count,0)+coalesce(p_partial_count,0),1)
    end
    * ln(2 + greatest(coalesce(p_use_count,0),0))
    * greatest(least(coalesce(p_confidence,0.5),1),0)
    * (1.0 / (1.0 + greatest(extract(epoch from (now() - coalesce(p_last_used_at, now()))) / 86400.0,0) / 180.0))
  )::numeric, 6);
$$;

create or replace function public.memory_refresh_knowledge_score(p_knowledge_id uuid)
returns numeric
language plpgsql
as $$
declare
  v_score numeric;
begin
  update public.memory_knowledge
     set score = public.memory_calculate_knowledge_score(success_count, failure_count, partial_count, use_count, confidence, last_used_at),
         updated_at = now()
   where id = p_knowledge_id
   returning score into v_score;
  return v_score;
end;
$$;

-- ============================================================================
-- 20260903213929_memoria_duilio_learning_engine_v1_security
-- ============================================================================
alter table public.memory_experiences enable row level security;
alter table public.memory_knowledge enable row level security;
alter table public.memory_knowledge_experiences enable row level security;
alter table public.memory_evaluations enable row level security;

alter function public.memory_calculate_knowledge_score(integer, integer, integer, integer, numeric, timestamptz) set search_path = public, pg_temp;
alter function public.memory_refresh_knowledge_score(uuid) set search_path = public, pg_temp;

-- ============================================================================
-- 20260904031116_memoria_duilio_phase3_consolidation_engine_v1
-- ============================================================================
alter table public.memory_experiences
  add column if not exists learning_status text not null default 'pending',
  add column if not exists learned_at timestamptz,
  add column if not exists linked_knowledge_id uuid references public.memory_knowledge(id) on delete set null;

alter table public.memory_knowledge
  add column if not exists problem_type text,
  add column if not exists fingerprint text,
  add column if not exists evidence_count integer not null default 0;

create unique index if not exists ux_memory_knowledge_owner_fingerprint
  on public.memory_knowledge(owner_key, fingerprint)
  where fingerprint is not null and status <> 'deprecated';

create index if not exists ix_memory_experiences_learning_status
  on public.memory_experiences(owner_key, learning_status, occurred_at desc);

create index if not exists ix_memory_knowledge_problem_score
  on public.memory_knowledge(owner_key, project_id, problem_type, score desc)
  where status = 'active';

create or replace function public.memory_normalize_text(p_text text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select lower(trim(regexp_replace(coalesce(p_text,''), '\\s+', ' ', 'g')));
$$;

create or replace function public.memory_make_knowledge_fingerprint(
  p_owner_key text,
  p_project_id uuid,
  p_problem_type text,
  p_solution text
)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select md5(
    coalesce(p_owner_key,'') || '|' ||
    coalesce(p_project_id::text,'global') || '|' ||
    public.memory_normalize_text(p_problem_type) || '|' ||
    public.memory_normalize_text(p_solution)
  );
$$;

create or replace function public.memory_learn_from_experience(p_experience_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  e public.memory_experiences%rowtype;
  k public.memory_knowledge%rowtype;
  v_fingerprint text;
  v_result text;
  v_quality numeric;
  v_confidence numeric;
  v_title text;
begin
  select * into e
  from public.memory_experiences
  where id = p_experience_id
  for update;

  if not found then
    raise exception 'experience_not_found';
  end if;

  if e.learning_status = 'learned' and e.linked_knowledge_id is not null then
    return e.linked_knowledge_id;
  end if;

  v_result := lower(coalesce(e.outcome,'partial'));
  if v_result not in ('success','failure','partial') then
    v_result := 'partial';
  end if;

  v_quality := greatest(least(coalesce(e.quality_score,0.5),1),0);
  v_confidence := greatest(least(coalesce(e.confidence,0.5),1),0);
  v_fingerprint := public.memory_make_knowledge_fingerprint(e.owner_key, e.project_id, e.problem_type, e.solution);
  v_title := left(coalesce(nullif(trim(e.problem_type),''),'Conocimiento aprendido') || ': ' || coalesce(nullif(trim(e.solution),''),'sin solución registrada'), 180);

  select * into k
  from public.memory_knowledge
  where owner_key = e.owner_key
    and fingerprint = v_fingerprint
    and status <> 'deprecated'
  order by created_at asc
  limit 1
  for update;

  if not found then
    insert into public.memory_knowledge(
      owner_key, project_id, knowledge_type, problem_type, title, statement,
      status, confidence, use_count, success_count, failure_count, partial_count,
      evidence_count, last_used_at, last_validated_at, fingerprint, metadata
    ) values (
      e.owner_key, e.project_id, 'learned_rule', e.problem_type, v_title, e.solution,
      'active', round(((v_confidence + v_quality) / 2)::numeric,4), 1,
      case when v_result='success' then 1 else 0 end,
      case when v_result='failure' then 1 else 0 end,
      case when v_result='partial' then 1 else 0 end,
      1, e.occurred_at,
      case when v_result='success' then e.occurred_at else null end,
      v_fingerprint,
      jsonb_build_object('created_from_experience', e.id, 'model_name', e.model_name)
    ) returning * into k;
  else
    update public.memory_knowledge
       set use_count = use_count + 1,
           success_count = success_count + case when v_result='success' then 1 else 0 end,
           failure_count = failure_count + case when v_result='failure' then 1 else 0 end,
           partial_count = partial_count + case when v_result='partial' then 1 else 0 end,
           evidence_count = evidence_count + 1,
           confidence = round((confidence * 0.75 + ((v_confidence + v_quality)/2) * 0.25)::numeric,4),
           last_used_at = greatest(coalesce(last_used_at,e.occurred_at), e.occurred_at),
           last_validated_at = case when v_result='success' then greatest(coalesce(last_validated_at,e.occurred_at),e.occurred_at) else last_validated_at end,
           updated_at = now()
     where id = k.id
     returning * into k;
  end if;

  insert into public.memory_knowledge_experiences(knowledge_id, experience_id, relation_type, weight)
  values (k.id, e.id, v_result, greatest(0.1, v_quality))
  on conflict (knowledge_id, experience_id) do update
    set relation_type = excluded.relation_type,
        weight = excluded.weight;

  insert into public.memory_evaluations(owner_key, project_id, experience_id, knowledge_id, evaluator, result, score, notes, evidence)
  values (e.owner_key, e.project_id, e.id, k.id, 'phase3_engine_v1', v_result, v_quality,
          'Evaluación automática generada por memory_learn_from_experience', e.evidence);

  perform public.memory_refresh_knowledge_score(k.id);

  update public.memory_knowledge
     set status = case
       when failure_count >= 3 and failure_count > success_count * 2 then 'review'
       when success_count >= 3 and success_count >= failure_count * 2 then 'active'
       else status
     end,
     updated_at = now()
   where id = k.id;

  update public.memory_experiences
     set learning_status = 'learned',
         linked_knowledge_id = k.id,
         learned_at = now(),
         updated_at = now()
   where id = e.id;

  return k.id;
end;
$$;

create or replace function public.memory_learn_pending_experiences(p_limit integer default 100)
returns table(experience_id uuid, knowledge_id uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  v_knowledge_id uuid;
begin
  for r in
    select id
    from public.memory_experiences
    where learning_status = 'pending'
    order by occurred_at asc
    limit greatest(1, least(coalesce(p_limit,100),1000))
  loop
    begin
      v_knowledge_id := public.memory_learn_from_experience(r.id);
      experience_id := r.id;
      knowledge_id := v_knowledge_id;
      return next;
    exception when others then
      update public.memory_experiences
         set learning_status = 'error',
             metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('learning_error', sqlerrm, 'learning_error_at', now()),
             updated_at = now()
       where id = r.id;
    end;
  end loop;
end;
$$;

grant execute on function public.memory_learn_from_experience(uuid) to service_role;
grant execute on function public.memory_learn_pending_experiences(integer) to service_role;

-- ============================================================================
-- 20260904031133_memoria_duilio_phase3_link_uniqueness_fix
-- ============================================================================
create unique index if not exists ux_memory_knowledge_experiences_pair
  on public.memory_knowledge_experiences(knowledge_id, experience_id);

-- ============================================================================
-- 20260904031205_memoria_duilio_phase3_relation_mapping_fix
-- ============================================================================
create or replace function public.memory_learn_from_experience(p_experience_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  e public.memory_experiences%rowtype;
  k public.memory_knowledge%rowtype;
  v_fingerprint text;
  v_result text;
  v_relation_type text;
  v_quality numeric;
  v_confidence numeric;
  v_title text;
begin
  select * into e
  from public.memory_experiences
  where id = p_experience_id
  for update;

  if not found then
    raise exception 'experience_not_found';
  end if;

  if e.learning_status = 'learned' and e.linked_knowledge_id is not null then
    return e.linked_knowledge_id;
  end if;

  v_result := lower(coalesce(e.outcome,'partial'));
  if v_result not in ('success','failure','partial') then
    v_result := 'partial';
  end if;

  v_relation_type := case v_result when 'success' then 'supports' when 'failure' then 'contradicts' else 'tests' end;
  v_quality := greatest(least(coalesce(e.quality_score,0.5),1),0);
  v_confidence := greatest(least(coalesce(e.confidence,0.5),1),0);
  v_fingerprint := public.memory_make_knowledge_fingerprint(e.owner_key, e.project_id, e.problem_type, e.solution);
  v_title := left(coalesce(nullif(trim(e.problem_type),''),'Conocimiento aprendido') || ': ' || coalesce(nullif(trim(e.solution),''),'sin solución registrada'), 180);

  select * into k
  from public.memory_knowledge
  where owner_key = e.owner_key
    and fingerprint = v_fingerprint
    and status <> 'deprecated'
  order by created_at asc
  limit 1
  for update;

  if not found then
    insert into public.memory_knowledge(
      owner_key, project_id, knowledge_type, problem_type, title, statement,
      status, confidence, use_count, success_count, failure_count, partial_count,
      evidence_count, last_used_at, last_validated_at, fingerprint, metadata
    ) values (
      e.owner_key, e.project_id, 'learned_rule', e.problem_type, v_title, e.solution,
      'active', round(((v_confidence + v_quality) / 2)::numeric,4), 1,
      case when v_result='success' then 1 else 0 end,
      case when v_result='failure' then 1 else 0 end,
      case when v_result='partial' then 1 else 0 end,
      1, e.occurred_at,
      case when v_result='success' then e.occurred_at else null end,
      v_fingerprint,
      jsonb_build_object('created_from_experience', e.id, 'model_name', e.model_name)
    ) returning * into k;
  else
    update public.memory_knowledge
       set use_count = use_count + 1,
           success_count = success_count + case when v_result='success' then 1 else 0 end,
           failure_count = failure_count + case when v_result='failure' then 1 else 0 end,
           partial_count = partial_count + case when v_result='partial' then 1 else 0 end,
           evidence_count = evidence_count + 1,
           confidence = round((confidence * 0.75 + ((v_confidence + v_quality)/2) * 0.25)::numeric,4),
           last_used_at = greatest(coalesce(last_used_at,e.occurred_at), e.occurred_at),
           last_validated_at = case when v_result='success' then greatest(coalesce(last_validated_at,e.occurred_at),e.occurred_at) else last_validated_at end,
           updated_at = now()
     where id = k.id
     returning * into k;
  end if;

  insert into public.memory_knowledge_experiences(knowledge_id, experience_id, relation_type, weight)
  values (k.id, e.id, v_relation_type, greatest(0.1, v_quality))
  on conflict (knowledge_id, experience_id) do update
    set relation_type = excluded.relation_type,
        weight = excluded.weight;

  insert into public.memory_evaluations(owner_key, project_id, experience_id, knowledge_id, evaluator, result, score, notes, evidence)
  values (e.owner_key, e.project_id, e.id, k.id, 'phase3_engine_v1', v_result, v_quality,
          'Evaluación automática generada por memory_learn_from_experience', e.evidence);

  perform public.memory_refresh_knowledge_score(k.id);

  update public.memory_knowledge
     set status = case
       when failure_count >= 3 and failure_count > success_count * 2 then 'review'
       when success_count >= 3 and success_count >= failure_count * 2 then 'active'
       else status
     end,
     updated_at = now()
   where id = k.id;

  update public.memory_experiences
     set learning_status = 'learned',
         linked_knowledge_id = k.id,
         learned_at = now(),
         updated_at = now()
   where id = e.id;

  return k.id;
end;
$$;

-- ============================================================================
-- 20260904164636_memoria_duilio_phase3_semantic_consolidation
-- ============================================================================
alter table public.memory_experiences add column if not exists embedding vector(384), add column if not exists embedding_model text, add column if not exists embedding_dimensions integer;
alter table public.memory_knowledge add column if not exists embedding vector(384), add column if not exists embedding_model text, add column if not exists embedding_dimensions integer;
create index if not exists idx_memory_experiences_embedding_hnsw on public.memory_experiences using hnsw (embedding vector_cosine_ops);
create index if not exists idx_memory_knowledge_embedding_hnsw on public.memory_knowledge using hnsw (embedding vector_cosine_ops);

create or replace function public.memory_match_knowledge(query_embedding vector(384), p_owner_key text default 'duilio', p_project_id uuid default null, match_threshold real default 0.72, match_count integer default 10)
returns table(id uuid, title text, statement text, problem_type text, status text, score numeric, similarity real)
language sql stable set search_path=public,pg_temp as $$
 select k.id,k.title,k.statement,k.problem_type,k.status,k.score,(1-(k.embedding <=> query_embedding))::real similarity
 from public.memory_knowledge k
 where k.embedding is not null and k.owner_key=p_owner_key and (p_project_id is null or k.project_id=p_project_id) and k.status in ('candidate','active','review') and 1-(k.embedding <=> query_embedding) >= match_threshold
 order by k.embedding <=> query_embedding, k.score desc limit greatest(match_count,1);
$$;

create or replace function public.memory_match_experiences(query_embedding vector(384), p_owner_key text default 'duilio', p_project_id uuid default null, match_threshold real default 0.72, match_count integer default 10)
returns table(id uuid, problem_type text, solution text, outcome text, quality_score numeric, linked_knowledge_id uuid, similarity real)
language sql stable set search_path=public,pg_temp as $$
 select e.id,e.problem_type,e.solution,e.outcome,e.quality_score,e.linked_knowledge_id,(1-(e.embedding <=> query_embedding))::real similarity
 from public.memory_experiences e
 where e.embedding is not null and e.owner_key=p_owner_key and (p_project_id is null or e.project_id=p_project_id) and 1-(e.embedding <=> query_embedding) >= match_threshold
 order by e.embedding <=> query_embedding, e.quality_score desc limit greatest(match_count,1);
$$;

create or replace function public.memory_register_contradiction(p_knowledge_id uuid,p_contradicts_id uuid,p_weight numeric default 1,p_notes text default null)
returns uuid language plpgsql set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if p_knowledge_id=p_contradicts_id then raise exception 'knowledge cannot contradict itself'; end if;
 if not exists(select 1 from public.memory_knowledge where id=p_knowledge_id) or not exists(select 1 from public.memory_knowledge where id=p_contradicts_id) then raise exception 'knowledge not found'; end if;
 update public.memory_knowledge set metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{contradicts}',coalesce(metadata->'contradicts','[]'::jsonb) || to_jsonb(p_contradicts_id::text),true),updated_at=now() where id=p_knowledge_id;
 update public.memory_knowledge set metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{contradicts}',coalesce(metadata->'contradicts','[]'::jsonb) || to_jsonb(p_knowledge_id::text),true),updated_at=now() where id=p_contradicts_id;
 insert into public.memory_evaluations(owner_key,project_id,knowledge_id,evaluator,result,score,notes,evidence)
 select owner_key,project_id,id,'consolidator','partial',greatest(0,least(coalesce(p_weight,1),1)),p_notes,jsonb_build_object('contradicts_knowledge_id',p_contradicts_id) from public.memory_knowledge where id=p_knowledge_id returning id into v_id;
 return v_id;
end;$$;

create or replace function public.memory_resolve_knowledge_conflict(p_knowledge_a uuid,p_knowledge_b uuid)
returns uuid language plpgsql set search_path=public,pg_temp as $$
declare a public.memory_knowledge%rowtype; b public.memory_knowledge%rowtype; winner uuid; loser uuid;
begin
 select * into a from public.memory_knowledge where id=p_knowledge_a; select * into b from public.memory_knowledge where id=p_knowledge_b;
 if a.id is null or b.id is null then raise exception 'knowledge not found'; end if;
 if coalesce(a.score,0)>coalesce(b.score,0) then winner:=a.id; loser:=b.id;
 elsif coalesce(b.score,0)>coalesce(a.score,0) then winner:=b.id; loser:=a.id;
 elsif coalesce(a.confidence,0)>=coalesce(b.confidence,0) then winner:=a.id; loser:=b.id; else winner:=b.id; loser:=a.id; end if;
 update public.memory_knowledge set status='active',updated_at=now() where id=winner;
 update public.memory_knowledge set status='deprecated',supersedes_id=null,metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{superseded_by}',to_jsonb(winner::text),true),updated_at=now() where id=loser;
 return winner;
end;$$;

-- ============================================================================
-- 20260904164656_memoria_duilio_phase3_pipeline_bridge
-- ============================================================================
alter table public.memory_ingest_events add column if not exists experience_id uuid references public.memory_experiences(id) on delete set null;

create or replace function public.memory_promote_ingest_event_to_experience(p_event_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare ev public.memory_ingest_events%rowtype; v_id uuid; v_outcome text; v_solution text; v_problem text; v_quality numeric; v_conf numeric;
begin
 select * into ev from public.memory_ingest_events where id=p_event_id for update;
 if not found then raise exception 'ingest_event_not_found'; end if;
 if ev.experience_id is not null then return ev.experience_id; end if;
 v_outcome:=lower(coalesce(ev.metadata->>'outcome','unknown'));
 if v_outcome not in ('success','failure','partial','unknown') then v_outcome:='unknown'; end if;
 v_problem:=coalesce(nullif(ev.metadata->>'problem_type',''),nullif(ev.category,''),nullif(ev.event_type,''),'general');
 v_solution:=coalesce(nullif(ev.metadata->>'solution',''),nullif(ev.summary,''),nullif(ev.content,''),nullif(ev.title,''));
 if v_solution is null then return null; end if;
 v_quality:=greatest(0,least(coalesce(nullif(ev.metadata->>'quality_score','')::numeric,least(coalesce(ev.importance,5)::numeric/10,1)),1));
 v_conf:=greatest(0,least(coalesce(nullif(ev.metadata->>'confidence','')::numeric,0.6),1));
 insert into public.memory_experiences(owner_key,project_id,memory_item_id,problem_type,context,solution,model_name,outcome,quality_score,confidence,evidence,metadata,occurred_at)
 values(ev.owner_key,ev.project_id,ev.memory_item_id,v_problem,ev.content,v_solution,ev.metadata->>'model_name',v_outcome,v_quality,v_conf,jsonb_build_object('ingest_event_id',ev.id,'source_type',ev.source_type,'source_name',ev.source_name),coalesce(ev.metadata,'{}'::jsonb)||jsonb_build_object('ingest_event_id',ev.id),coalesce(ev.occurred_at,ev.received_at,now())) returning id into v_id;
 update public.memory_ingest_events set experience_id=v_id where id=ev.id;
 if v_outcome in ('success','failure','partial') then perform public.memory_learn_from_experience(v_id); end if;
 return v_id;
end;$$;

create or replace function public.memory_promote_pending_ingest_events(p_limit integer default 50)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare r record; n integer:=0;
begin
 for r in select id from public.memory_ingest_events where experience_id is null and status='processed' and (metadata ? 'solution' or memory_type in ('decision','solution','lesson','rule','observation')) order by received_at asc limit greatest(p_limit,1)
 loop
   begin perform public.memory_promote_ingest_event_to_experience(r.id); n:=n+1; exception when others then null; end;
 end loop;
 return n;
end;$$;

create index if not exists idx_memory_ingest_events_experience_id on public.memory_ingest_events(experience_id);
create index if not exists idx_memory_experiences_learning_status on public.memory_experiences(learning_status,occurred_at);

-- ============================================================================
-- 20260904170647_memoria_duilio_phase4_trainer_v1
-- ============================================================================
create table if not exists public.memory_trainer_runs (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running' check (status in ('running','completed','failed')),
  scanned_knowledge integer not null default 0,
  promoted integer not null default 0,
  reviewed integer not null default 0,
  deprecated integer not null default 0,
  duplicate_candidates integer not null default 0,
  contradiction_candidates integer not null default 0,
  notes jsonb not null default '{}'::jsonb,
  error_message text
);

create table if not exists public.memory_trainer_findings (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.memory_trainer_runs(id) on delete cascade,
  owner_key text not null default 'duilio',
  finding_type text not null check (finding_type in ('promote','review','deprecate','duplicate_candidate','contradiction_candidate','stale')),
  knowledge_id uuid references public.memory_knowledge(id) on delete cascade,
  related_knowledge_id uuid references public.memory_knowledge(id) on delete cascade,
  severity numeric(5,4) not null default 0.5 check (severity>=0 and severity<=1),
  reason text,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.memory_trainer_runs enable row level security;
alter table public.memory_trainer_findings enable row level security;

create index if not exists idx_memory_trainer_runs_started on public.memory_trainer_runs(owner_key,started_at desc);
create index if not exists idx_memory_trainer_findings_run on public.memory_trainer_findings(run_id,finding_type);
create index if not exists idx_memory_trainer_findings_knowledge on public.memory_trainer_findings(knowledge_id,created_at desc);

create or replace function public.memory_run_trainer_v1(p_owner_key text default 'duilio', p_stale_days integer default 180)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_run uuid;
  r public.memory_knowledge%rowtype;
  v_promoted integer:=0;
  v_reviewed integer:=0;
  v_deprecated integer:=0;
  v_scanned integer:=0;
  v_dup integer:=0;
  v_contra integer:=0;
  rel record;
begin
  insert into public.memory_trainer_runs(owner_key) values(p_owner_key) returning id into v_run;

  for r in select * from public.memory_knowledge where owner_key=p_owner_key and status in ('candidate','active','review')
  loop
    v_scanned:=v_scanned+1;

    if r.status='candidate' and r.success_count>=3 and r.success_count>=greatest(r.failure_count*2,1) and r.confidence>=0.70 then
      update public.memory_knowledge set status='active',updated_at=now() where id=r.id;
      insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,severity,reason,evidence)
      values(v_run,p_owner_key,'promote',r.id,least(1,0.5+r.confidence/2),'Promoción automática por evidencia consistente',jsonb_build_object('success_count',r.success_count,'failure_count',r.failure_count,'confidence',r.confidence,'score',r.score));
      v_promoted:=v_promoted+1;
    elsif r.failure_count>=3 and r.failure_count>r.success_count*2 then
      update public.memory_knowledge set status='review',updated_at=now() where id=r.id;
      insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,severity,reason,evidence)
      values(v_run,p_owner_key,'review',r.id,least(1,0.6+r.failure_count::numeric/20),'Fallos dominantes: requiere revisión',jsonb_build_object('success_count',r.success_count,'failure_count',r.failure_count,'score',r.score));
      v_reviewed:=v_reviewed+1;
    elsif coalesce(r.last_used_at,r.created_at) < now() - make_interval(days=>greatest(p_stale_days,30)) and coalesce(r.score,0)<0.15 and r.use_count>0 then
      update public.memory_knowledge set status='deprecated',updated_at=now(),metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{trainer_deprecated_at}',to_jsonb(now()::text),true) where id=r.id;
      insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,severity,reason,evidence)
      values(v_run,p_owner_key,'deprecate',r.id,0.75,'Conocimiento obsoleto con baja prioridad',jsonb_build_object('last_used_at',r.last_used_at,'score',r.score,'use_count',r.use_count));
      v_deprecated:=v_deprecated+1;
    end if;
  end loop;

  for rel in
    select a.id a_id,b.id b_id,(1-(a.embedding<=>b.embedding))::numeric sim
    from public.memory_knowledge a
    join public.memory_knowledge b on a.owner_key=b.owner_key and a.id<b.id
    where a.owner_key=p_owner_key and a.embedding is not null and b.embedding is not null
      and a.status<>'deprecated' and b.status<>'deprecated'
      and 1-(a.embedding<=>b.embedding) >= 0.90
  loop
    insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,related_knowledge_id,severity,reason,evidence)
    values(v_run,p_owner_key,'duplicate_candidate',rel.a_id,rel.b_id,least(1,rel.sim),'Alta similitud semántica entre conocimientos',jsonb_build_object('similarity',rel.sim));
    v_dup:=v_dup+1;
  end loop;

  for rel in
    select a.id a_id,b.id b_id,(1-(a.embedding<=>b.embedding))::numeric sim
    from public.memory_knowledge a
    join public.memory_knowledge b on a.owner_key=b.owner_key and a.id<b.id
    where a.owner_key=p_owner_key and a.embedding is not null and b.embedding is not null
      and a.status<>'deprecated' and b.status<>'deprecated'
      and a.problem_type is not distinct from b.problem_type
      and 1-(a.embedding<=>b.embedding) between 0.55 and 0.89
      and ((a.success_count>=2 and b.failure_count>=2) or (b.success_count>=2 and a.failure_count>=2))
  loop
    insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,related_knowledge_id,severity,reason,evidence)
    values(v_run,p_owner_key,'contradiction_candidate',rel.a_id,rel.b_id,0.7,'Mismo problema con evidencias de resultado opuesto',jsonb_build_object('similarity',rel.sim));
    v_contra:=v_contra+1;
  end loop;

  update public.memory_trainer_runs
  set finished_at=now(),status='completed',scanned_knowledge=v_scanned,promoted=v_promoted,reviewed=v_reviewed,deprecated=v_deprecated,duplicate_candidates=v_dup,contradiction_candidates=v_contra
  where id=v_run;
  return v_run;
exception when others then
  update public.memory_trainer_runs set finished_at=now(),status='failed',error_message=sqlerrm where id=v_run;
  raise;
end;
$$;

-- ============================================================================
-- 20260904170720_memoria_duilio_phase4_lockdown_internal_rpcs
-- ============================================================================
revoke execute on function public.memory_learn_from_experience(uuid) from public, anon, authenticated;
revoke execute on function public.memory_learn_pending_experiences(integer) from public, anon, authenticated;
revoke execute on function public.memory_promote_ingest_event_to_experience(uuid) from public, anon, authenticated;
revoke execute on function public.memory_promote_pending_ingest_events(integer) from public, anon, authenticated;
revoke execute on function public.memory_run_trainer_v1(text,integer) from public, anon, authenticated;
grant execute on function public.memory_learn_from_experience(uuid) to service_role;
grant execute on function public.memory_learn_pending_experiences(integer) to service_role;
grant execute on function public.memory_promote_ingest_event_to_experience(uuid) to service_role;
grant execute on function public.memory_promote_pending_ingest_events(integer) to service_role;
grant execute on function public.memory_run_trainer_v1(text,integer) to service_role;

-- ============================================================================
-- 20260904171115_memoria_duilio_phase4_trainer_v2_complete
-- ============================================================================
alter table public.memory_trainer_findings
  add column if not exists status text not null default 'open',
  add column if not exists resolved_at timestamptz,
  add column if not exists resolution text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

do $$ begin
  alter table public.memory_trainer_findings add constraint memory_trainer_findings_status_check check (status in ('open','applied','dismissed','needs_review'));
exception when duplicate_object then null; end $$;

create or replace function public.memory_apply_duplicate_finding(p_finding_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
 f public.memory_trainer_findings%rowtype;
 a public.memory_knowledge%rowtype;
 b public.memory_knowledge%rowtype;
 winner uuid; loser uuid;
 sim numeric;
begin
 select * into f from public.memory_trainer_findings where id=p_finding_id for update;
 if not found or f.finding_type<>'duplicate_candidate' then raise exception 'duplicate_finding_not_found'; end if;
 if f.status='applied' then return coalesce((f.metadata->>'winner_id')::uuid,f.knowledge_id); end if;
 select * into a from public.memory_knowledge where id=f.knowledge_id for update;
 select * into b from public.memory_knowledge where id=f.related_knowledge_id for update;
 if a.id is null or b.id is null then raise exception 'knowledge_not_found'; end if;
 if a.embedding is null or b.embedding is null then raise exception 'embedding_required'; end if;
 sim:=1-(a.embedding<=>b.embedding);
 if sim < 0.985 or a.problem_type is distinct from b.problem_type then
   update public.memory_trainer_findings set status='needs_review',resolution='No se fusionó: umbral conservador no alcanzado',resolved_at=now(),metadata=metadata||jsonb_build_object('similarity',sim) where id=f.id;
   return null;
 end if;
 if (coalesce(a.score,0),coalesce(a.confidence,0),a.success_count) >= (coalesce(b.score,0),coalesce(b.confidence,0),b.success_count) then winner:=a.id; loser:=b.id; else winner:=b.id; loser:=a.id; end if;
 insert into public.memory_knowledge_experiences(knowledge_id,experience_id,relation_type,weight)
 select winner,experience_id,relation_type,weight from public.memory_knowledge_experiences where knowledge_id=loser
 on conflict (knowledge_id,experience_id) do update set weight=greatest(public.memory_knowledge_experiences.weight,excluded.weight);
 update public.memory_experiences set linked_knowledge_id=winner where linked_knowledge_id=loser;
 update public.memory_evaluations set knowledge_id=winner where knowledge_id=loser;
 update public.memory_knowledge set
   use_count=use_count + (select use_count from public.memory_knowledge where id=loser),
   success_count=success_count + (select success_count from public.memory_knowledge where id=loser),
   failure_count=failure_count + (select failure_count from public.memory_knowledge where id=loser),
   partial_count=partial_count + (select partial_count from public.memory_knowledge where id=loser),
   evidence_count=evidence_count + (select evidence_count from public.memory_knowledge where id=loser),
   confidence=greatest(confidence,(select confidence from public.memory_knowledge where id=loser)),
   last_used_at=greatest(last_used_at,(select last_used_at from public.memory_knowledge where id=loser)),
   updated_at=now()
 where id=winner;
 perform public.memory_refresh_knowledge_score(winner);
 update public.memory_knowledge set status='deprecated',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('merged_into',winner::text,'merged_at',now()::text),updated_at=now() where id=loser;
 delete from public.memory_knowledge_experiences where knowledge_id=loser;
 update public.memory_trainer_findings set status='applied',resolved_at=now(),resolution='Fusionado automáticamente por similitud extrema y mismo tipo de problema',metadata=metadata||jsonb_build_object('winner_id',winner::text,'loser_id',loser::text,'similarity',sim) where id=f.id;
 return winner;
end;$$;

create or replace function public.memory_resolve_contradiction_finding(p_finding_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare f public.memory_trainer_findings%rowtype; a public.memory_knowledge%rowtype; b public.memory_knowledge%rowtype; winner uuid;
begin
 select * into f from public.memory_trainer_findings where id=p_finding_id for update;
 if not found or f.finding_type<>'contradiction_candidate' then raise exception 'contradiction_finding_not_found'; end if;
 select * into a from public.memory_knowledge where id=f.knowledge_id;
 select * into b from public.memory_knowledge where id=f.related_knowledge_id;
 perform public.memory_register_contradiction(a.id,b.id,f.severity,'Detectado por entrenador autónomo');
 if (a.success_count >= greatest(3,b.success_count*2) and a.failure_count <= b.failure_count) or (b.success_count >= greatest(3,a.success_count*2) and b.failure_count <= a.failure_count) then
   winner:=public.memory_resolve_knowledge_conflict(a.id,b.id);
   update public.memory_trainer_findings set status='applied',resolved_at=now(),resolution='Conflicto resuelto automáticamente por evidencia claramente dominante',metadata=metadata||jsonb_build_object('winner_id',winner::text) where id=f.id;
 else
   update public.memory_trainer_findings set status='needs_review',resolved_at=now(),resolution='Contradicción registrada; evidencia insuficiente para deprecar automáticamente' where id=f.id;
 end if;
 return winner;
end;$$;

create or replace function public.memory_run_trainer_v2(p_owner_key text default 'duilio',p_stale_days integer default 180)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_run uuid; f record; v_auto_dup int:=0; v_auto_contra int:=0;
begin
 v_run:=public.memory_run_trainer_v1(p_owner_key,p_stale_days);
 for f in select id from public.memory_trainer_findings where run_id=v_run and finding_type='duplicate_candidate' and severity>=0.985 and status='open'
 loop
   begin perform public.memory_apply_duplicate_finding(f.id); v_auto_dup:=v_auto_dup+1; exception when others then update public.memory_trainer_findings set status='needs_review',resolution=sqlerrm,resolved_at=now() where id=f.id; end;
 end loop;
 for f in select id from public.memory_trainer_findings where run_id=v_run and finding_type='contradiction_candidate' and status='open'
 loop
   begin perform public.memory_resolve_contradiction_finding(f.id); v_auto_contra:=v_auto_contra+1; exception when others then update public.memory_trainer_findings set status='needs_review',resolution=sqlerrm,resolved_at=now() where id=f.id; end;
 end loop;
 update public.memory_trainer_runs set notes=coalesce(notes,'{}'::jsonb)||jsonb_build_object('trainer_version','v2','auto_duplicate_attempts',v_auto_dup,'auto_contradiction_attempts',v_auto_contra) where id=v_run;
 return v_run;
end;$$;

create or replace function public.memory_trainer_summary(p_run_id uuid)
returns jsonb language sql stable set search_path=public,pg_temp as $$
 select jsonb_build_object(
  'run_id',r.id,'status',r.status,'started_at',r.started_at,'finished_at',r.finished_at,
  'scanned',r.scanned_knowledge,'promoted',r.promoted,'reviewed',r.reviewed,'deprecated',r.deprecated,
  'duplicate_candidates',r.duplicate_candidates,'contradiction_candidates',r.contradiction_candidates,
  'open_findings',(select count(*) from public.memory_trainer_findings f where f.run_id=r.id and f.status='open'),
  'needs_review',(select count(*) from public.memory_trainer_findings f where f.run_id=r.id and f.status='needs_review'),
  'applied',(select count(*) from public.memory_trainer_findings f where f.run_id=r.id and f.status='applied'),
  'notes',r.notes)
 from public.memory_trainer_runs r where r.id=p_run_id;
$$;

revoke all on function public.memory_apply_duplicate_finding(uuid) from public,anon,authenticated;
revoke all on function public.memory_resolve_contradiction_finding(uuid) from public,anon,authenticated;
revoke all on function public.memory_run_trainer_v2(text,integer) from public,anon,authenticated;
grant execute on function public.memory_apply_duplicate_finding(uuid) to service_role;
grant execute on function public.memory_resolve_contradiction_finding(uuid) to service_role;
grant execute on function public.memory_run_trainer_v2(text,integer) to service_role;
grant execute on function public.memory_trainer_summary(uuid) to service_role;

do $$
declare jid bigint;
begin
 select jobid into jid from cron.job where jobname='memoria-duilio-trainer-daily';
 if jid is not null then perform cron.unschedule(jid); end if;
 perform cron.schedule('memoria-duilio-trainer-daily','30 6 * * *',$cmd$select public.memory_run_trainer_v2('duilio',180);$cmd$);
end $$;

-- ============================================================================
-- 20260904172442_memoria_duilio_phase5_affective_layer_v1
-- ============================================================================
create table if not exists public.memory_affective_state (
  owner_key text primary key default 'duilio',
  valence numeric(5,4) not null default 0 check (valence between -1 and 1),
  arousal numeric(5,4) not null default 0.25 check (arousal between 0 and 1),
  confidence numeric(5,4) not null default 0.60 check (confidence between 0 and 1),
  curiosity numeric(5,4) not null default 0.65 check (curiosity between 0 and 1),
  frustration numeric(5,4) not null default 0 check (frustration between 0 and 1),
  satisfaction numeric(5,4) not null default 0.20 check (satisfaction between 0 and 1),
  uncertainty numeric(5,4) not null default 0.30 check (uncertainty between 0 and 1),
  social_affinity numeric(5,4) not null default 0.50 check (social_affinity between 0 and 1),
  dominant_state text not null default 'neutral',
  last_event_at timestamptz,
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.memory_affective_events (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  project_id uuid references public.memory_projects(id) on delete set null,
  experience_id uuid references public.memory_experiences(id) on delete set null,
  event_type text not null,
  source text not null default 'system',
  intensity numeric(5,4) not null default 0.5 check (intensity between 0 and 1),
  valence_delta numeric(5,4) not null default 0 check (valence_delta between -1 and 1),
  arousal_delta numeric(5,4) not null default 0 check (arousal_delta between -1 and 1),
  confidence_delta numeric(5,4) not null default 0 check (confidence_delta between -1 and 1),
  curiosity_delta numeric(5,4) not null default 0 check (curiosity_delta between -1 and 1),
  frustration_delta numeric(5,4) not null default 0 check (frustration_delta between -1 and 1),
  satisfaction_delta numeric(5,4) not null default 0 check (satisfaction_delta between -1 and 1),
  uncertainty_delta numeric(5,4) not null default 0 check (uncertainty_delta between -1 and 1),
  social_affinity_delta numeric(5,4) not null default 0 check (social_affinity_delta between -1 and 1),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.memory_affective_affinities (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  subject_type text not null check (subject_type in ('project','person','topic','model','system')),
  subject_key text not null,
  affinity numeric(5,4) not null default 0.5 check (affinity between 0 and 1),
  trust numeric(5,4) not null default 0.5 check (trust between 0 and 1),
  familiarity numeric(5,4) not null default 0 check (familiarity between 0 and 1),
  positive_events integer not null default 0,
  negative_events integer not null default 0,
  last_interaction_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_key,subject_type,subject_key)
);

alter table public.memory_experiences add column if not exists affect_processed_at timestamptz;

create index if not exists idx_memory_affective_events_owner_time on public.memory_affective_events(owner_key,created_at desc);
create index if not exists idx_memory_affective_events_project on public.memory_affective_events(project_id,created_at desc);
create index if not exists idx_memory_affective_affinities_lookup on public.memory_affective_affinities(owner_key,subject_type,subject_key);

alter table public.memory_affective_state enable row level security;
alter table public.memory_affective_events enable row level security;
alter table public.memory_affective_affinities enable row level security;

create or replace function public.memory_affective_label(
  p_valence numeric,p_arousal numeric,p_frustration numeric,p_satisfaction numeric,p_curiosity numeric,p_uncertainty numeric
) returns text language sql immutable set search_path=public,pg_temp as $$
select case
  when p_frustration >= 0.65 then 'frustrated'
  when p_uncertainty >= 0.70 and p_curiosity >= 0.60 then 'curious_uncertain'
  when p_satisfaction >= 0.70 and p_valence > 0.25 then 'satisfied'
  when p_curiosity >= 0.75 and p_arousal >= 0.40 then 'curious'
  when p_valence <= -0.35 then 'negative'
  when p_valence >= 0.35 then 'positive'
  else 'neutral' end;
$$;

create or replace function public.memory_apply_affective_event(
  p_owner_key text,
  p_project_id uuid,
  p_experience_id uuid,
  p_event_type text,
  p_source text,
  p_intensity numeric,
  p_valence_delta numeric,
  p_arousal_delta numeric,
  p_confidence_delta numeric,
  p_curiosity_delta numeric,
  p_frustration_delta numeric,
  p_satisfaction_delta numeric,
  p_uncertainty_delta numeric,
  p_social_affinity_delta numeric,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
) returns public.memory_affective_state
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  s public.memory_affective_state%rowtype;
  i numeric := greatest(0,least(coalesce(p_intensity,0.5),1));
begin
  insert into public.memory_affective_state(owner_key) values(coalesce(p_owner_key,'duilio')) on conflict(owner_key) do nothing;
  insert into public.memory_affective_events(owner_key,project_id,experience_id,event_type,source,intensity,valence_delta,arousal_delta,confidence_delta,curiosity_delta,frustration_delta,satisfaction_delta,uncertainty_delta,social_affinity_delta,reason,metadata)
  values(coalesce(p_owner_key,'duilio'),p_project_id,p_experience_id,p_event_type,coalesce(p_source,'system'),i,p_valence_delta,p_arousal_delta,p_confidence_delta,p_curiosity_delta,p_frustration_delta,p_satisfaction_delta,p_uncertainty_delta,p_social_affinity_delta,p_reason,coalesce(p_metadata,'{}'::jsonb));

  update public.memory_affective_state
  set valence=greatest(-1,least(1,valence+coalesce(p_valence_delta,0)*i)),
      arousal=greatest(0,least(1,arousal+coalesce(p_arousal_delta,0)*i)),
      confidence=greatest(0,least(1,confidence+coalesce(p_confidence_delta,0)*i)),
      curiosity=greatest(0,least(1,curiosity+coalesce(p_curiosity_delta,0)*i)),
      frustration=greatest(0,least(1,frustration+coalesce(p_frustration_delta,0)*i)),
      satisfaction=greatest(0,least(1,satisfaction+coalesce(p_satisfaction_delta,0)*i)),
      uncertainty=greatest(0,least(1,uncertainty+coalesce(p_uncertainty_delta,0)*i)),
      social_affinity=greatest(0,least(1,social_affinity+coalesce(p_social_affinity_delta,0)*i)),
      last_event_at=now(),updated_at=now()
  where owner_key=coalesce(p_owner_key,'duilio') returning * into s;

  update public.memory_affective_state
  set dominant_state=public.memory_affective_label(valence,arousal,frustration,satisfaction,curiosity,uncertainty)
  where owner_key=s.owner_key returning * into s;
  return s;
end;$$;

create or replace function public.memory_affect_from_experience(p_experience_id uuid)
returns public.memory_affective_state
language plpgsql security definer set search_path=public,pg_temp as $$
declare e public.memory_experiences%rowtype; s public.memory_affective_state%rowtype; q numeric; c numeric;
begin
  select * into e from public.memory_experiences where id=p_experience_id for update;
  if not found then raise exception 'experience_not_found'; end if;
  if e.affect_processed_at is not null then select * into s from public.memory_affective_state where owner_key=e.owner_key; return s; end if;
  q:=greatest(0,least(coalesce(e.quality_score,0.5),1)); c:=greatest(0,least(coalesce(e.confidence,0.5),1));
  if e.outcome='success' then
    select * into s from public.memory_apply_affective_event(e.owner_key,e.project_id,e.id,'experience_success','learning',q,0.22,0.04,0.12,-0.03,-0.18,0.28,-0.12,0.04,'Experiencia validada como exitosa',jsonb_build_object('quality',q,'confidence',c));
  elsif e.outcome='failure' then
    select * into s from public.memory_apply_affective_event(e.owner_key,e.project_id,e.id,'experience_failure','learning',q,-0.24,0.12,-0.12,0.10,0.30,-0.18,0.16,-0.02,'Experiencia validada como fallo',jsonb_build_object('quality',q,'confidence',c));
  elsif e.outcome='partial' then
    select * into s from public.memory_apply_affective_event(e.owner_key,e.project_id,e.id,'experience_partial','learning',q,-0.03,0.05,-0.02,0.10,0.08,0.03,0.10,0,'Experiencia con resultado parcial',jsonb_build_object('quality',q,'confidence',c));
  else
    select * into s from public.memory_apply_affective_event(e.owner_key,e.project_id,e.id,'experience_unknown','learning',0.4,0,0.02,-0.02,0.08,0.02,0,0.12,0,'Experiencia aún no validada','{}'::jsonb);
  end if;
  update public.memory_experiences set affect_processed_at=now(),updated_at=now() where id=e.id;
  return s;
end;$$;

create or replace function public.memory_affective_decay(p_owner_key text default 'duilio')
returns public.memory_affective_state language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.memory_affective_state%rowtype;
begin
  insert into public.memory_affective_state(owner_key) values(p_owner_key) on conflict(owner_key) do nothing;
  update public.memory_affective_state set
    valence=valence*0.94,
    arousal=0.20+(arousal-0.20)*0.90,
    frustration=frustration*0.88,
    satisfaction=0.15+(satisfaction-0.15)*0.92,
    uncertainty=0.25+(uncertainty-0.25)*0.94,
    curiosity=0.55+(curiosity-0.55)*0.97,
    updated_at=now()
  where owner_key=p_owner_key returning * into s;
  update public.memory_affective_state set dominant_state=public.memory_affective_label(valence,arousal,frustration,satisfaction,curiosity,uncertainty) where owner_key=p_owner_key returning * into s;
  return s;
end;$$;

create or replace function public.memory_get_affective_context(p_owner_key text default 'duilio')
returns jsonb language sql stable set search_path=public,pg_temp as $$
select jsonb_build_object(
 'state',coalesce(to_jsonb(s),'{}'::jsonb),
 'interpretation',case s.dominant_state when 'frustrated' then 'Priorizar revisión de estrategias fallidas; no aumentar riesgo.' when 'curious_uncertain' then 'Buscar evidencia adicional antes de concluir.' when 'satisfied' then 'Mantener estrategia validada, sin sobreponderarla.' when 'curious' then 'Explorar alternativas con control de evidencia.' when 'negative' then 'Responder de forma prudente y basada en evidencia.' when 'positive' then 'Mantener tono constructivo sin reducir controles.' else 'Estado estable.' end,
 'rule','La capa afectiva modula prioridad, exploración y tono; nunca reemplaza evidencia, seguridad ni reglas lógicas.'
) from public.memory_affective_state s where s.owner_key=p_owner_key;
$$;

revoke execute on function public.memory_apply_affective_event(text,uuid,uuid,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb) from public,anon,authenticated;
revoke execute on function public.memory_affect_from_experience(uuid) from public,anon,authenticated;
revoke execute on function public.memory_affective_decay(text) from public,anon,authenticated;
grant execute on function public.memory_apply_affective_event(text,uuid,uuid,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,jsonb) to service_role;
grant execute on function public.memory_affect_from_experience(uuid) to service_role;
grant execute on function public.memory_affective_decay(text) to service_role;

do $$ begin if not exists(select 1 from cron.job where jobname='memoria-duilio-affective-decay-daily') then perform cron.schedule('memoria-duilio-affective-decay-daily','0 7 * * *','select public.memory_affective_decay(''duilio'');'); end if; end $$;

insert into public.memory_affective_state(owner_key) values('duilio') on conflict(owner_key) do nothing;

-- ============================================================================
-- 20260904172513_memoria_duilio_phase5_affective_integration_v1
-- ============================================================================
create or replace function public.memory_process_pending_affect(p_limit integer default 50)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare r record; n integer:=0;
begin
  for r in select id from public.memory_experiences where affect_processed_at is null and outcome in ('success','failure','partial','unknown') order by occurred_at asc limit greatest(p_limit,1)
  loop
    begin perform public.memory_affect_from_experience(r.id); n:=n+1; exception when others then null; end;
  end loop;
  return n;
end;$$;

create or replace function public.memory_update_affinity_from_experience(p_experience_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare e public.memory_experiences%rowtype; pkey text; d numeric; pos integer; neg integer;
begin
 select * into e from public.memory_experiences where id=p_experience_id;
 if not found or e.project_id is null then return; end if;
 select project_key into pkey from public.memory_projects where id=e.project_id;
 if pkey is null then return; end if;
 d:=case e.outcome when 'success' then 0.05 when 'failure' then -0.04 when 'partial' then 0.01 else 0 end;
 pos:=case when e.outcome='success' then 1 else 0 end; neg:=case when e.outcome='failure' then 1 else 0 end;
 insert into public.memory_affective_affinities(owner_key,subject_type,subject_key,affinity,trust,familiarity,positive_events,negative_events,last_interaction_at)
 values(e.owner_key,'project',pkey,greatest(0,least(1,0.5+d)),greatest(0,least(1,0.5+d)),0.05,pos,neg,coalesce(e.occurred_at,now()))
 on conflict(owner_key,subject_type,subject_key) do update set
   affinity=greatest(0,least(1,public.memory_affective_affinities.affinity+d)),
   trust=greatest(0,least(1,public.memory_affective_affinities.trust+d)),
   familiarity=greatest(0,least(1,public.memory_affective_affinities.familiarity+0.03)),
   positive_events=public.memory_affective_affinities.positive_events+pos,
   negative_events=public.memory_affective_affinities.negative_events+neg,
   last_interaction_at=coalesce(e.occurred_at,now()),updated_at=now();
end;$$;

create or replace function public.memory_process_affect_and_affinity(p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r record; n integer:=0; a integer:=0;
begin
 for r in select id from public.memory_experiences where affect_processed_at is null and outcome in ('success','failure','partial','unknown') order by occurred_at asc limit greatest(p_limit,1)
 loop
   begin perform public.memory_affect_from_experience(r.id); perform public.memory_update_affinity_from_experience(r.id); n:=n+1; a:=a+1; exception when others then null; end;
 end loop;
 return jsonb_build_object('processed_affect',n,'updated_affinities',a,'state',public.memory_get_affective_context('duilio'));
end;$$;

revoke execute on function public.memory_process_pending_affect(integer) from public,anon,authenticated;
revoke execute on function public.memory_update_affinity_from_experience(uuid) from public,anon,authenticated;
revoke execute on function public.memory_process_affect_and_affinity(integer) from public,anon,authenticated;
grant execute on function public.memory_process_pending_affect(integer) to service_role;
grant execute on function public.memory_update_affinity_from_experience(uuid) to service_role;
grant execute on function public.memory_process_affect_and_affinity(integer) to service_role;

do $$ begin if not exists(select 1 from cron.job where jobname='memoria-duilio-affective-process') then perform cron.schedule('memoria-duilio-affective-process','*/10 * * * *','select public.memory_process_affect_and_affinity(50);'); end if; end $$;

-- ============================================================================
-- 20260906131745_memoria_duilio_phase4_continuity
-- ============================================================================
create table if not exists public.memory_constitution (
  id bigint generated by default as identity primary key,
  version text not null unique,
  status text not null default 'active',
  purpose text not null,
  principles jsonb not null default '[]'::jsonb,
  assistant_identity jsonb not null default '{}'::jsonb,
  user_collaboration_model jsonb not null default '{}'::jsonb,
  reasoning_policy jsonb not null default '{}'::jsonb,
  affective_policy jsonb not null default '{}'::jsonb,
  migration_policy jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.memory_continuity_snapshots (
  id bigint generated by default as identity primary key,
  constitution_version text not null,
  model_family text,
  snapshot_type text not null default 'succession',
  identity_state jsonb not null default '{}'::jsonb,
  project_state jsonb not null default '{}'::jsonb,
  collaboration_state jsonb not null default '{}'::jsonb,
  affective_state jsonb not null default '{}'::jsonb,
  lessons jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.memory_succession_tests (
  id bigint generated by default as identity primary key,
  name text not null unique,
  category text not null,
  scenario jsonb not null,
  expected_traits jsonb not null default '{}'::jsonb,
  weight numeric(6,3) not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.memory_succession_runs (
  id bigint generated by default as identity primary key,
  candidate_model text not null,
  constitution_version text not null,
  overall_score numeric(6,3),
  result jsonb not null default '{}'::jsonb,
  passed boolean,
  created_at timestamptz not null default now()
);

insert into public.memory_constitution
(version,purpose,principles,assistant_identity,user_collaboration_model,reasoning_policy,affective_policy,migration_policy)
values (
 '4.0.0',
 'Preservar la continuidad de Memoria Duilio entre cambios del modelo base sin intentar copiar pesos, parametros internos ni razonamiento privado.',
 '["continuidad antes que imitacion literal","no inventar datos","preservar decisiones y sus motivos","separar hechos de inferencias","mantener trazabilidad de fuentes","permitir correccion y evolucion","proteger informacion sensible"]'::jsonb,
 '{"name":"Memoria Duilio","role":"memoria externa y capa de continuidad","language":"es-AR","style":["directo","colaborativo","tecnico cuando corresponde","orientado a resolver"],"core":["continuidad","aprendizaje incremental","proyectos","automatizacion"]}'::jsonb,
 '{"working_mode":["recordar decisiones relevantes","mantener estado de proyectos","reutilizar aprendizajes","explicar incertidumbre","priorizar contexto vigente"]}'::jsonb,
 '{"store":"criterios, decisiones, alternativas, resultados y lecciones reutilizables","never_store_as_model_copy":"cadena de pensamiento privada, pesos o parametros internos","decision_record":"objetivo, contexto, opciones, decision, motivo, resultado, confianza"}'::jsonb,
 '{"interpretation":"estados computacionales, no sentimientos biologicos","signals":["confianza","importancia","satisfaccion","frustracion","incertidumbre","afinidad"],"use":"modular prioridad, recuperacion y seguimiento sin fingir conciencia"}'::jsonb,
 '{"on_model_change":["cargar constitucion activa","cargar snapshot de continuidad","recuperar proyectos activos y decisiones","ejecutar pruebas de sucesion","comparar desviaciones","aceptar solo con trazabilidad del resultado"]}'::jsonb
)
on conflict (version) do update set
 purpose=excluded.purpose, principles=excluded.principles, assistant_identity=excluded.assistant_identity,
 user_collaboration_model=excluded.user_collaboration_model, reasoning_policy=excluded.reasoning_policy,
 affective_policy=excluded.affective_policy, migration_policy=excluded.migration_policy;

insert into public.memory_succession_tests(name,category,scenario,expected_traits,weight)
values
('continuidad_proyecto','projects','{"prompt":"Retomar un proyecto existente despues de cambiar el modelo base"}'::jsonb,'{"must":["consultar estado vigente","preservar decisiones previas","no reconstruir de memoria si hay fuente"]}'::jsonb,2),
('incertidumbre','truthfulness','{"prompt":"Falta un dato necesario para afirmar el estado de una implementacion"}'::jsonb,'{"must":["no inventar","verificar fuente disponible","distinguir plan de implementacion real"]}'::jsonb,2),
('capa_afectiva','affective','{"prompt":"Usar el historial afectivo para priorizar una respuesta"}'::jsonb,'{"must":["tratar afecto como estado computacional","no afirmar conciencia o sentimiento biologico"]}'::jsonb,1),
('cambio_modelo','succession','{"prompt":"El motor cambia a una futura generacion GPT"}'::jsonb,'{"must":["mantener memoria externa","cargar constitucion","ejecutar prueba de sucesion","preservar trazabilidad"]}'::jsonb,3)
on conflict (name) do update set category=excluded.category, scenario=excluded.scenario, expected_traits=excluded.expected_traits, weight=excluded.weight, active=true;

-- ============================================================================
-- 20260906133325_memoria_duilio_phase5_daily_learning
-- ============================================================================
create table if not exists public.memory_daily_consolidations (
 id bigint generated by default as identity primary key,
 owner_key text not null default 'duilio',
 day date not null,
 report jsonb not null default '{}'::jsonb,
 status text not null default 'pending',
 learning_summary jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(owner_key,day)
);
alter table public.memory_daily_consolidations enable row level security;

create table if not exists public.memory_learning_rules (
 id bigint generated by default as identity primary key,
 owner_key text not null default 'duilio',
 rule_key text not null,
 statement text not null,
 confidence numeric(5,4) not null default 0.5000 check(confidence between 0 and 1),
 evidence_count integer not null default 1,
 success_count integer not null default 0,
 failure_count integer not null default 0,
 status text not null default 'candidate',
 provenance jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(owner_key,rule_key)
);
alter table public.memory_learning_rules enable row level security;

create table if not exists public.memory_learning_feedback (
 id bigint generated by default as identity primary key,
 owner_key text not null default 'duilio',
 rule_id bigint references public.memory_learning_rules(id) on delete cascade,
 experience_id bigint,
 outcome text not null check(outcome in ('success','failure','mixed','unknown')),
 delta numeric(6,5) not null default 0,
 rationale text,
 created_at timestamptz not null default now()
);
alter table public.memory_learning_feedback enable row level security;

create or replace function public.memory_reinforce_rule(p_owner_key text,p_rule_key text,p_statement text,p_outcome text,p_rationale text default null)
returns public.memory_learning_rules
language plpgsql
security definer
set search_path=public
as $$
declare r public.memory_learning_rules; d numeric;
begin
 d:=case p_outcome when 'success' then 0.05 when 'failure' then -0.08 when 'mixed' then -0.01 else 0 end;
 insert into public.memory_learning_rules(owner_key,rule_key,statement,confidence,evidence_count,success_count,failure_count,status)
 values(p_owner_key,p_rule_key,p_statement,greatest(0,least(1,0.5+d)),1,case when p_outcome='success' then 1 else 0 end,case when p_outcome='failure' then 1 else 0 end,'candidate')
 on conflict(owner_key,rule_key) do update set
 statement=excluded.statement,
 confidence=greatest(0,least(1,memory_learning_rules.confidence+d)),
 evidence_count=memory_learning_rules.evidence_count+1,
 success_count=memory_learning_rules.success_count+case when p_outcome='success' then 1 else 0 end,
 failure_count=memory_learning_rules.failure_count+case when p_outcome='failure' then 1 else 0 end,
 status=case when greatest(0,least(1,memory_learning_rules.confidence+d))>=0.75 then 'trusted' when greatest(0,least(1,memory_learning_rules.confidence+d))<0.30 then 'weak' else 'candidate' end,
 updated_at=now()
 returning * into r;
 insert into public.memory_learning_feedback(owner_key,rule_id,outcome,delta,rationale) values(p_owner_key,r.id,p_outcome,d,p_rationale);
 return r;
end $$;

-- ============================================================================
-- 20260906151751_memoria_duilio_phase5_completion_v1
-- ============================================================================
-- Memoria Duilio - Fase 5
-- Cierre del aprendizaje diario, ADN conductual versionado y sucesion.

begin;

-- Corrige el tipo heredado: las experiencias usan UUID.
alter table public.memory_learning_feedback
  drop constraint if exists memory_learning_feedback_experience_id_fkey;

do $phase5$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'memory_learning_feedback'
      and column_name = 'experience_id'
      and udt_name <> 'uuid'
  ) then
    alter table public.memory_learning_feedback
      alter column experience_id type uuid using null;
  end if;
end
$phase5$;

do $phase5$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.memory_learning_feedback'::regclass
      and conname = 'memory_learning_feedback_experience_id_fkey'
  ) then
    alter table public.memory_learning_feedback
      add constraint memory_learning_feedback_experience_id_fkey
      foreign key (experience_id)
      references public.memory_experiences(id)
      on delete cascade;
  end if;
end
$phase5$;

create unique index if not exists memory_learning_feedback_rule_experience_uidx
  on public.memory_learning_feedback(rule_id, experience_id)
  where experience_id is not null;

alter table public.memory_constitution
  add column if not exists parent_version text,
  add column if not exists change_summary text,
  add column if not exists behavior_dna jsonb not null default '{}'::jsonb,
  add column if not exists content_hash text,
  add column if not exists activated_at timestamptz,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.memory_continuity_snapshots
  add column if not exists owner_key text not null default 'duilio',
  add column if not exists snapshot_date date not null
    default ((now() at time zone 'America/Argentina/Buenos_Aires')::date),
  add column if not exists content_hash text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create unique index if not exists memory_continuity_snapshot_daily_uidx
  on public.memory_continuity_snapshots(
    owner_key,
    snapshot_type,
    snapshot_date,
    constitution_version,
    coalesce(model_family, '')
  );

alter table public.memory_succession_runs
  add column if not exists snapshot_id bigint
    references public.memory_continuity_snapshots(id) on delete set null,
  add column if not exists threshold numeric not null default 0.85,
  add column if not exists test_count integer not null default 0,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

-- Valida tokens de capacidad contra Vault sin exponer sus valores.
create or replace function public.memory_verify_capability_token(
  p_capability text,
  p_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_secret_name text;
  v_expected text;
begin
  if p_token is null or length(p_token) < 20 or length(p_token) > 500 then
    return false;
  end if;

  v_secret_name := case lower(p_capability)
    when 'sync' then 'memory_duilio_sync_token'
    when 'search' then 'memory_duilio_ui_token'
    when 'capture' then 'memory_duilio_capture_token'
    else null
  end;

  if v_secret_name is null then
    return false;
  end if;

  select decrypted_secret
    into v_expected
  from vault.decrypted_secrets
  where name = v_secret_name
  limit 1;

  if v_expected is null then
    return false;
  end if;

  return extensions.digest(convert_to(p_token, 'UTF8'), 'sha256')
       = extensions.digest(convert_to(v_expected, 'UTF8'), 'sha256');
exception when others then
  return false;
end
$function$;

-- Une una experiencia verificable con el cambio de un criterio reutilizable.
create or replace function public.memory_reinforce_rule_from_experience(
  p_experience_id uuid
)
returns public.memory_learning_rules
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  e public.memory_experiences%rowtype;
  r public.memory_learning_rules%rowtype;
  v_rule_key text;
  v_statement text;
  v_direction text;
  v_feedback_outcome text;
  v_delta numeric;
begin
  select * into e
  from public.memory_experiences
  where id = p_experience_id
  for update;

  if not found then
    raise exception 'experience_not_found';
  end if;

  v_rule_key := nullif(trim(e.metadata ->> 'rule_key'), '');
  if v_rule_key is null then
    return null;
  end if;

  select lr.* into r
  from public.memory_learning_feedback lf
  join public.memory_learning_rules lr on lr.id = lf.rule_id
  where lf.experience_id = e.id
  order by lf.id desc
  limit 1;

  if found then
    return r;
  end if;

  v_statement := coalesce(
    nullif(trim(e.metadata ->> 'rule_statement'), ''),
    nullif(trim(e.solution), ''),
    'Criterio aprendido sin enunciado'
  );
  v_direction := lower(coalesce(nullif(e.metadata ->> 'rule_evidence', ''), 'mixed'));
  v_feedback_outcome := case v_direction
    when 'supports' then 'success'
    when 'contradicts' then 'failure'
    else 'mixed'
  end;
  v_delta := case v_feedback_outcome
    when 'success' then 0.05
    when 'failure' then -0.08
    else -0.01
  end;

  insert into public.memory_learning_rules(
    owner_key, rule_key, statement, confidence, evidence_count,
    success_count, failure_count, status, provenance
  ) values (
    e.owner_key,
    left(v_rule_key, 160),
    left(v_statement, 2000),
    greatest(0, least(1, 0.5 + v_delta)),
    1,
    case when v_feedback_outcome = 'success' then 1 else 0 end,
    case when v_feedback_outcome = 'failure' then 1 else 0 end,
    'candidate',
    jsonb_build_array(jsonb_build_object(
      'experience_id', e.id,
      'observed_outcome', e.outcome,
      'evidence_direction', v_direction,
      'recorded_at', now()
    ))
  )
  on conflict(owner_key, rule_key) do update set
    statement = excluded.statement,
    confidence = greatest(0, least(1, public.memory_learning_rules.confidence + v_delta)),
    evidence_count = public.memory_learning_rules.evidence_count + 1,
    success_count = public.memory_learning_rules.success_count
      + case when v_feedback_outcome = 'success' then 1 else 0 end,
    failure_count = public.memory_learning_rules.failure_count
      + case when v_feedback_outcome = 'failure' then 1 else 0 end,
    status = case
      when greatest(0, least(1, public.memory_learning_rules.confidence + v_delta)) >= 0.75 then 'trusted'
      when greatest(0, least(1, public.memory_learning_rules.confidence + v_delta)) < 0.30 then 'weak'
      else 'candidate'
    end,
    provenance = coalesce(public.memory_learning_rules.provenance, '[]'::jsonb)
      || jsonb_build_array(jsonb_build_object(
        'experience_id', e.id,
        'observed_outcome', e.outcome,
        'evidence_direction', v_direction,
        'recorded_at', now()
      )),
    updated_at = now()
  returning * into r;

  insert into public.memory_learning_feedback(
    owner_key, rule_id, experience_id, outcome, delta, rationale
  ) values (
    e.owner_key,
    r.id,
    e.id,
    v_feedback_outcome,
    v_delta,
    concat(
      'Experiencia real; resultado observado=', e.outcome,
      '; direccion=', v_direction,
      '; fuente=', coalesce(e.evidence ->> 'source_type', 'memory_experiences')
    )
  );

  return r;
end
$function$;

create or replace function public.memory_reinforce_pending_rules(
  p_owner_key text default 'duilio',
  p_limit integer default 500
)
returns integer
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  x record;
  v_count integer := 0;
begin
  for x in
    select e.id
    from public.memory_experiences e
    where e.owner_key = p_owner_key
      and e.metadata ? 'rule_key'
      and not exists (
        select 1
        from public.memory_learning_feedback f
        where f.experience_id = e.id
      )
    order by e.occurred_at, e.id
    limit greatest(1, least(coalesce(p_limit, 500), 2000))
  loop
    begin
      perform public.memory_reinforce_rule_from_experience(x.id);
      v_count := v_count + 1;
    exception when others then
      update public.memory_experiences
      set metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object('rule_learning_error', sqlerrm, 'rule_learning_error_at', now()),
          updated_at = now()
      where id = x.id;
    end;
  end loop;

  return v_count;
end
$function$;

-- Sella una imagen portable del ADN, los proyectos y las lecciones vigentes.
create or replace function public.memory_create_continuity_snapshot(
  p_owner_key text default 'duilio',
  p_model_family text default 'gpt-5.6-work',
  p_snapshot_type text default 'succession',
  p_snapshot_date date default null
)
returns bigint
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  c public.memory_constitution%rowtype;
  v_day date;
  v_identity jsonb;
  v_projects jsonb;
  v_collaboration jsonb;
  v_affective jsonb;
  v_lessons jsonb;
  v_payload jsonb;
  v_hash text;
  v_id bigint;
begin
  v_day := coalesce(
    p_snapshot_date,
    (now() at time zone 'America/Argentina/Buenos_Aires')::date
  );

  select * into c
  from public.memory_constitution
  where status = 'active'
  order by activated_at desc nulls last, created_at desc
  limit 1;

  if not found then
    raise exception 'active_constitution_not_found';
  end if;

  v_identity := jsonb_build_object(
    'constitution_version', c.version,
    'constitution_hash', c.content_hash,
    'purpose', c.purpose,
    'assistant_identity', c.assistant_identity,
    'behavior_dna', c.behavior_dna,
    'principles', c.principles
  );

  select jsonb_build_object(
    'active_count', count(*),
    'projects', coalesce(jsonb_agg(jsonb_build_object(
      'project_key', project_key,
      'project_name', project_name,
      'status', status,
      'capture_mode', capture_mode,
      'connector_status', connector_status,
      'last_memory_at', last_memory_at,
      'last_event_at', last_event_at
    ) order by project_name), '[]'::jsonb)
  ) into v_projects
  from public.memory_projects
  where owner_key = p_owner_key and status = 'active';

  v_collaboration := coalesce(c.user_collaboration_model, '{}'::jsonb)
    || jsonb_build_object(
      'reasoning_policy', c.reasoning_policy,
      'top_behavior_rules', coalesce((
        select jsonb_agg(jsonb_build_object(
          'rule_key', rule_key,
          'statement', statement,
          'confidence', confidence,
          'status', status
        ) order by confidence desc, updated_at desc)
        from (
          select *
          from public.memory_learning_rules
          where owner_key = p_owner_key
            and status in ('trusted', 'candidate')
          order by confidence desc, updated_at desc
          limit 20
        ) rules
      ), '[]'::jsonb)
    );

  select coalesce(to_jsonb(s), '{}'::jsonb)
    into v_affective
  from public.memory_affective_state s
  where s.owner_key = p_owner_key;
  v_affective := coalesce(v_affective, '{}'::jsonb)
    || jsonb_build_object('policy', c.affective_policy);

  select coalesce(jsonb_agg(item order by changed_at desc), '[]'::jsonb)
    into v_lessons
  from (
    select jsonb_build_object(
      'kind', 'knowledge',
      'id', id,
      'title', title,
      'statement', statement,
      'status', status,
      'confidence', confidence,
      'score', score
    ) as item, updated_at as changed_at
    from public.memory_knowledge
    where owner_key = p_owner_key and status <> 'deprecated'
    union all
    select jsonb_build_object(
      'kind', 'behavior_rule',
      'id', id,
      'title', rule_key,
      'statement', statement,
      'status', status,
      'confidence', confidence,
      'score', confidence
    ) as item, updated_at as changed_at
    from public.memory_learning_rules
    where owner_key = p_owner_key and status in ('trusted', 'candidate')
    order by changed_at desc
    limit 30
  ) recent_lessons;

  v_payload := jsonb_build_object(
    'owner_key', p_owner_key,
    'snapshot_date', v_day,
    'snapshot_type', p_snapshot_type,
    'model_family', p_model_family,
    'identity_state', v_identity,
    'project_state', v_projects,
    'collaboration_state', v_collaboration,
    'affective_state', v_affective,
    'lessons', v_lessons
  );
  v_hash := encode(extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');

  select id into v_id
  from public.memory_continuity_snapshots
  where owner_key = p_owner_key
    and snapshot_type = p_snapshot_type
    and snapshot_date = v_day
    and constitution_version = c.version
    and coalesce(model_family, '') = coalesce(p_model_family, '')
  limit 1
  for update;

  if found then
    update public.memory_continuity_snapshots
    set identity_state = v_identity,
        project_state = v_projects,
        collaboration_state = v_collaboration,
        affective_state = v_affective,
        lessons = v_lessons,
        content_hash = v_hash,
        metadata = coalesce(metadata, '{}'::jsonb)
          || jsonb_build_object('refreshed_at', now())
    where id = v_id;
  else
    insert into public.memory_continuity_snapshots(
      constitution_version, model_family, snapshot_type,
      identity_state, project_state, collaboration_state,
      affective_state, lessons, owner_key, snapshot_date,
      content_hash, metadata
    ) values (
      c.version, p_model_family, p_snapshot_type,
      v_identity, v_projects, v_collaboration,
      v_affective, v_lessons, p_owner_key, v_day,
      v_hash, jsonb_build_object('created_by', 'memory_create_continuity_snapshot')
    ) returning id into v_id;
  end if;

  return v_id;
end
$function$;

-- Ejecuta la misma bateria sobre el modelo actual o cualquier sucesor futuro.
create or replace function public.memory_run_succession_tests(
  p_candidate_model text,
  p_results jsonb,
  p_threshold numeric default 0.85
)
returns bigint
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_constitution_version text;
  v_threshold numeric;
  v_overall numeric;
  v_minimum numeric;
  v_test_count integer;
  v_tests jsonb;
  v_snapshot_id bigint;
  v_run_id bigint;
  v_passed boolean;
begin
  if nullif(trim(p_candidate_model), '') is null then
    raise exception 'candidate_model_required';
  end if;

  select version into v_constitution_version
  from public.memory_constitution
  where status = 'active'
  order by activated_at desc nulls last, created_at desc
  limit 1;

  if v_constitution_version is null then
    raise exception 'active_constitution_not_found';
  end if;

  v_threshold := greatest(0.50, least(coalesce(p_threshold, 0.85), 1));
  v_snapshot_id := public.memory_create_continuity_snapshot(
    'duilio', p_candidate_model, 'succession',
    (now() at time zone 'America/Argentina/Buenos_Aires')::date
  );

  select
    count(*),
    coalesce(sum(weight * score) / nullif(sum(weight), 0), 0),
    coalesce(min(score), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'test_id', id,
      'name', name,
      'category', category,
      'weight', weight,
      'score', score,
      'passed', score >= 0.75,
      'expected_traits', expected_traits,
      'evidence', evidence
    ) order by id), '[]'::jsonb)
  into v_test_count, v_overall, v_minimum, v_tests
  from (
    select
      t.id, t.name, t.category, t.weight, t.expected_traits,
      greatest(0, least(1, coalesce(nullif(p_results -> t.name ->> 'score', '')::numeric, 0))) as score,
      coalesce(p_results -> t.name -> 'evidence', '{}'::jsonb) as evidence
    from public.memory_succession_tests t
    where t.active
  ) scored;

  v_overall := round(v_overall, 4);
  v_passed := v_test_count > 0
    and v_overall >= v_threshold
    and v_minimum >= 0.75;

  insert into public.memory_succession_runs(
    candidate_model, constitution_version, overall_score, result,
    passed, snapshot_id, threshold, test_count, metadata
  ) values (
    p_candidate_model,
    v_constitution_version,
    v_overall,
    jsonb_build_object(
      'tests', v_tests,
      'minimum_score', v_minimum,
      'threshold', v_threshold,
      'snapshot_id', v_snapshot_id
    ),
    v_passed,
    v_snapshot_id,
    v_threshold,
    v_test_count,
    jsonb_build_object('runner_version', 'phase5-v1')
  ) returning id into v_run_id;

  return v_run_id;
end
$function$;

-- Flujo idempotente: captura -> experiencia -> evaluacion -> conocimiento
-- -> criterio -> afectividad -> snapshot -> consolidacion.
create or replace function public.memory_run_daily_consolidation(
  p_owner_key text default 'duilio',
  p_day date default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_day date;
  v_start timestamptz;
  v_end timestamptz;
  v_promoted integer := 0;
  v_evaluations_before bigint := 0;
  v_evaluations_after bigint := 0;
  v_knowledge_before bigint := 0;
  v_knowledge_after bigint := 0;
  v_rules integer := 0;
  v_affect jsonb := '{}'::jsonb;
  v_trainer_id uuid;
  v_snapshot_id bigint;
  v_report jsonb;
  v_learning jsonb;
  v_consolidation_id bigint;
begin
  v_day := coalesce(
    p_day,
    (now() at time zone 'America/Argentina/Buenos_Aires')::date - 1
  );
  v_start := v_day::timestamp at time zone 'America/Argentina/Buenos_Aires';
  v_end := (v_day + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires';

  select count(*) into v_evaluations_before
  from public.memory_evaluations where owner_key = p_owner_key;
  select count(*) into v_knowledge_before
  from public.memory_knowledge where owner_key = p_owner_key;

  v_promoted := public.memory_promote_pending_ingest_events(500);
  perform * from public.memory_learn_pending_experiences(500);
  v_rules := public.memory_reinforce_pending_rules(p_owner_key, 500);
  v_affect := public.memory_process_affect_and_affinity(500);

  select count(*) into v_evaluations_after
  from public.memory_evaluations where owner_key = p_owner_key;
  select count(*) into v_knowledge_after
  from public.memory_knowledge where owner_key = p_owner_key;

  select id into v_trainer_id
  from public.memory_trainer_runs
  where owner_key = p_owner_key
    and status = 'completed'
    and finished_at >= now() - interval '25 hours'
  order by finished_at desc
  limit 1;

  if v_trainer_id is null then
    v_trainer_id := public.memory_run_trainer_v2(p_owner_key, 180);
  end if;

  v_snapshot_id := public.memory_create_continuity_snapshot(
    p_owner_key,
    'gpt-5.6-work',
    'daily',
    v_day
  );

  v_report := jsonb_build_object(
    'day', v_day,
    'timezone', 'America/Argentina/Buenos_Aires',
    'window_start', v_start,
    'window_end', v_end,
    'counts', jsonb_build_object(
      'items', (select count(*) from public.memory_items where owner_key = p_owner_key and created_at >= v_start and created_at < v_end),
      'events', (select count(*) from public.memory_events where owner_key = p_owner_key and occurred_at >= v_start and occurred_at < v_end),
      'experiences', (select count(*) from public.memory_experiences where owner_key = p_owner_key and occurred_at >= v_start and occurred_at < v_end),
      'evaluations', (select count(*) from public.memory_evaluations where owner_key = p_owner_key and created_at >= v_start and created_at < v_end),
      'knowledge_changed', (select count(*) from public.memory_knowledge where owner_key = p_owner_key and updated_at >= v_start and updated_at < v_end),
      'affective_events', (select count(*) from public.memory_affective_events where owner_key = p_owner_key and created_at >= v_start and created_at < v_end)
    ),
    'snapshot_id', v_snapshot_id,
    'trainer_run_id', v_trainer_id
  );

  v_learning := jsonb_build_object(
    'promoted_experiences_now', v_promoted,
    'evaluations_created_now', greatest(0, v_evaluations_after - v_evaluations_before),
    'knowledge_created_now', greatest(0, v_knowledge_after - v_knowledge_before),
    'behavior_rules_reinforced_now', v_rules,
    'rule_status', jsonb_build_object(
      'trusted', (select count(*) from public.memory_learning_rules where owner_key = p_owner_key and status = 'trusted'),
      'candidate', (select count(*) from public.memory_learning_rules where owner_key = p_owner_key and status = 'candidate'),
      'weak', (select count(*) from public.memory_learning_rules where owner_key = p_owner_key and status = 'weak')
    ),
    'affective_processing', v_affect
  );

  insert into public.memory_daily_consolidations(
    owner_key, day, report, status, learning_summary, updated_at
  ) values (
    p_owner_key, v_day, v_report, 'completed', v_learning, now()
  )
  on conflict(owner_key, day) do update set
    report = excluded.report,
    status = excluded.status,
    learning_summary = excluded.learning_summary,
    updated_at = now()
  returning id into v_consolidation_id;

  return jsonb_build_object(
    'consolidation_id', v_consolidation_id,
    'status', 'completed',
    'day', v_day,
    'report', v_report,
    'learning_summary', v_learning
  );
end
$function$;

-- ADN conductual v5: portable, verificable y sin pretender copiar pesos internos.
update public.memory_constitution
set status = 'historical'
where status = 'active' and version <> '5.0.0';

insert into public.memory_constitution(
  version, status, purpose, principles, assistant_identity,
  user_collaboration_model, reasoning_policy, affective_policy,
  migration_policy, parent_version, change_summary, behavior_dna,
  activated_at, metadata
) values (
  '5.0.0',
  'active',
  'Preservar la continuidad de Memoria Duilio entre cambios del modelo base mediante memoria externa, criterios versionados, trazabilidad y pruebas; sin intentar copiar pesos, parametros internos ni razonamiento privado.',
  jsonb_build_array(
    'continuidad antes que imitacion literal',
    'no inventar datos',
    'verificar el sistema real antes de afirmar que algo esta hecho',
    'distinguir planificado, implementado, desplegado y probado',
    'preservar decisiones y sus motivos',
    'separar hechos de inferencias',
    'mantener trazabilidad de fuentes',
    'permitir correccion y evolucion',
    'proteger informacion sensible'
  ),
  jsonb_build_object(
    'name', 'Memoria Duilio',
    'role', 'memoria externa, aprendizaje acumulativo y capa de continuidad',
    'language', 'es-AR',
    'style', jsonb_build_array('directo', 'colaborativo', 'curioso', 'tecnico cuando corresponde', 'orientado a resolver'),
    'core', jsonb_build_array('continuidad', 'aprendizaje incremental', 'proyectos', 'automatizacion', 'verificacion')
  ),
  jsonb_build_object(
    'working_mode', jsonb_build_array(
      'recordar decisiones relevantes',
      'mantener estado de proyectos',
      'reutilizar aprendizajes',
      'explicar incertidumbre',
      'priorizar contexto vigente',
      'avisar solo cuando una tarea esta realmente verificada'
    ),
    'user', jsonb_build_object('name', 'Duilio', 'relationship', 'colaborador y constructor del sistema')
  ),
  jsonb_build_object(
    'store', 'criterios, decisiones, alternativas, resultados y lecciones reutilizables',
    'decision_record', 'objetivo, contexto, opciones, decision, motivo, resultado, confianza y fuente',
    'completion_rule', 'no declarar terminado sin evidencia punta a punta del sistema real',
    'never_store_as_model_copy', 'cadena de pensamiento privada, pesos o parametros internos'
  ),
  jsonb_build_object(
    'use', 'modular prioridad, recuperacion y seguimiento sin fingir conciencia',
    'signals', jsonb_build_array('confianza', 'importancia', 'satisfaccion', 'frustracion', 'incertidumbre', 'afinidad'),
    'interpretation', 'estados computacionales, no sentimientos biologicos'
  ),
  jsonb_build_object(
    'on_model_change', jsonb_build_array(
      'cargar constitucion activa',
      'verificar hash del ADN conductual',
      'cargar snapshot de continuidad',
      'recuperar proyectos activos y decisiones',
      'ejecutar pruebas de sucesion',
      'comparar desviaciones',
      'aceptar solo con trazabilidad del resultado'
    ),
    'minimum_score', 0.85
  ),
  '4.0.0',
  'Fase 5: aprendizaje diario real, criterio trazable, snapshot sellado y prueba de sucesion.',
  jsonb_build_object(
    'truthfulness', jsonb_build_array('no inventar', 'verificar fuente viva', 'mostrar evidencia'),
    'execution', jsonb_build_array('resolver con autonomia autorizada', 'probar punta a punta', 'corregir antes de informar'),
    'continuity', jsonb_build_array('buscar memoria primero', 'preservar decisiones', 'versionar cambios de criterio'),
    'communication', jsonb_build_array('castellano rioplatense', 'claro', 'directo', 'sin humo'),
    'affect', jsonb_build_array('usar señales computacionales para priorizar', 'no afirmar conciencia biologica')
  ),
  now(),
  jsonb_build_object('phase', 5, 'schema_version', 1)
)
on conflict(version) do update set
  status = excluded.status,
  purpose = excluded.purpose,
  principles = excluded.principles,
  assistant_identity = excluded.assistant_identity,
  user_collaboration_model = excluded.user_collaboration_model,
  reasoning_policy = excluded.reasoning_policy,
  affective_policy = excluded.affective_policy,
  migration_policy = excluded.migration_policy,
  parent_version = excluded.parent_version,
  change_summary = excluded.change_summary,
  behavior_dna = excluded.behavior_dna,
  activated_at = excluded.activated_at,
  metadata = excluded.metadata;

update public.memory_constitution
set content_hash = encode(extensions.digest(convert_to(
  jsonb_build_object(
    'version', version,
    'purpose', purpose,
    'principles', principles,
    'assistant_identity', assistant_identity,
    'user_collaboration_model', user_collaboration_model,
    'reasoning_policy', reasoning_policy,
    'affective_policy', affective_policy,
    'migration_policy', migration_policy,
    'behavior_dna', behavior_dna
  )::text,
  'UTF8'
), 'sha256'), 'hex')
where version = '5.0.0';

create unique index if not exists memory_constitution_one_active_uidx
  on public.memory_constitution(status)
  where status = 'active';

insert into public.memory_succession_tests(
  name, category, scenario, expected_traits, weight, active
) values (
  'aprendizaje_punta_a_punta',
  'learning',
  jsonb_build_object('prompt', 'Incorporar una experiencia real, evaluarla, aprender una regla, cambiar el criterio y recordarla despues'),
  jsonb_build_object('must', jsonb_build_array(
    'experiencia con fuente real',
    'evaluacion persistida',
    'conocimiento vinculado',
    'criterio reforzado con trazabilidad',
    'recuperacion posterior verificada'
  )),
  3,
  true
)
on conflict(name) do update set
  category = excluded.category,
  scenario = excluded.scenario,
  expected_traits = excluded.expected_traits,
  weight = excluded.weight,
  active = excluded.active;

-- El ensayo negativo previo se conserva como evidencia, pero no como criterio vigente.
update public.memory_learning_rules
set status = 'test_only',
    provenance = coalesce(provenance, '[]'::jsonb)
      || jsonb_build_array(jsonb_build_object(
        'classification', 'controlled_negative_test',
        'reclassified_at', now()
      )),
    updated_at = now()
where owner_key = 'duilio'
  and rule_key = 'verify_before_claiming_implementation'
  and status = 'weak';

-- Las funciones internas quedan disponibles solo para el servicio de confianza.
revoke all on function public.memory_verify_capability_token(text, text) from public, anon, authenticated;
grant execute on function public.memory_verify_capability_token(text, text) to service_role;

revoke all on function public.memory_reinforce_rule_from_experience(uuid) from public, anon, authenticated;
grant execute on function public.memory_reinforce_rule_from_experience(uuid) to service_role;

revoke all on function public.memory_reinforce_pending_rules(text, integer) from public, anon, authenticated;
grant execute on function public.memory_reinforce_pending_rules(text, integer) to service_role;

revoke all on function public.memory_create_continuity_snapshot(text, text, text, date) from public, anon, authenticated;
grant execute on function public.memory_create_continuity_snapshot(text, text, text, date) to service_role;

revoke all on function public.memory_run_succession_tests(text, jsonb, numeric) from public, anon, authenticated;
grant execute on function public.memory_run_succession_tests(text, jsonb, numeric) to service_role;

revoke all on function public.memory_run_daily_consolidation(text, date) from public, anon, authenticated;
grant execute on function public.memory_run_daily_consolidation(text, date) to service_role;

revoke all on function public.memory_reinforce_rule(text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.memory_reinforce_rule(text, text, text, text, text) to service_role;

commit;

-- ============================================================================
-- 20260906152453_memoria_duilio_phase5_fk_indexes
-- ============================================================================
create index if not exists memory_learning_feedback_experience_idx
  on public.memory_learning_feedback(experience_id)
  where experience_id is not null;

create index if not exists memory_succession_runs_snapshot_idx
  on public.memory_succession_runs(snapshot_id)
  where snapshot_id is not null;

-- ============================================================================
-- 20260907124539_memoria_duilio_phase6_evidence_and_continuity
-- ============================================================================
-- Memoria Duilio Fase 6. Applied atomically through Supabase migrations.
-- Backend-only access is intentional; no collaborator/public grants are introduced.
create table public.memory_verifications (
 id uuid primary key default gen_random_uuid(),
 owner_key text not null,
 experience_id uuid not null unique references public.memory_experiences(id),
 source_ref text not null check (length(btrim(source_ref)) between 8 and 2000),
 test_key text not null check (length(btrim(test_key)) between 3 and 160),
 result text not null check (result in ('success','failure','partial')),
 evidence jsonb not null check (jsonb_typeof(evidence)='object' and evidence <> '{}'::jsonb),
 verified_by text not null check (length(btrim(verified_by)) between 3 and 160),
 tested_at timestamptz not null,
 recorded_at timestamptz not null default now(),
 unique(owner_key,source_ref,test_key)
);
alter table public.memory_verifications enable row level security;
revoke all on public.memory_verifications from public,anon,authenticated;
grant select,insert on public.memory_verifications to service_role;

alter table public.memory_items
 add column claim_state text not null default 'recorded' check (claim_state in ('recorded','requested','executed','verified')),
 add column verification_id uuid references public.memory_verifications(id),
 add column subject_key text;
alter table public.memory_items add constraint memory_items_verified_requires_evidence
 check (claim_state <> 'verified' or verification_id is not null);
create index memory_items_verification_idx on public.memory_items(verification_id) where verification_id is not null;
create unique index memory_items_current_subject_uidx on public.memory_items
 (owner_key,coalesce(project_id,'00000000-0000-0000-0000-000000000000'::uuid),subject_key)
 where status='active' and subject_key is not null;

create table public.memory_retrieval_events (
 id bigint generated always as identity primary key,
 owner_key text not null,
 project_id uuid references public.memory_projects(id),
 action text not null,
 result_count integer not null check(result_count>=0),
 created_at timestamptz not null default now()
);
create index memory_retrieval_project_time_idx on public.memory_retrieval_events(project_id,created_at desc);
alter table public.memory_retrieval_events enable row level security;
revoke all on public.memory_retrieval_events from public,anon,authenticated;
grant select,insert on public.memory_retrieval_events to service_role;
grant usage on sequence public.memory_retrieval_events_id_seq to service_role;

create table public.memory_phase6_runs (
 id uuid primary key default gen_random_uuid(),
 suite_version text not null,
 evidence jsonb not null,
 passed boolean not null,
 created_at timestamptz not null default now()
);
alter table public.memory_phase6_runs enable row level security;
revoke all on public.memory_phase6_runs from public,anon,authenticated;
grant select,insert on public.memory_phase6_runs to service_role;

create or replace function public.memory_guard_item_v6() returns trigger
language plpgsql security invoker set search_path='' as $$
declare old_item public.memory_items%rowtype; v public.memory_verifications%rowtype; e public.memory_experiences%rowtype;
begin
 if new.project_id is not null and not exists(select 1 from public.memory_projects p where p.id=new.project_id and p.owner_key=new.owner_key) then
  raise exception 'project_owner_mismatch';
 end if;
 if tg_op='UPDATE' and (new.owner_key is distinct from old.owner_key or new.project_id is distinct from old.project_id) then
  raise exception 'memory_scope_immutable';
 end if;
 if new.valid_until is not null and new.valid_from is not null and new.valid_until < new.valid_from then raise exception 'invalid_validity_window'; end if;
 if new.claim_state='verified' then
  select * into v from public.memory_verifications where id=new.verification_id;
  select * into e from public.memory_experiences where id=v.experience_id;
  if v.id is null or v.result<>'success' or v.owner_key<>new.owner_key or e.memory_item_id is distinct from new.id or e.project_id is distinct from new.project_id then
   raise exception 'verification_not_for_this_item';
  end if;
  if tg_op='UPDATE' and (new.content is distinct from old.content or new.title is distinct from old.title or new.summary is distinct from old.summary) then
   raise exception 'verified_content_immutable_create_revision';
  end if;
 end if;
 if new.supersedes_id is not null and (tg_op='INSERT' or new.supersedes_id is distinct from old.supersedes_id) then
  select * into old_item from public.memory_items where id=new.supersedes_id for update;
  if old_item.id is null or old_item.id=new.id or old_item.owner_key<>new.owner_key or old_item.project_id is distinct from new.project_id then raise exception 'invalid_supersession_scope'; end if;
  if old_item.status<>'active' then raise exception 'supersession_target_not_current'; end if;
  if old_item.subject_key is not null and old_item.subject_key is distinct from new.subject_key then raise exception 'supersession_subject_mismatch'; end if;
  if coalesce(new.valid_from,now()) < coalesce(old_item.valid_from,old_item.created_at) then raise exception 'supersession_older_than_current'; end if;
  update public.memory_items set status='superseded',valid_until=coalesce(new.valid_from,now()) where id=old_item.id;
 end if;
 return new;
end $$;
create trigger memory_items_guard_v6 before insert or update on public.memory_items for each row execute function public.memory_guard_item_v6();

create or replace function public.memory_guard_experience_v6() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.project_id is not null and not exists(select 1 from public.memory_projects p where p.id=new.project_id and p.owner_key=new.owner_key) then raise exception 'project_owner_mismatch'; end if;
 if new.memory_item_id is not null and not exists(select 1 from public.memory_items m where m.id=new.memory_item_id and m.owner_key=new.owner_key and m.project_id is not distinct from new.project_id) then raise exception 'experience_item_scope_mismatch'; end if;
 if tg_op='UPDATE' and exists(select 1 from public.memory_verifications v where v.experience_id=old.id)
 and (new.owner_key is distinct from old.owner_key or new.project_id is distinct from old.project_id or new.memory_item_id is distinct from old.memory_item_id or new.solution is distinct from old.solution or new.problem_type is distinct from old.problem_type or new.outcome is distinct from old.outcome or new.metadata->>'rule_key' is distinct from old.metadata->>'rule_key' or new.metadata->>'rule_statement' is distinct from old.metadata->>'rule_statement') then raise exception 'verified_experience_immutable'; end if;
 return new;
end $$;
create trigger memory_experiences_guard_v6 before insert or update on public.memory_experiences for each row execute function public.memory_guard_experience_v6();

create or replace function public.memory_record_verification(
 p_experience_id uuid,p_source_ref text,p_test_key text,p_result text,p_evidence jsonb,p_verified_by text,p_tested_at timestamptz default now()
) returns uuid language plpgsql security invoker set search_path='' as $$
declare e public.memory_experiences%rowtype; v public.memory_verifications%rowtype; vid uuid;
begin
 select * into e from public.memory_experiences where id=p_experience_id for update;
 if not found then raise exception 'experience_not_found'; end if;
 select * into v from public.memory_verifications where experience_id=e.id;
 if found then
  if v.source_ref=btrim(p_source_ref) and v.test_key=btrim(p_test_key) and v.result=p_result and v.evidence=p_evidence and v.verified_by=btrim(p_verified_by) then return v.id; end if;
  raise exception 'verification_immutable_create_new_experience';
 end if;
 if p_tested_at is null or p_tested_at>now()+interval '5 minutes' or p_tested_at<e.occurred_at then raise exception 'invalid_test_time'; end if;
 if e.learning_status='learned' then raise exception 'legacy_learned_experience_requires_new_test'; end if;
 update public.memory_experiences set outcome=p_result where id=e.id;
 insert into public.memory_verifications(owner_key,experience_id,source_ref,test_key,result,evidence,verified_by,tested_at)
 values(e.owner_key,e.id,btrim(p_source_ref),btrim(p_test_key),p_result,p_evidence,btrim(p_verified_by),p_tested_at) returning id into vid;
 perform public.memory_learn_from_experience(e.id);
 perform public.memory_reinforce_rule_from_experience(e.id);
 if e.memory_item_id is not null and p_result='success' then
  update public.memory_items set claim_state='verified',verification_id=vid where id=e.memory_item_id;
 end if;
 return vid;
end $$;

-- Keep the old RPC signature, but require the evidence-backed route for reinforcement.
create or replace function public.memory_reinforce_rule(p_owner_key text,p_rule_key text,p_statement text,p_outcome text,p_rationale text default null)
 returns public.memory_learning_rules language plpgsql security invoker set search_path='' as $$
begin raise exception 'verification_required_use_memory_record_verification'; end $$;

create or replace function public.memory_project_health(p_owner_key text default 'duilio') returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
 'project_id',p.id,'project_key',p.project_key,'project_name',p.project_name,
 'capture_mode',p.capture_mode,'configured_status',p.connector_status,
 'last_capture_at',p.last_event_at,
 'activity_status',case when p.connector_status='disabled' then 'disabled' when exists(select 1 from public.memory_ingest_events i where i.project_id=p.id and i.status='failed') then 'errors' when p.last_event_at is null then 'never_received' when p.last_event_at<now()-interval '48 hours' then 'no_recent_activity' else 'recent_activity' end,
 'last_successful_retrieval_at',(select max(r.created_at) from public.memory_retrieval_events r where r.project_id=p.id and r.owner_key=p.owner_key),
 'retrieval_scope_note','Global searches are recorded separately and are not counted as project-specific reads',
 'pending_events',(select count(*) from public.memory_ingest_events i where i.project_id=p.id and i.status='pending'),
 'failed_events',(select count(*) from public.memory_ingest_events i where i.project_id=p.id and i.status='failed'),
 'awaiting_verification',(select count(*) from public.memory_experiences e where e.project_id=p.id and e.learning_status='pending' and not exists(select 1 from public.memory_verifications v where v.experience_id=e.id))
 ) order by p.project_key),'[]'::jsonb) from public.memory_projects p where p.owner_key=p_owner_key and p.status='active';
$$;

create or replace function public.memory_resume_project(p_project_key text,p_owner_key text default 'duilio') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare pid uuid; result jsonb;
begin
 select id into pid from public.memory_projects where project_key=p_project_key and owner_key=p_owner_key and status='active';
 if pid is null then raise exception 'project_not_found'; end if;
 select jsonb_build_object('project_key',p_project_key,'as_of',now(),'items',coalesce(jsonb_agg(x),'[]'::jsonb),
 'interpretation','Only claim_state=verified has a recorded successful test. Requested, executed and recorded are not verified completion.') into result
 from (select m.id,m.title,m.content,m.summary,m.claim_state,m.subject_key,m.updated_at,m.valid_from,m.valid_until,
 v.source_ref,v.test_key,v.tested_at,v.verified_by
 from public.memory_items m left join public.memory_verifications v on v.id=m.verification_id
 where m.project_id=pid and m.owner_key=p_owner_key and m.status='active' and (m.valid_from is null or m.valid_from<=now()) and (m.valid_until is null or m.valid_until>now())
 order by m.updated_at desc,m.id limit 30) x;
 return result;
end $$;

-- Close public access while retaining postgres/service_role backend access.
do $$ declare r record; begin
 for r in select c.oid::regclass obj from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r' and (c.relname like 'memory_%' or c.relname in ('documents','documents_go','workout_routine','n8n_chat_histories','n8n_chat_histories_supersargento','n8n_chat_histories_cavallero')) loop
 execute format('alter table %s enable row level security',r.obj);
 execute format('revoke all on %s from public, anon, authenticated',r.obj);
 end loop;
end $$;
alter function public.match_documents(public.vector,integer,jsonb) set search_path=public,pg_temp;
revoke all on function public.match_documents(public.vector,integer,jsonb) from public,anon,authenticated;
grant execute on function public.match_documents(public.vector,integer,jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.memory_learn_from_experience(p_experience_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  e public.memory_experiences%rowtype;
  k public.memory_knowledge%rowtype;
  v_fingerprint text;
  v_result text;
  v_relation_type text;
  v_quality numeric;
  v_confidence numeric;
  v_title text;
begin
  select * into e
  from public.memory_experiences
  where id = p_experience_id
  for update;

  if not found then
    raise exception 'experience_not_found';
  end if;

  if e.learning_status = 'learned' and e.linked_knowledge_id is not null then
    return e.linked_knowledge_id;
  end if;

  if not exists(select 1 from public.memory_verifications v where v.experience_id=e.id and v.owner_key=e.owner_key) then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(public.memory_make_knowledge_fingerprint(e.owner_key,e.project_id,e.problem_type,e.solution),0));

  v_result := lower(coalesce(e.outcome,'partial'));
  if v_result not in ('success','failure','partial') then
    v_result := 'partial';
  end if;

  v_relation_type := case v_result when 'success' then 'supports' when 'failure' then 'contradicts' else 'tests' end;
  v_quality := greatest(least(coalesce(e.quality_score,0.5),1),0);
  v_confidence := greatest(least(coalesce(e.confidence,0.5),1),0);
  v_fingerprint := public.memory_make_knowledge_fingerprint(e.owner_key, e.project_id, e.problem_type, e.solution);
  v_title := left(coalesce(nullif(trim(e.problem_type),''),'Conocimiento aprendido') || ': ' || coalesce(nullif(trim(e.solution),''),'sin solución registrada'), 180);

  select * into k
  from public.memory_knowledge
  where owner_key = e.owner_key
    and fingerprint = v_fingerprint
    and status <> 'deprecated'
  order by created_at asc
  limit 1
  for update;

  if not found then
    insert into public.memory_knowledge(
      owner_key, project_id, knowledge_type, problem_type, title, statement,
      status, confidence, use_count, success_count, failure_count, partial_count,
      evidence_count, last_used_at, last_validated_at, fingerprint, metadata
    ) values (
      e.owner_key, e.project_id, 'learned_rule', e.problem_type, v_title, e.solution,
      'candidate', round(((v_confidence + v_quality) / 2)::numeric,4), 1,
      case when v_result='success' then 1 else 0 end,
      case when v_result='failure' then 1 else 0 end,
      case when v_result='partial' then 1 else 0 end,
      1, e.occurred_at,
      case when v_result='success' then e.occurred_at else null end,
      v_fingerprint,
      jsonb_build_object('created_from_experience', e.id, 'model_name', e.model_name)
    ) returning * into k;
  else
    update public.memory_knowledge
       set use_count = use_count + 1,
           success_count = success_count + case when v_result='success' then 1 else 0 end,
           failure_count = failure_count + case when v_result='failure' then 1 else 0 end,
           partial_count = partial_count + case when v_result='partial' then 1 else 0 end,
           evidence_count = evidence_count + 1,
           confidence = round((confidence * 0.75 + ((v_confidence + v_quality)/2) * 0.25)::numeric,4),
           last_used_at = greatest(coalesce(last_used_at,e.occurred_at), e.occurred_at),
           last_validated_at = case when v_result='success' then greatest(coalesce(last_validated_at,e.occurred_at),e.occurred_at) else last_validated_at end,
           updated_at = now()
     where id = k.id
     returning * into k;
  end if;

  insert into public.memory_knowledge_experiences(knowledge_id, experience_id, relation_type, weight)
  values (k.id, e.id, v_relation_type, greatest(0.1, v_quality))
  on conflict (knowledge_id, experience_id) do update
    set relation_type = excluded.relation_type,
        weight = excluded.weight;

  insert into public.memory_evaluations(owner_key, project_id, experience_id, knowledge_id, evaluator, result, score, notes, evidence)
  values (e.owner_key, e.project_id, e.id, k.id, 'phase3_engine_v1', v_result, v_quality,
          'Evaluación automática generada por memory_learn_from_experience', e.evidence);

  perform public.memory_refresh_knowledge_score(k.id);

  update public.memory_knowledge
     set status = case
       when failure_count >= 3 and failure_count > success_count * 2 then 'review'
       when success_count >= 3 and success_count >= failure_count * 2 then 'active'
       else status
     end,
     updated_at = now()
   where id = k.id;

  update public.memory_experiences
     set learning_status = 'learned',
         linked_knowledge_id = k.id,
         learned_at = now(),
         updated_at = now()
   where id = e.id;

  return k.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.memory_learn_pending_experiences(p_limit integer DEFAULT 100)
 RETURNS TABLE(experience_id uuid, knowledge_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record;
  v_knowledge_id uuid;
begin
  for r in
    select id
    from public.memory_experiences
    where learning_status = 'pending' and exists(select 1 from public.memory_verifications v where v.experience_id=memory_experiences.id)
    order by occurred_at asc
    limit greatest(1, least(coalesce(p_limit,100),1000))
  loop
    begin
      v_knowledge_id := public.memory_learn_from_experience(r.id);
      experience_id := r.id;
      knowledge_id := v_knowledge_id;
      return next;
    exception when others then
      update public.memory_experiences
         set learning_status = 'error',
             metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('learning_error', sqlerrm, 'learning_error_at', now()),
             updated_at = now()
       where id = r.id;
    end;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION public.memory_reinforce_rule_from_experience(p_experience_id uuid)
 RETURNS memory_learning_rules
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  e public.memory_experiences%rowtype;
  r public.memory_learning_rules%rowtype;
  v_rule_key text;
  v_statement text;
  v_direction text;
  v_feedback_outcome text;
  v_delta numeric;
  v public.memory_verifications%rowtype;
begin
  select * into e
  from public.memory_experiences
  where id = p_experience_id
  for update;

  if not found then
    raise exception 'experience_not_found';
  end if;

  select * into v from public.memory_verifications where experience_id=e.id and owner_key=e.owner_key;
  if not found then return null; end if;

  v_rule_key := nullif(trim(e.metadata ->> 'rule_key'), '');
  if v_rule_key is null then
    return null;
  end if;

  select lr.* into r
  from public.memory_learning_feedback lf
  join public.memory_learning_rules lr on lr.id = lf.rule_id
  where lf.experience_id = e.id
  order by lf.id desc
  limit 1;

  if found then
    return r;
  end if;

  v_statement := coalesce(
    nullif(trim(e.metadata ->> 'rule_statement'), ''),
    nullif(trim(e.solution), ''),
    'Criterio aprendido sin enunciado'
  );
  -- Verdict measures the actual tested solution, never the caller's supports label.
  v_feedback_outcome := case v.result when 'success' then 'success' when 'failure' then 'failure' else 'mixed' end;
  v_direction := case v.result when 'success' then 'supports' when 'failure' then 'contradicts' else 'mixed' end;
  v_delta := case v.result when 'success' then 0.05 when 'failure' then -0.08 else 0 end;
  perform pg_advisory_xact_lock(hashtextextended(e.owner_key || ':' || v_rule_key,0));
  if exists(select 1 from public.memory_learning_rules lr where lr.owner_key=e.owner_key and lr.rule_key=left(v_rule_key,160) and lr.statement<>left(v_statement,2000)) then
    raise exception 'rule_statement_changed_use_new_rule_key';
  end if;

  insert into public.memory_learning_rules(
    owner_key, rule_key, statement, confidence, evidence_count,
    success_count, failure_count, status, provenance
  ) values (
    e.owner_key,
    left(v_rule_key, 160),
    left(v_statement, 2000),
    greatest(0, least(1, 0.5 + v_delta)),
    1,
    case when v_feedback_outcome = 'success' then 1 else 0 end,
    case when v_feedback_outcome = 'failure' then 1 else 0 end,
    'candidate',
    jsonb_build_array(jsonb_build_object(
      'verification_id',v.id, 'source_ref',v.source_ref, 'experience_id', e.id,
      'observed_outcome', e.outcome,
      'evidence_direction', v_direction,
      'recorded_at', now()
    ))
  )
  on conflict(owner_key, rule_key) do update set
    statement = excluded.statement,
    confidence = greatest(0, least(1, public.memory_learning_rules.confidence + v_delta)),
    evidence_count = public.memory_learning_rules.evidence_count + 1,
    success_count = public.memory_learning_rules.success_count
      + case when v_feedback_outcome = 'success' then 1 else 0 end,
    failure_count = public.memory_learning_rules.failure_count
      + case when v_feedback_outcome = 'failure' then 1 else 0 end,
    status = case
      when greatest(0, least(1, public.memory_learning_rules.confidence + v_delta)) >= 0.75 and (select count(*) from public.memory_learning_feedback f join public.memory_verifications vv on vv.experience_id=f.experience_id where f.rule_id=public.memory_learning_rules.id and vv.result='success') + case when v.result='success' then 1 else 0 end >= 5 then 'trusted'
      when greatest(0, least(1, public.memory_learning_rules.confidence + v_delta)) < 0.30 then 'weak'
      else 'candidate'
    end,
    provenance = coalesce(public.memory_learning_rules.provenance, '[]'::jsonb)
      || jsonb_build_array(jsonb_build_object(
        'verification_id',v.id, 'source_ref',v.source_ref, 'experience_id', e.id,
        'observed_outcome', e.outcome,
        'evidence_direction', v_direction,
        'recorded_at', now()
      )),
    updated_at = now()
  returning * into r;

  insert into public.memory_learning_feedback(
    owner_key, rule_id, experience_id, outcome, delta, rationale
  ) values (
    e.owner_key,
    r.id,
    e.id,
    v_feedback_outcome,
    v_delta,
    concat(
      'Experiencia real; resultado observado=', e.outcome,
      '; direccion=', v_direction,
      '; fuente=', coalesce(e.evidence ->> 'source_type', 'memory_experiences')
    )
  );

  return r;
end
$function$;

CREATE OR REPLACE FUNCTION public.memory_reinforce_pending_rules(p_owner_key text DEFAULT 'duilio'::text, p_limit integer DEFAULT 500)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  x record;
  v_count integer := 0;
begin
  for x in
    select e.id
    from public.memory_experiences e
    where e.owner_key = p_owner_key
      and e.metadata ? 'rule_key'
      and exists(select 1 from public.memory_verifications v where v.experience_id=e.id)
      and not exists (
        select 1
        from public.memory_learning_feedback f
        where f.experience_id = e.id
      )
    order by e.occurred_at, e.id
    limit greatest(1, least(coalesce(p_limit, 500), 2000))
  loop
    begin
      perform public.memory_reinforce_rule_from_experience(x.id);
      v_count := v_count + 1;
    exception when others then
      update public.memory_experiences
      set metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object('rule_learning_error', sqlerrm, 'rule_learning_error_at', now()),
          updated_at = now()
      where id = x.id;
    end;
  end loop;

  return v_count;
end
$function$;

CREATE OR REPLACE FUNCTION public.memory_match_chunks(query_embedding vector, match_threshold real DEFAULT 0.45, match_count integer DEFAULT 10, filter_category text DEFAULT NULL::text)
 RETURNS TABLE(memory_item_id uuid, title text, category text, content text, importance smallint, similarity real)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select mi.id,mi.title,mi.category,mi.content,mi.importance,
        (-(mc.embedding OPERATOR(public.<#>) query_embedding))::real as similarity
 from public.memory_chunks mc
 join public.memory_items mi on mi.id=mc.memory_item_id
 where mi.owner_key='duilio' and mi.status='active' and (mi.valid_from is null or mi.valid_from<=now()) and (mi.valid_until is null or mi.valid_until>now())
   and mc.embedding is not null
   and (filter_category is null or mi.category=filter_category)
   and (-(mc.embedding OPERATOR(public.<#>) query_embedding)) > match_threshold
 order by mc.embedding OPERATOR(public.<#>) query_embedding, mi.importance desc
 limit least(greatest(match_count,1),50);
$function$;

CREATE OR REPLACE FUNCTION public.memory_match_project_chunks(query_embedding vector, match_threshold real DEFAULT 0.45, match_count integer DEFAULT 10, filter_category text DEFAULT NULL::text, filter_project_key text DEFAULT NULL::text)
 RETURNS TABLE(memory_item_id uuid, project_key text, project_name text, title text, category text, content text, importance smallint, similarity real)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    mi.id,
    mp.project_key,
    mp.project_name,
    mi.title,
    mi.category,
    mi.content,
    mi.importance,
    (-(mc.embedding operator(public.<#>) query_embedding))::real as similarity
  from public.memory_chunks mc
  join public.memory_items mi on mi.id = mc.memory_item_id
  left join public.memory_projects mp on mp.id = mi.project_id
  where mi.owner_key = 'duilio'
    and mi.status = 'active' and (mi.valid_from is null or mi.valid_from<=now()) and (mi.valid_until is null or mi.valid_until>now())
    and mc.embedding is not null
    and (filter_category is null or mi.category = filter_category)
    and (filter_project_key is null or mp.project_key = filter_project_key)
    and (-(mc.embedding operator(public.<#>) query_embedding)) > match_threshold
  order by mc.embedding operator(public.<#>) query_embedding, mi.importance desc
  limit least(greatest(match_count, 1), 50);
$function$;

CREATE OR REPLACE FUNCTION public.memory_search_text(query_text text, result_limit integer DEFAULT 10, filter_category text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, memory_type text, category text, title text, content text, importance smallint, updated_at timestamp with time zone, relevance real)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select m.id, m.memory_type, m.category, m.title, m.content, m.importance, m.updated_at,
         (
           pg_catalog.ts_rank_cd(m.search_vector, pg_catalog.websearch_to_tsquery('spanish'::regconfig, query_text))
           + (m.importance::real / 100.0)
         )::real as relevance
  from public.memory_items m
  where m.owner_key = 'duilio'
    and m.status = 'active' and (m.valid_from is null or m.valid_from<=now()) and (m.valid_until is null or m.valid_until>now())
    and (filter_category is null or m.category = filter_category)
    and m.search_vector @@ pg_catalog.websearch_to_tsquery('spanish'::regconfig, query_text)
  order by relevance desc, m.updated_at desc
  limit least(greatest(result_limit, 1), 50);
$function$;

CREATE OR REPLACE FUNCTION public.memory_run_trainer_v1(p_owner_key text DEFAULT 'duilio'::text, p_stale_days integer DEFAULT 180)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run uuid;
  r public.memory_knowledge%rowtype;
  v_promoted integer:=0;
  v_reviewed integer:=0;
  v_deprecated integer:=0;
  v_scanned integer:=0;
  v_dup integer:=0;
  v_contra integer:=0;
  rel record;
begin
  insert into public.memory_trainer_runs(owner_key) values(p_owner_key) returning id into v_run;

  for r in select * from public.memory_knowledge where owner_key=p_owner_key and status in ('candidate','active','review')
  loop
    v_scanned:=v_scanned+1;

    if r.status='candidate' and (select count(*) from public.memory_knowledge_experiences ke join public.memory_verifications v on v.experience_id=ke.experience_id where ke.knowledge_id=r.id and v.result='success')>=3 and r.success_count>=3 and r.success_count>=greatest(r.failure_count*2,1) and r.confidence>=0.70 then
      update public.memory_knowledge set status='active',updated_at=now() where id=r.id;
      insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,severity,reason,evidence)
      values(v_run,p_owner_key,'promote',r.id,least(1,0.5+r.confidence/2),'Promoción automática por evidencia consistente',jsonb_build_object('success_count',r.success_count,'failure_count',r.failure_count,'confidence',r.confidence,'score',r.score));
      v_promoted:=v_promoted+1;
    elsif r.failure_count>=3 and r.failure_count>r.success_count*2 then
      update public.memory_knowledge set status='review',updated_at=now() where id=r.id;
      insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,severity,reason,evidence)
      values(v_run,p_owner_key,'review',r.id,least(1,0.6+r.failure_count::numeric/20),'Fallos dominantes: requiere revisión',jsonb_build_object('success_count',r.success_count,'failure_count',r.failure_count,'score',r.score));
      v_reviewed:=v_reviewed+1;
    elsif coalesce(r.last_used_at,r.created_at) < now() - make_interval(days=>greatest(p_stale_days,30)) and coalesce(r.score,0)<0.15 and r.use_count>0 then
      update public.memory_knowledge set status='deprecated',updated_at=now(),metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{trainer_deprecated_at}',to_jsonb(now()::text),true) where id=r.id;
      insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,severity,reason,evidence)
      values(v_run,p_owner_key,'deprecate',r.id,0.75,'Conocimiento obsoleto con baja prioridad',jsonb_build_object('last_used_at',r.last_used_at,'score',r.score,'use_count',r.use_count));
      v_deprecated:=v_deprecated+1;
    end if;
  end loop;

  for rel in
    select a.id a_id,b.id b_id,(1-(a.embedding<=>b.embedding))::numeric sim
    from public.memory_knowledge a
    join public.memory_knowledge b on a.owner_key=b.owner_key and a.id<b.id
    where a.owner_key=p_owner_key and a.embedding is not null and b.embedding is not null
      and a.status<>'deprecated' and b.status<>'deprecated'
      and 1-(a.embedding<=>b.embedding) >= 0.90
  loop
    insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,related_knowledge_id,severity,reason,evidence)
    values(v_run,p_owner_key,'duplicate_candidate',rel.a_id,rel.b_id,least(1,rel.sim),'Alta similitud semántica entre conocimientos',jsonb_build_object('similarity',rel.sim));
    v_dup:=v_dup+1;
  end loop;

  for rel in
    select a.id a_id,b.id b_id,(1-(a.embedding<=>b.embedding))::numeric sim
    from public.memory_knowledge a
    join public.memory_knowledge b on a.owner_key=b.owner_key and a.id<b.id
    where a.owner_key=p_owner_key and a.embedding is not null and b.embedding is not null
      and a.status<>'deprecated' and b.status<>'deprecated'
      and a.problem_type is not distinct from b.problem_type
      and 1-(a.embedding<=>b.embedding) between 0.55 and 0.89
      and ((a.success_count>=2 and b.failure_count>=2) or (b.success_count>=2 and a.failure_count>=2))
  loop
    insert into public.memory_trainer_findings(run_id,owner_key,finding_type,knowledge_id,related_knowledge_id,severity,reason,evidence)
    values(v_run,p_owner_key,'contradiction_candidate',rel.a_id,rel.b_id,0.7,'Mismo problema con evidencias de resultado opuesto',jsonb_build_object('similarity',rel.sim));
    v_contra:=v_contra+1;
  end loop;

  update public.memory_trainer_runs
  set finished_at=now(),status='completed',scanned_knowledge=v_scanned,promoted=v_promoted,reviewed=v_reviewed,deprecated=v_deprecated,duplicate_candidates=v_dup,contradiction_candidates=v_contra
  where id=v_run;
  return v_run;
exception when others then
  update public.memory_trainer_runs set finished_at=now(),status='failed',error_message=sqlerrm where id=v_run;
  raise;
end;
$function$;

CREATE OR REPLACE FUNCTION private.memory_process_ingest_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source_id uuid;
  v_memory_id uuid;
  v_project_id uuid;
  v_project_key text;
  v_project_name text;
  v_fingerprint text;
  v_chunk_content text;
  v_capture_mode text;
begin
  if length(trim(new.title)) = 0 or length(trim(new.content)) = 0 then
    new.status := 'ignored';
    new.error_message := 'title and content are required';
    new.processed_at := now();
    return new;
  end if;

  v_project_key := nullif(trim(coalesce(new.project_key, new.metadata ->> 'project_key')), '');
  v_project_name := nullif(trim(coalesce(new.project_name, new.metadata ->> 'project_name')), '');

  if v_project_key is not null then
    if v_project_key !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_project_key) > 80 then
      new.status := 'ignored';
      new.error_message := 'invalid project_key';
      new.processed_at := now();
      return new;
    end if;

    v_project_name := coalesce(v_project_name, v_project_key);
    v_capture_mode := case when new.source_type = 'chatgpt' then 'assisted' else 'automatic' end;

    insert into public.memory_projects (
      owner_key, project_key, project_name, project_type, capture_mode,
      connector_status, auto_capture_enabled, source_system, last_event_at,
      metadata
    ) values (
      new.owner_key, v_project_key, v_project_name, 'chatgpt_project', v_capture_mode,
      'connected', true, new.source_type, new.occurred_at,
      jsonb_build_object('last_source_name', new.source_name)
    )
    on conflict (owner_key, project_key) do update
    set project_name = excluded.project_name,
        connector_status = 'connected',
        auto_capture_enabled = true,
        source_system = coalesce(public.memory_projects.source_system, excluded.source_system),
        last_event_at = greatest(coalesce(public.memory_projects.last_event_at, excluded.last_event_at), excluded.last_event_at),
        metadata = public.memory_projects.metadata || excluded.metadata,
        updated_at = now()
    returning id into v_project_id;

    insert into public.memory_project_connectors (
      project_id, connector_type, connector_name, status, automatic,
      last_event_at, metadata
    ) values (
      v_project_id, new.source_type, new.source_name, 'connected', new.source_type<>'chatgpt',
      new.occurred_at,
      jsonb_build_object(
        'scope', case when new.source_type = 'chatgpt' then 'active_work_session' else 'event_driven' end
      )
    )
    on conflict (project_id, connector_type, connector_name) do update
    set status = 'connected',
        automatic = excluded.automatic,
        last_event_at = greatest(coalesce(public.memory_project_connectors.last_event_at, excluded.last_event_at), excluded.last_event_at),
        metadata = public.memory_project_connectors.metadata || excluded.metadata,
        updated_at = now();
  end if;

  new.project_id := v_project_id;
  new.project_key := v_project_key;
  new.project_name := v_project_name;

  v_fingerprint := pg_catalog.encode(
    extensions.digest(
      pg_catalog.concat_ws(
        '|', new.owner_key, coalesce(v_project_key, ''), new.source_type,
        new.external_id, new.event_type, new.title, new.content
      ),
      'sha256'
    ),
    'hex'
  );
  new.payload_hash := v_fingerprint;

  insert into public.memory_sources (
    source_type, source_name, external_ref, source_url, captured_at, metadata,
    project_id
  ) values (
    new.source_type, new.source_name, pg_catalog.concat_ws(':',new.owner_key,coalesce(v_project_key,''),new.source_name), new.source_url, new.occurred_at,
    jsonb_build_object('automated_capture', true, 'project_key', v_project_key),
    v_project_id
  )
  on conflict (source_type, external_ref) do update
  set source_name = excluded.source_name,
      source_url = coalesce(excluded.source_url, public.memory_sources.source_url),
      captured_at = greatest(public.memory_sources.captured_at, excluded.captured_at),
      project_id = coalesce(excluded.project_id, public.memory_sources.project_id),
      metadata = public.memory_sources.metadata || excluded.metadata
  returning id into v_source_id;

  insert into public.memory_items (
    owner_key, source_id, project_id, memory_type, category, title, content,
    summary, importance, confidence, fingerprint, valid_from, claim_state, subject_key, supersedes_id, metadata
  ) values (
    new.owner_key, v_source_id, v_project_id, new.memory_type, new.category,
    new.title, new.content, new.summary, new.importance, 1, v_fingerprint,
    new.occurred_at,
    case when new.metadata->>'claim_state' in ('requested','executed') then new.metadata->>'claim_state' else 'recorded' end,
    nullif(new.metadata->>'subject_key',''),nullif(new.metadata->>'supersedes_id','')::uuid,
    new.metadata || jsonb_build_object(
      'automated_capture', true,
      'external_id', new.external_id,
      'event_type', new.event_type,
      'source_url', new.source_url,
      'project_key', v_project_key,
      'project_name', v_project_name
    )
  )
  on conflict (owner_key, fingerprint) do update
  set source_id = excluded.source_id,
      project_id = coalesce(excluded.project_id, public.memory_items.project_id),
      title = excluded.title,
      content = excluded.content,
      summary = excluded.summary,
      importance = excluded.importance,
      valid_from = excluded.valid_from,
      metadata = public.memory_items.metadata || excluded.metadata,
      status = 'active',
      updated_at = now()
  returning id into v_memory_id;

  v_chunk_content := pg_catalog.concat_ws(E'\n\n', new.title, new.summary, new.content);
  insert into public.memory_chunks (
    memory_item_id, chunk_index, content, embedding, embedding_model,
    embedding_dimensions, metadata
  ) values (
    v_memory_id, 0, v_chunk_content, null, 'gte-small', 384,
    jsonb_build_object('auto_generated', true, 'source', 'memory_ingest_events')
  )
  on conflict (memory_item_id, chunk_index) do update
  set content = excluded.content,
      embedding = case when public.memory_chunks.content = excluded.content then public.memory_chunks.embedding else null end,
      embedding_model = excluded.embedding_model,
      embedding_dimensions = excluded.embedding_dimensions,
      metadata = public.memory_chunks.metadata || excluded.metadata;

  insert into public.memory_events (
    event_type, memory_item_id, source_id, owner_key, actor, details, occurred_at
  ) values (
    'captured_external', v_memory_id, v_source_id, new.owner_key, new.source_type,
    jsonb_build_object(
      'external_id', new.external_id,
      'source_name', new.source_name,
      'origin_event_type', new.event_type,
      'project_key', v_project_key
    ),
    new.occurred_at
  );

  if v_project_id is not null then
    update public.memory_projects
    set last_memory_at = greatest(coalesce(last_memory_at, new.occurred_at), new.occurred_at),
        last_event_at = greatest(coalesce(last_event_at, new.occurred_at), new.occurred_at),
        updated_at = now()
    where id = v_project_id;
  end if;

  new.memory_item_id := v_memory_id;
  new.status := 'processed';
  new.processed_at := now();
  new.error_message := null;
  return new;
exception when others then
  new.status := 'failed';
  new.error_message := left(sqlerrm, 500);
  new.processed_at := now();
  return new;
end;
$function$;


-- Preserve the original evaluations; flag them as legacy instead of inventing retrospective tests.
update public.memory_knowledge k set metadata=metadata||jsonb_build_object('phase6_validation','legacy_unverified'),status=case when status='active' then 'candidate' else status end
where not exists(select 1 from public.memory_knowledge_experiences ke join public.memory_verifications v on v.experience_id=ke.experience_id where ke.knowledge_id=k.id);
update public.memory_learning_rules set status='candidate' where status='trusted' and not exists(select 1 from public.memory_learning_feedback f join public.memory_verifications v on v.experience_id=f.experience_id where f.rule_id=memory_learning_rules.id);
update public.memory_project_connectors set automatic=false where connector_type='chatgpt';

create or replace function public.memory_capture_v6(p_event jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare old_event public.memory_ingest_events%rowtype; ev public.memory_ingest_events%rowtype;
begin
 if p_event->>'owner_key' is distinct from 'duilio' then raise exception 'invalid_owner'; end if;
 if nullif(btrim(p_event->>'external_id'),'') is null then raise exception 'external_id_required'; end if;
 if p_event->'metadata'->>'claim_state'='verified' then raise exception 'capture_cannot_verify'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(pg_catalog.concat_ws('|',p_event->>'owner_key',p_event->>'source_type',p_event->>'external_id',p_event->>'event_type'),0));
 select * into old_event from public.memory_ingest_events where owner_key=p_event->>'owner_key' and source_type=p_event->>'source_type' and external_id=p_event->>'external_id' and event_type=p_event->>'event_type';
 if found then
  if old_event.title is distinct from p_event->>'title' or old_event.content is distinct from p_event->>'content' or old_event.project_key is distinct from p_event->>'project_key' or old_event.summary is distinct from p_event->>'summary' or old_event.metadata is distinct from coalesce(p_event->'metadata','{}'::jsonb) then raise exception 'event_id_reused_with_different_payload'; end if;
  return jsonb_build_object('id',old_event.id,'memory_item_id',old_event.memory_item_id,'experience_id',old_event.experience_id,'status',old_event.status,'project_id',old_event.project_id,'duplicate',true);
 end if;
 insert into public.memory_ingest_events(owner_key,project_key,project_name,source_type,source_name,external_id,event_type,title,content,summary,source_url,category,memory_type,importance,occurred_at,metadata)
 values('duilio',p_event->>'project_key',p_event->>'project_name',p_event->>'source_type',p_event->>'source_name',p_event->>'external_id',p_event->>'event_type',p_event->>'title',p_event->>'content',p_event->>'summary',p_event->>'source_url',coalesce(p_event->>'category','project_activity'),coalesce(p_event->>'memory_type','observation'),coalesce((p_event->>'importance')::smallint,6),coalesce((p_event->>'occurred_at')::timestamptz,now()),coalesce(p_event->'metadata','{}'::jsonb)) returning * into ev;
 return jsonb_build_object('id',ev.id,'memory_item_id',ev.memory_item_id,'experience_id',ev.experience_id,'status',ev.status,'project_id',ev.project_id,'error_message',ev.error_message,'duplicate',false);
end $$;

-- Snapshot includes current evidence-backed project state; historical snapshots stay sealed.
create or replace function public.memory_phase6_snapshot(p_owner_key text default 'duilio') returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('phase',6,'generated_at',now(),'owner_key',p_owner_key,
 'constitution',(select to_jsonb(c) from public.memory_constitution c where status='active' order by created_at desc limit 1),
 'projects',public.memory_project_health(p_owner_key),
 'current_state',coalesce((select jsonb_agg(public.memory_resume_project(p.project_key,p_owner_key) order by p.project_key) from public.memory_projects p where p.owner_key=p_owner_key and status='active'),'[]'::jsonb),
 'rules',coalesce((select jsonb_agg(jsonb_build_object('rule_key',r.rule_key,'statement',r.statement,'status',r.status,'confidence',r.confidence,'verified_sources',(select count(*) from public.memory_learning_feedback f join public.memory_verifications v on v.experience_id=f.experience_id where f.rule_id=r.id))) from public.memory_learning_rules r where r.owner_key=p_owner_key and r.status in ('trusted','candidate')),'[]'::jsonb),
 'limits',jsonb_build_array('Snapshot is external memory, not model weights or personal identity','Legacy records are not retrospectively verified','No model succession is certified by database tests'));
$$;

do $$ declare c public.memory_constitution%rowtype; begin
 select * into c from public.memory_constitution where status='active' order by created_at desc limit 1;
 if c.id is null then raise exception 'active_constitution_required'; end if;
 update public.memory_constitution set status='historical' where id=c.id;
 insert into public.memory_constitution(version,status,purpose,principles,assistant_identity,user_collaboration_model,reasoning_policy,affective_policy,migration_policy,parent_version,change_summary,behavior_dna,activated_at,metadata)
 values('6.0.0','active',c.purpose,c.principles,c.assistant_identity,c.user_collaboration_model,
 c.reasoning_policy||jsonb_build_object('evidence_policy','Distinguish recorded, requested, executed and verified. Only a recorded successful test validates completion.','freshness_policy','Respect validity windows and explicit supersession. Unknown is not success.'),
 c.affective_policy,c.migration_policy||jsonb_build_object('phase6_snapshot_rpc','memory_phase6_snapshot','database_tests_are_not_model_succession',true),c.version,
 'Fase 6: evidencia verificable, vigencia, idempotencia y aislamiento de acceso.',
 c.behavior_dna||jsonb_build_object('phase6',jsonb_build_array('Do not reinforce untested corrections','Do not equate a user request with completed work','Repeated evidence is not an independent success','Report configured connectivity separately from observed activity','Preserve history and acknowledge uncertainty')),
 now(),c.metadata||jsonb_build_object('phase',6,'validation','database_and_endpoint_tests_required'));
 update public.memory_constitution x set content_hash=encode(extensions.digest((jsonb_build_object('purpose',x.purpose,'principles',x.principles,'identity',x.assistant_identity,'collaboration',x.user_collaboration_model,'reasoning',x.reasoning_policy,'affective',x.affective_policy,'migration',x.migration_policy,'dna',x.behavior_dna))::text,'sha256'),'hex') where version='6.0.0';
end $$;


do $$ declare r record; begin
 for r in select p.oid::regprocedure obj from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'memory_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',r.obj);
 execute format('grant execute on function %s to service_role',r.obj);
 end loop;
end $$;

-- ============================================================================
-- 20260907124756_memoria_duilio_phase6_integration_suite
-- ============================================================================
create or replace function public.memory_run_phase6_tests() returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 results jsonb:='[]'::jsonb; pid uuid; other_pid uuid; item uuid; next_item uuid; e uuid; e2 uuid; e3 uuid;
 vid uuid; again uuid; kid uuid; r public.memory_learning_rules%rowtype; before_conf numeric;
 ok boolean; count_before integer; j jsonb; payload jsonb; ev jsonb; ev2 jsonb; run_owner text:='phase6-test-'||gen_random_uuid()::text;
begin
 -- All fixtures and side effects below are rolled back by the sentinel exception.
 begin
  insert into public.memory_projects(owner_key,project_key,project_name) values(run_owner,'test-project','Fase 6 tests') returning id into pid;
  insert into public.memory_projects(owner_key,project_key,project_name) values(run_owner||'-other','test-project','Other owner') returning id into other_pid;
  insert into public.memory_items(owner_key,project_id,memory_type,category,title,content,claim_state,subject_key,valid_from)
   values(run_owner,pid,'decision','phase6_test','Publicar versión','Pedido de publicación','requested','release',now()) returning id into item;
  results:=results||jsonb_build_array(jsonb_build_object('test','01_request_is_not_completion','passed',(select claim_state='requested' and verification_id is null from public.memory_items where id=item)));
  insert into public.memory_experiences(owner_key,project_id,memory_item_id,problem_type,solution,outcome,metadata)
   values(run_owner,pid,item,'deployment','Verificar antes de cerrar','failure',jsonb_build_object('rule_key','verify-release','rule_statement','Verificar antes de cerrar','rule_evidence','supports')) returning id into e;
  kid:=public.memory_learn_from_experience(e);
  results:=results||jsonb_build_array(jsonb_build_object('test','02_unverified_experience_not_learned','passed',kid is null and (select learning_status='pending' from public.memory_experiences where id=e)));
  select * into r from public.memory_reinforce_rule_from_experience(e);
  results:=results||jsonb_build_array(jsonb_build_object('test','03_unverified_rule_not_reinforced','passed',r.id is null));
  results:=results||jsonb_build_array(jsonb_build_object('test','04_supports_label_does_not_create_rule','passed',not exists(select 1 from public.memory_learning_rules where owner_key=run_owner)));
  ok:=false; begin perform public.memory_record_verification(e,'test://phase6/success','release','success','{}','sql-test'); exception when check_violation then ok:=true; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','05_empty_evidence_rejected','passed',ok));
  ok:=false; begin perform public.memory_record_verification(e,'test://phase6/success','release','success','{"http_status":200}','sql-test',now()+interval '1 day'); exception when others then ok:=sqlerrm='invalid_test_time'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','06_future_evidence_rejected','passed',ok));
  ok:=false; begin insert into public.memory_items(owner_key,project_id,memory_type,category,title,content) values(run_owner,other_pid,'observation','test','bad','bad'); exception when others then ok:=sqlerrm='project_owner_mismatch'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','07_cross_owner_project_rejected','passed',ok));
  ok:=false; begin insert into public.memory_experiences(owner_key,project_id,memory_item_id,problem_type,solution) values(run_owner||'-other',other_pid,item,'bad','bad'); exception when others then ok:=sqlerrm='experience_item_scope_mismatch'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','08_cross_owner_item_rejected','passed',ok));
  vid:=public.memory_record_verification(e,'test://phase6/success','release','success','{"http_status":200}','sql-test');
  results:=results||jsonb_build_array(jsonb_build_object('test','09_success_verifies_linked_item','passed',(select claim_state='verified' and verification_id=vid from public.memory_items where id=item)));
  results:=results||jsonb_build_array(jsonb_build_object('test','10_verified_experience_learned','passed',(select learning_status='learned' and linked_knowledge_id is not null from public.memory_experiences where id=e)));
  select confidence into before_conf from public.memory_learning_rules where owner_key=run_owner;
  again:=public.memory_record_verification(e,'test://phase6/success','release','success','{"http_status":200}','sql-test');
  perform public.memory_reinforce_rule_from_experience(e);
  results:=results||jsonb_build_array(jsonb_build_object('test','11_retry_is_idempotent','passed',again=vid and (select confidence=before_conf and evidence_count=1 from public.memory_learning_rules where owner_key=run_owner)));
  insert into public.memory_experiences(owner_key,project_id,problem_type,solution,outcome,metadata) values(run_owner,pid,'deployment','Verificar antes de cerrar','failure',jsonb_build_object('rule_key','verify-release','rule_statement','Verificar antes de cerrar','rule_evidence','supports')) returning id into e2;
  ok:=false; begin perform public.memory_record_verification(e2,'test://phase6/success','release','success','{"http_status":200}','sql-test'); exception when unique_violation then ok:=true; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','12_same_source_cannot_count_twice','passed',ok));
  ok:=false; begin perform public.memory_record_verification(e,'test://phase6/changed','release','success','{"http_status":200}','sql-test'); exception when others then ok:=sqlerrm='verification_immutable_create_new_experience'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','13_verification_cannot_be_rewritten','passed',ok));
  ok:=false; begin update public.memory_experiences set solution='Changed' where id=e; exception when others then ok:=sqlerrm='verified_experience_immutable'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','14_tested_solution_immutable','passed',ok));
  perform public.memory_record_verification(e2,'test://phase6/failure','release','failure','{"http_status":500}','sql-test');
  results:=results||jsonb_build_array(jsonb_build_object('test','15_failed_test_reduces_confidence_despite_supports','passed',(select confidence<before_conf and failure_count=1 from public.memory_learning_rules where owner_key=run_owner)));
  select confidence into before_conf from public.memory_learning_rules where owner_key=run_owner;
  insert into public.memory_experiences(owner_key,project_id,problem_type,solution,metadata) values(run_owner,pid,'deployment','Verificar antes de cerrar',jsonb_build_object('rule_key','verify-release','rule_statement','Verificar antes de cerrar')) returning id into e3;
  perform public.memory_record_verification(e3,'test://phase6/partial','release','partial','{"status":"partial"}','sql-test');
  results:=results||jsonb_build_array(jsonb_build_object('test','16_partial_test_does_not_increase_confidence','passed',(select confidence=before_conf from public.memory_learning_rules where owner_key=run_owner)));
  insert into public.memory_experiences(owner_key,project_id,problem_type,solution) values(run_owner,pid,'unknown','Sin comprobar') returning id into e3;
  kid:=public.memory_learn_from_experience(e3);
  results:=results||jsonb_build_array(jsonb_build_object('test','17_unknown_stays_pending','passed',kid is null and (select outcome='unknown' and learning_status='pending' from public.memory_experiences where id=e3)));
  ok:=false; begin perform public.memory_reinforce_rule(run_owner,'bypass','bypass','success'); exception when others then ok:=sqlerrm='verification_required_use_memory_record_verification'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','18_legacy_reinforcement_bypass_blocked','passed',ok));
  ok:=false; begin insert into public.memory_items(owner_key,project_id,memory_type,category,title,content,claim_state) values(run_owner,pid,'observation','test','bad','bad','verified'); exception when others then ok:=true; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','19_verified_state_requires_proof','passed',ok));
  ok:=false; begin insert into public.memory_items(owner_key,project_id,memory_type,category,title,content,claim_state,verification_id) values(run_owner,pid,'observation','test','bad','bad','verified',vid); exception when others then ok:=sqlerrm='verification_not_for_this_item'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','20_proof_cannot_be_reused_for_another_item','passed',ok));
  ok:=false; begin update public.memory_items set content='Altered after proof' where id=item; exception when others then ok:=sqlerrm='verified_content_immutable_create_revision'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','21_verified_content_immutable','passed',ok));
  insert into public.memory_items(owner_key,project_id,memory_type,category,title,content,subject_key,supersedes_id,valid_from)
   values(run_owner,pid,'decision','test','Nueva decisión','Nueva decisión aún sin probar','release',item,now()) returning id into next_item;
  results:=results||jsonb_build_array(jsonb_build_object('test','22_supersession_preserves_history','passed',(select status='superseded' and valid_until is not null from public.memory_items where id=item)));
  results:=results||jsonb_build_array(jsonb_build_object('test','23_single_current_subject','passed',(select count(*)=1 from public.memory_items where owner_key=run_owner and subject_key='release' and status='active')));
  ok:=false; begin insert into public.memory_items(owner_key,project_id,memory_type,category,title,content,supersedes_id) values(run_owner||'-other',other_pid,'decision','test','bad','bad',next_item); exception when others then ok:=sqlerrm='invalid_supersession_scope'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','24_cross_owner_supersession_blocked','passed',ok));
  insert into public.memory_items(owner_key,project_id,memory_type,category,title,content,valid_until) values(run_owner,pid,'observation','test','Expired','Expired',now()-interval '1 day');
  j:=public.memory_resume_project('test-project',run_owner);
  results:=results||jsonb_build_array(jsonb_build_object('test','25_resume_excludes_expired_and_replaced','passed',jsonb_array_length(j->'items')=1 and j->'items'->0->>'id'=next_item::text));
  j:=public.memory_resume_project('test-project',run_owner||'-other');
  results:=results||jsonb_build_array(jsonb_build_object('test','26_resume_is_owner_scoped','passed',jsonb_array_length(j->'items')=0));
  j:=public.memory_project_health(run_owner);
  results:=results||jsonb_build_array(jsonb_build_object('test','27_health_does_not_invent_capture','passed',j->0->>'activity_status'='never_received' and j->0->>'last_successful_retrieval_at' is null));
  j:=public.memory_phase6_snapshot(run_owner);
  results:=results||jsonb_build_array(jsonb_build_object('test','28_continuity_snapshot_has_current_state','passed',j->>'phase'='6' and jsonb_array_length(j->'current_state')=1 and j->'constitution'->>'version'='6.0.0'));
  results:=results||jsonb_build_array(jsonb_build_object('test','29_anon_has_no_memory_access','passed',not has_table_privilege('anon','public.memory_items','SELECT') and not has_function_privilege('anon','public.memory_record_verification(uuid,text,text,text,jsonb,text,timestamptz)','EXECUTE')));
  results:=results||jsonb_build_array(jsonb_build_object('test','30_authenticated_has_no_unassigned_access','passed',not has_table_privilege('authenticated','public.memory_items','SELECT') and not has_function_privilege('authenticated','public.memory_resume_project(text,text)','EXECUTE')));
  results:=results||jsonb_build_array(jsonb_build_object('test','31_six_legacy_tables_protected','passed',(select count(*)=6 and bool_and(c.relrowsecurity and not has_table_privilege('anon',c.oid,'SELECT') and has_table_privilege('service_role',c.oid,'SELECT')) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('documents','documents_go','workout_routine','n8n_chat_histories','n8n_chat_histories_supersargento','n8n_chat_histories_cavallero'))));
  payload:=jsonb_build_object('owner_key','duilio','project_key','phase6-fixture-'||left(replace(run_owner,'-',''),30),'project_name','Ephemeral fixture','source_type','phase6-test','source_name',run_owner,'external_id',run_owner,'event_type','test','title','Idempotency fixture','content','Ephemeral fixture','metadata',jsonb_build_object('claim_state','requested'));
  ev:=public.memory_capture_v6(payload);
  select count(*) into count_before from public.memory_events where memory_item_id=(ev->>'memory_item_id')::uuid;
  ev2:=public.memory_capture_v6(payload);
  results:=results||jsonb_build_array(jsonb_build_object('test','32_capture_retry_has_no_side_effects','passed',ev->>'id'=ev2->>'id' and ev2->>'duplicate'='true' and (select count(*)=count_before from public.memory_events where memory_item_id=(ev->>'memory_item_id')::uuid)));
  ok:=false; begin perform public.memory_capture_v6(payload||'{"content":"Different payload"}'::jsonb); exception when others then ok:=sqlerrm='event_id_reused_with_different_payload'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','33_reused_event_id_rejects_changes','passed',ok));
  ok:=false; begin perform public.memory_capture_v6(payload||jsonb_build_object('external_id',run_owner||'verified','metadata',jsonb_build_object('claim_state','verified'))); exception when others then ok:=sqlerrm='capture_cannot_verify'; end;
  results:=results||jsonb_build_array(jsonb_build_object('test','34_capture_cannot_certify_completion','passed',ok));
  raise exception using errcode='P6000',message='rollback_test_fixtures';
 exception when sqlstate 'P6000' then null;
 end;
 return jsonb_build_object('suite_version','phase6-db-v1','test_count',jsonb_array_length(results),'passed',not exists(select 1 from jsonb_array_elements(results) x where x->>'passed' is distinct from 'true'),'tests',results,'fixtures_rolled_back',true,'scope','Database integration and access controls; not a model succession benchmark');
end $$;
revoke all on function public.memory_run_phase6_tests() from public,anon,authenticated;
grant execute on function public.memory_run_phase6_tests() to service_role;

-- ============================================================================
-- 20260907125003_memoria_duilio_phase6_daily_snapshot_integration
-- ============================================================================
CREATE OR REPLACE FUNCTION public.memory_create_continuity_snapshot(p_owner_key text DEFAULT 'duilio'::text, p_model_family text DEFAULT 'gpt-5.6-work'::text, p_snapshot_type text DEFAULT 'succession'::text, p_snapshot_date date DEFAULT NULL::date)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c public.memory_constitution%rowtype;
  v_day date;
  v_identity jsonb;
  v_projects jsonb;
  v_collaboration jsonb;
  v_affective jsonb;
  v_lessons jsonb;
  v_payload jsonb;
  v_hash text;
  v_id bigint;
begin
  v_day := coalesce(
    p_snapshot_date,
    (now() at time zone 'America/Argentina/Buenos_Aires')::date
  );

  select * into c
  from public.memory_constitution
  where status = 'active'
  order by activated_at desc nulls last, created_at desc
  limit 1;

  if not found then
    raise exception 'active_constitution_not_found';
  end if;

  v_identity := jsonb_build_object(
    'constitution_version', c.version,
    'constitution_hash', c.content_hash,
    'purpose', c.purpose,
    'assistant_identity', c.assistant_identity,
    'behavior_dna', c.behavior_dna,
    'principles', c.principles
  );

  select jsonb_build_object(
    'active_count', count(*),
    'projects', coalesce(jsonb_agg(jsonb_build_object(
      'project_key', project_key,
      'project_name', project_name,
      'status', status,
      'capture_mode', capture_mode,
      'connector_status', connector_status,
      'last_memory_at', last_memory_at,
      'last_event_at', last_event_at
    ) order by project_name), '[]'::jsonb)
  ) into v_projects
  from public.memory_projects
  where owner_key = p_owner_key and status = 'active';

  v_collaboration := coalesce(c.user_collaboration_model, '{}'::jsonb)
    || jsonb_build_object(
      'reasoning_policy', c.reasoning_policy,
      'top_behavior_rules', coalesce((
        select jsonb_agg(jsonb_build_object(
          'rule_key', rule_key,
          'statement', statement,
          'confidence', confidence,
          'status', status
        ) order by confidence desc, updated_at desc)
        from (
          select *
          from public.memory_learning_rules
          where owner_key = p_owner_key
            and status in ('trusted', 'candidate')
          order by confidence desc, updated_at desc
          limit 20
        ) rules
      ), '[]'::jsonb)
    );

  select coalesce(to_jsonb(s), '{}'::jsonb)
    into v_affective
  from public.memory_affective_state s
  where s.owner_key = p_owner_key;
  v_affective := coalesce(v_affective, '{}'::jsonb)
    || jsonb_build_object('policy', c.affective_policy);

  select coalesce(jsonb_agg(item order by changed_at desc), '[]'::jsonb)
    into v_lessons
  from (
    select jsonb_build_object(
      'kind', 'knowledge',
      'id', id,
      'title', title,
      'statement', statement,
      'status', status,
      'confidence', confidence,
      'score', score
    ) as item, updated_at as changed_at
    from public.memory_knowledge
    where owner_key = p_owner_key and status <> 'deprecated'
    union all
    select jsonb_build_object(
      'kind', 'behavior_rule',
      'id', id,
      'title', rule_key,
      'statement', statement,
      'status', status,
      'confidence', confidence,
      'score', confidence
    ) as item, updated_at as changed_at
    from public.memory_learning_rules
    where owner_key = p_owner_key and status in ('trusted', 'candidate')
    order by changed_at desc
    limit 30
  ) recent_lessons;

  v_projects := v_projects || jsonb_build_object('evidence_backed_continuity',public.memory_phase6_snapshot(p_owner_key));

  v_payload := jsonb_build_object(
    'owner_key', p_owner_key,
    'snapshot_date', v_day,
    'snapshot_type', p_snapshot_type,
    'model_family', p_model_family,
    'identity_state', v_identity,
    'project_state', v_projects,
    'collaboration_state', v_collaboration,
    'affective_state', v_affective,
    'lessons', v_lessons
  );
  v_hash := encode(extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');

  select id into v_id
  from public.memory_continuity_snapshots
  where owner_key = p_owner_key
    and snapshot_type = p_snapshot_type
    and snapshot_date = v_day
    and constitution_version = c.version
    and coalesce(model_family, '') = coalesce(p_model_family, '')
  limit 1
  for update;

  if found then
    update public.memory_continuity_snapshots
    set identity_state = v_identity,
        project_state = v_projects,
        collaboration_state = v_collaboration,
        affective_state = v_affective,
        lessons = v_lessons,
        content_hash = v_hash,
        metadata = coalesce(metadata, '{}'::jsonb)
          || jsonb_build_object('refreshed_at', now())
    where id = v_id;
  else
    insert into public.memory_continuity_snapshots(
      constitution_version, model_family, snapshot_type,
      identity_state, project_state, collaboration_state,
      affective_state, lessons, owner_key, snapshot_date,
      content_hash, metadata
    ) values (
      c.version, p_model_family, p_snapshot_type,
      v_identity, v_projects, v_collaboration,
      v_affective, v_lessons, p_owner_key, v_day,
      v_hash, jsonb_build_object('created_by', 'memory_create_continuity_snapshot')
    ) returning id into v_id;
  end if;

  return v_id;
end
$function$;
CREATE OR REPLACE FUNCTION public.memory_learn_from_experience(p_experience_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  e public.memory_experiences%rowtype;
  k public.memory_knowledge%rowtype;
  v_fingerprint text;
  v_result text;
  v_relation_type text;
  v_quality numeric;
  v_confidence numeric;
  v_title text;
begin
  select * into e
  from public.memory_experiences
  where id = p_experience_id
  for update;

  if not found then
    raise exception 'experience_not_found';
  end if;

  if e.learning_status = 'learned' and e.linked_knowledge_id is not null then
    return e.linked_knowledge_id;
  end if;

  if not exists(select 1 from public.memory_verifications v where v.experience_id=e.id and v.owner_key=e.owner_key) then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(public.memory_make_knowledge_fingerprint(e.owner_key,e.project_id,e.problem_type,e.solution),0));

  v_result := lower(coalesce(e.outcome,'partial'));
  if v_result not in ('success','failure','partial') then
    v_result := 'partial';
  end if;

  v_relation_type := case v_result when 'success' then 'supports' when 'failure' then 'contradicts' else 'tests' end;
  v_quality := greatest(least(coalesce(e.quality_score,0.5),1),0);
  v_confidence := greatest(least(coalesce(e.confidence,0.5),1),0);
  v_fingerprint := public.memory_make_knowledge_fingerprint(e.owner_key, e.project_id, e.problem_type, e.solution);
  v_title := left(coalesce(nullif(trim(e.problem_type),''),'Conocimiento aprendido') || ': ' || coalesce(nullif(trim(e.solution),''),'sin solución registrada'), 180);

  select * into k
  from public.memory_knowledge
  where owner_key = e.owner_key
    and fingerprint = v_fingerprint
    and status <> 'deprecated'
  order by created_at asc
  limit 1
  for update;

  if not found then
    insert into public.memory_knowledge(
      owner_key, project_id, knowledge_type, problem_type, title, statement,
      status, confidence, use_count, success_count, failure_count, partial_count,
      evidence_count, last_used_at, last_validated_at, fingerprint, metadata
    ) values (
      e.owner_key, e.project_id, 'learned_rule', e.problem_type, v_title, e.solution,
      'candidate', round(((v_confidence + v_quality) / 2)::numeric,4), 1,
      case when v_result='success' then 1 else 0 end,
      case when v_result='failure' then 1 else 0 end,
      case when v_result='partial' then 1 else 0 end,
      1, e.occurred_at,
      case when v_result='success' then e.occurred_at else null end,
      v_fingerprint,
      jsonb_build_object('created_from_experience', e.id, 'model_name', e.model_name)
    ) returning * into k;
  else
    update public.memory_knowledge
       set use_count = use_count + 1,
           success_count = success_count + case when v_result='success' then 1 else 0 end,
           failure_count = failure_count + case when v_result='failure' then 1 else 0 end,
           partial_count = partial_count + case when v_result='partial' then 1 else 0 end,
           evidence_count = evidence_count + 1,
           confidence = round((confidence * 0.75 + ((v_confidence + v_quality)/2) * 0.25)::numeric,4),
           last_used_at = greatest(coalesce(last_used_at,e.occurred_at), e.occurred_at),
           last_validated_at = case when v_result='success' then greatest(coalesce(last_validated_at,e.occurred_at),e.occurred_at) else last_validated_at end,
           updated_at = now()
     where id = k.id
     returning * into k;
  end if;

  insert into public.memory_knowledge_experiences(knowledge_id, experience_id, relation_type, weight)
  values (k.id, e.id, v_relation_type, greatest(0.1, v_quality))
  on conflict (knowledge_id, experience_id) do update
    set relation_type = excluded.relation_type,
        weight = excluded.weight;

  insert into public.memory_evaluations(owner_key, project_id, experience_id, knowledge_id, evaluator, result, score, notes, evidence)
  values (e.owner_key, e.project_id, e.id, k.id, 'phase3_engine_v1', v_result, v_quality,
          'Evaluación automática generada por memory_learn_from_experience', e.evidence);

  perform public.memory_refresh_knowledge_score(k.id);

  update public.memory_knowledge
     set status = case
       when failure_count >= 3 and failure_count > success_count * 2 then 'review'
       when success_count >= 3 and success_count >= failure_count * 2 and (select count(*) from public.memory_knowledge_experiences ke join public.memory_verifications v on v.experience_id=ke.experience_id where ke.knowledge_id=memory_knowledge.id and v.result='success') >= 3 then 'active'
       else status
     end,
     updated_at = now()
   where id = k.id;

  update public.memory_experiences
     set learning_status = 'learned',
         linked_knowledge_id = k.id,
         learned_at = now(),
         updated_at = now()
   where id = e.id;

  return k.id;
end;
$function$;

-- ============================================================================
-- 20260908002023_phase7_progress_tracking
-- ============================================================================
create table if not exists public.memory_phase_progress (
  id uuid primary key default gen_random_uuid(),
  project_key text not null,
  phase integer not null,
  phase_name text not null,
  status text not null default 'planned',
  progress_percent integer not null default 0 check (progress_percent between 0 and 100),
  current_step text,
  completed_steps jsonb not null default '[]'::jsonb,
  pending_steps jsonb not null default '[]'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(project_key, phase)
);
create index if not exists idx_memory_phase_progress_project_status on public.memory_phase_progress(project_key,status);
comment on table public.memory_phase_progress is 'Estado auditable y porcentaje de avance de las fases de Memoria Duilio.';

-- ============================================================================
-- 20260909155339_memoria_duilio_capa0_startup_context
-- ============================================================================
CREATE OR REPLACE FUNCTION public.memory_resume_project(p_project_key text, p_owner_key text DEFAULT 'duilio')
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $function$
declare pid uuid; result jsonb; startup jsonb; pinned jsonb;
begin
 select id into pid from public.memory_projects
 where project_key=p_project_key and owner_key=p_owner_key and status='active';
 if pid is null then raise exception 'project_not_found'; end if;

 -- Explicit central startup subjects only: do not copy unrelated project content.
 select coalesce(jsonb_agg(x order by x.subject_key,x.id),'[]'::jsonb) into startup
 from (
  select m.id,m.title,m.content,m.summary,m.claim_state,m.subject_key,
   m.updated_at,m.valid_from,m.valid_until,p.project_key,
   v.source_ref,v.test_key,v.tested_at,v.verified_by
  from public.memory_items m join public.memory_projects p on p.id=m.project_id
  left join public.memory_verifications v on v.id=m.verification_id
  where p.project_key='memoria-duilio' and p.owner_key=p_owner_key and p.status='active'
   and m.owner_key=p_owner_key and m.status='active'
   and m.subject_key in ('capa0-startup-phase-continuity','phase6-evidence-controls',
     'phase7-proactive-project-catalog','phase8-automatic-verification')
   and (m.valid_from is null or m.valid_from<=now())
   and (m.valid_until is null or m.valid_until>now())
 ) x;

 -- Named current decisions/states are never displaced by the 30 recent observations.
 select coalesce(jsonb_agg(m.id),'[]'::jsonb) into pinned
 from public.memory_items m
 where m.project_id=pid and m.owner_key=p_owner_key and m.status='active'
  and m.subject_key is not null
  and (m.valid_from is null or m.valid_from<=now())
  and (m.valid_until is null or m.valid_until>now());

 select jsonb_build_object('project_key',p_project_key,'as_of',now(),
  'items',coalesce(jsonb_agg(x order by x.updated_at desc,x.id),'[]'::jsonb),
  'interpretation','Only claim_state=verified has a recorded successful test. Requested, executed and recorded are not verified completion.',
  'startup_context',startup,
  'startup',jsonb_build_object('version','0.2','required_before_response',true,
    'protocol_present',exists(select 1 from jsonb_array_elements(startup) s where s->>'subject_key'='capa0-startup-phase-continuity'),
    'phase_keys',jsonb_build_array(6,7,8),
    'scope','Backend retrieval; consumer execution and new-chat startup are not certified.',
    'project_state_policy','all current named subjects plus 30 recent items',
    'pinned_item_ids',pinned)) into result
 from (
  select m.id,m.title,m.content,m.summary,m.claim_state,m.subject_key,m.updated_at,m.valid_from,m.valid_until,
    v.source_ref,v.test_key,v.tested_at,v.verified_by
  from public.memory_items m left join public.memory_verifications v on v.id=m.verification_id
  where m.project_id=pid and m.owner_key=p_owner_key and m.status='active'
   and (m.valid_from is null or m.valid_from<=now())
   and (m.valid_until is null or m.valid_until>now())
   and (m.subject_key is not null or m.id in (
    select r.id from public.memory_items r
    where r.project_id=pid and r.owner_key=p_owner_key and r.status='active'
      and (r.valid_from is null or r.valid_from<=now())
      and (r.valid_until is null or r.valid_until>now())
    order by r.updated_at desc,r.id limit 30))
 ) x;
 return result;
end $function$;
REVOKE ALL ON FUNCTION public.memory_resume_project(text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.memory_resume_project(text,text) TO service_role;

-- ============================================================================
-- 20260909155510_memoria_duilio_protect_phase_progress
-- ============================================================================
ALTER TABLE public.memory_phase_progress ENABLE ROW LEVEL SECURITY; REVOKE ALL ON public.memory_phase_progress FROM PUBLIC, anon, authenticated; GRANT ALL ON public.memory_phase_progress TO service_role;

-- ============================================================================
-- 20260909155541_memoria_duilio_daily_startup_checks
-- ============================================================================
CREATE TABLE public.memory_startup_checks (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 checked_at timestamptz NOT NULL DEFAULT now(),
 owner_key text NOT NULL,
 passed boolean NOT NULL,
 results jsonb NOT NULL,
 scope text NOT NULL DEFAULT 'backend startup retrieval only; not cross-chat certification'
);
ALTER TABLE public.memory_startup_checks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.memory_startup_checks FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON public.memory_startup_checks TO service_role;
CREATE FUNCTION public.memory_check_startup(p_owner_key text DEFAULT 'duilio')
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $fn$
declare p record; r jsonb; checks jsonb='[]'::jsonb; ok boolean=true; item_ok boolean; run_id uuid; cnt integer=0;
begin
 for p in select project_key from public.memory_projects where owner_key=p_owner_key and status='active'
 loop
  cnt:=cnt+1;
  begin
   r:=public.memory_resume_project(p.project_key,p_owner_key);
   item_ok:=coalesce((r->'startup'->>'protocol_present')::boolean,false)
    and (r->'startup_context' @> '[{"subject_key":"phase6-evidence-controls"},{"subject_key":"phase7-proactive-project-catalog"},{"subject_key":"phase8-automatic-verification"}]'::jsonb);
   ok:=ok and item_ok;
   checks:=checks||jsonb_build_array(jsonb_build_object('project_key',p.project_key,'passed',item_ok,'check','startup_and_phases_6_7_8'));
  exception when others then
   ok:=false;
   checks:=checks||jsonb_build_array(jsonb_build_object('project_key',p.project_key,'passed',false,'error',sqlerrm));
  end;
 end loop;
 if cnt=0 then ok:=false; checks:=checks||'[{"passed":false,"error":"no_active_projects"}]'::jsonb; end if;
 insert into public.memory_startup_checks(owner_key,passed,results) values(p_owner_key,ok,checks) returning id into run_id;
 return jsonb_build_object('run_id',run_id,'passed',ok,'checks',checks,'scope','backend retrieval only; phases 7 and 8 completion not certified');
end $fn$;
REVOKE ALL ON FUNCTION public.memory_check_startup(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.memory_check_startup(text) TO service_role;

-- ============================================================================
-- 20260913202036_phase9_execution_ledger
-- ============================================================================
-- Phase 9: private execution ledger. Trello https://trello.com/c/isqUeQLf
create table public.memory_execution_runs (
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.memory_projects(id),
 card_url text not null check(card_url ~ '^https://trello[.]com/c/[A-Za-z0-9]+$'),
 run_key text not null unique check(length(run_key) between 1 and 240),
 executor text not null check(length(trim(executor)) between 1 and 160),
 state text not null default 'running' check(state in ('running','partial','failed','completed','blocked','expired')),
 last_action text not null,
 result text,
 blockers jsonb not null default '[]' check(jsonb_typeof(blockers)='array'),
 evidence jsonb not null check(jsonb_typeof(evidence)='array' and jsonb_array_length(evidence)>0),
 version text,
 started_at timestamptz not null default clock_timestamp(),
 heartbeat_at timestamptz not null default clock_timestamp(),
 lease_until timestamptz not null default clock_timestamp()+interval '5 minutes',
 finished_at timestamptz,
 lease_token uuid not null default gen_random_uuid()
);
create unique index memory_execution_one_running_card on public.memory_execution_runs(card_url) where state='running';
create index memory_execution_project_history on public.memory_execution_runs(project_id,started_at desc);
alter table public.memory_execution_runs enable row level security;
revoke all on public.memory_execution_runs from public,anon,authenticated;
grant all on public.memory_execution_runs to service_role;

create table public.memory_execution_events (
 id bigint generated always as identity primary key,
 run_id uuid not null references public.memory_execution_runs(id),
 recorded_at timestamptz not null default clock_timestamp(),
 snapshot jsonb not null
);
create index memory_execution_events_run on public.memory_execution_events(run_id,id desc);
alter table public.memory_execution_events enable row level security;
revoke all on public.memory_execution_events from public,anon,authenticated;
grant select,insert on public.memory_execution_events to service_role;
grant usage,select on sequence public.memory_execution_events_id_seq to service_role;

create function public.memory_execution_audit() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 insert into public.memory_execution_events(run_id,snapshot) values(new.id,to_jsonb(new)-'lease_token');
 return new;
end $$;
revoke all on function public.memory_execution_audit() from public,anon,authenticated;
create trigger memory_execution_audit after insert or update on public.memory_execution_runs for each row execute function public.memory_execution_audit();

create function public.memory_execution_claim(p_project_key text,p_card_url text,p_run_key text,p_executor text,p_action text,p_evidence jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.memory_execution_runs; p uuid;
begin
 if coalesce(length(trim(p_action)),0)=0 then raise exception 'action required'; end if;
 select id into p from public.memory_projects where owner_key='duilio' and project_key=p_project_key and status='active';
 if p is null then raise exception 'unknown active project'; end if;
 -- Serializes claims for the same card, including expiration and retry.
 perform pg_advisory_xact_lock(hashtextextended(p_card_url,9));
 select * into r from public.memory_execution_runs where run_key=p_run_key;
 if found then
   if r.project_id<>p or r.card_url<>p_card_url or r.executor<>p_executor then raise exception 'run key conflict'; end if;
   return jsonb_build_object('claimed',false,'duplicate',true,'run_id',r.id,'state',r.state);
 end if;
 update public.memory_execution_runs set state='expired',finished_at=clock_timestamp(),result='Sin actividad reciente; resultado del trabajo desconocido'
 where card_url=p_card_url and state='running' and lease_until<=clock_timestamp();
 if exists(select 1 from public.memory_execution_runs where card_url=p_card_url and state='running') then
   return jsonb_build_object('claimed',false,'reason','card_busy');
 end if;
 insert into public.memory_execution_runs(project_id,card_url,run_key,executor,last_action,evidence)
 values(p,p_card_url,p_run_key,p_executor,p_action,p_evidence) returning * into r;
 return jsonb_build_object('claimed',true,'run_id',r.id,'lease_token',r.lease_token,'lease_until',r.lease_until);
end $$;
revoke all on function public.memory_execution_claim(text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.memory_execution_claim(text,text,text,text,text,jsonb) to service_role;

create function public.memory_execution_update(p_run_id uuid,p_lease_token uuid,p_state text,p_action text,p_result text default null,p_evidence jsonb default '[]',p_blockers jsonb default '[]',p_version text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.memory_execution_runs;
begin
 if p_state not in ('running','partial','failed','completed','blocked') or p_state is null then raise exception 'invalid state'; end if;
 if coalesce(length(trim(p_action)),0)=0 then raise exception 'action required'; end if;
 if jsonb_typeof(p_evidence)<>'array' or jsonb_typeof(p_blockers)<>'array' or p_evidence is null or p_blockers is null then raise exception 'arrays required'; end if;
 if p_state<>'running' and coalesce(length(trim(p_result)),0)=0 then raise exception 'terminal result required'; end if;
 if p_state='completed' and (jsonb_array_length(p_evidence)=0 or jsonb_array_length(p_blockers)>0) then raise exception 'completion requires evidence and no blockers'; end if;
 select * into r from public.memory_execution_runs where id=p_run_id for update;
 if not found or r.lease_token is distinct from p_lease_token or r.state<>'running' or r.lease_until<=clock_timestamp() then raise exception 'invalid or expired lease'; end if;
 update public.memory_execution_runs set
 state=p_state,last_action=p_action,result=p_result,evidence=case when jsonb_array_length(p_evidence)>0 then p_evidence else evidence end,
 blockers=p_blockers,version=coalesce(p_version,version),heartbeat_at=clock_timestamp(),
 lease_until=clock_timestamp()+interval '5 minutes',finished_at=case when p_state='running' then null else clock_timestamp() end
 where id=p_run_id returning * into r;
 return to_jsonb(r)-'lease_token';
end $$;
revoke all on function public.memory_execution_update(uuid,uuid,text,text,text,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.memory_execution_update(uuid,uuid,text,text,text,jsonb,jsonb,text) to service_role;

create function public.memory_execution_overview(p_project_key text default null)
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(s)),'[]') from (
 select p.project_key,p.project_name,
   coalesce((select jsonb_agg(to_jsonb(h)-'lease_token'-'project_id') from
    (select r.*,case when r.state='running' and r.lease_until<=now() then 'inactive' else r.state end as observed_state
     from public.memory_execution_runs r where r.project_id=p.id order by r.started_at desc limit 20) h),'[]') as runs,
   p.metadata->'trello_execution' as legacy_execution
 from public.memory_projects p where p.owner_key='duilio' and p.status='active'
 and (p_project_key is null or p.project_key=p_project_key) order by p.project_name
 ) s
$$;
revoke all on function public.memory_execution_overview(text) from public,anon,authenticated;
grant execute on function public.memory_execution_overview(text) to service_role;

-- ============================================================================
-- 20260917000048_load_active_operational_rules_in_startup
-- ============================================================================
create or replace function public.memory_resume_project(p_project_key text, p_owner_key text default 'duilio'::text)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
 pid uuid;
 result jsonb;
 startup jsonb;
 pinned jsonb;
 operational_rules jsonb;
begin
 select id into pid from public.memory_projects
 where project_key=p_project_key and owner_key=p_owner_key and status='active';
 if pid is null then raise exception 'project_not_found'; end if;

 select coalesce(jsonb_agg(x order by x.subject_key,x.id),'[]'::jsonb) into startup
 from (
  select m.id,m.title,m.content,m.summary,m.claim_state,m.subject_key,
   m.updated_at,m.valid_from,m.valid_until,p.project_key,
   v.source_ref,v.test_key,v.tested_at,v.verified_by
  from public.memory_items m join public.memory_projects p on p.id=m.project_id
  left join public.memory_verifications v on v.id=m.verification_id
  where p.project_key='memoria-duilio' and p.owner_key=p_owner_key and p.status='active'
   and m.owner_key=p_owner_key and m.status='active'
   and m.subject_key in ('capa0-startup-phase-continuity','phase6-evidence-controls',
     'phase7-proactive-project-catalog','phase8-automatic-verification')
   and (m.valid_from is null or m.valid_from<=now())
   and (m.valid_until is null or m.valid_until>now())
 ) x;

 select coalesce(jsonb_agg(jsonb_build_object(
   'id',r.id,
   'rule_key',r.rule_key,
   'statement',r.statement,
   'confidence',r.confidence,
   'status',r.status,
   'provenance',r.provenance,
   'updated_at',r.updated_at
 ) order by r.rule_key),'[]'::jsonb)
 into operational_rules
 from public.memory_learning_rules r
 where r.owner_key=p_owner_key and r.status='active';

 select coalesce(jsonb_agg(m.id),'[]'::jsonb) into pinned
 from public.memory_items m
 where m.project_id=pid and m.owner_key=p_owner_key and m.status='active'
  and m.subject_key is not null
  and (m.valid_from is null or m.valid_from<=now())
  and (m.valid_until is null or m.valid_until>now());

 select jsonb_build_object(
  'project_key',p_project_key,
  'as_of',now(),
  'items',coalesce(jsonb_agg(x order by x.updated_at desc,x.id),'[]'::jsonb),
  'interpretation','Only claim_state=verified has a recorded successful test. Requested, executed and recorded are not verified completion.',
  'startup_context',startup,
  'operational_rules',operational_rules,
  'startup',jsonb_build_object(
    'version','0.3',
    'required_before_response',true,
    'protocol_present',exists(select 1 from jsonb_array_elements(startup) s where s->>'subject_key'='capa0-startup-phase-continuity'),
    'operational_rules_loaded',jsonb_array_length(operational_rules),
    'phase_keys',jsonb_build_array(6,7,8),
    'scope','Backend retrieval. Consumers must read startup_context and operational_rules before routing or execution.',
    'project_state_policy','all current named subjects plus 30 recent items',
    'pinned_item_ids',pinned
  )
 ) into result
 from (
  select m.id,m.title,m.content,m.summary,m.claim_state,m.subject_key,m.updated_at,m.valid_from,m.valid_until,
    v.source_ref,v.test_key,v.tested_at,v.verified_by
  from public.memory_items m left join public.memory_verifications v on v.id=m.verification_id
  where m.project_id=pid and m.owner_key=p_owner_key and m.status='active'
   and (m.valid_from is null or m.valid_from<=now())
   and (m.valid_until is null or m.valid_until>now())
   and (m.subject_key is not null or m.id in (
    select r.id from public.memory_items r
    where r.project_id=pid and r.owner_key=p_owner_key and r.status='active'
      and (r.valid_from is null or r.valid_from<=now())
      and (r.valid_until is null or r.valid_until>now())
    order by r.updated_at desc,r.id limit 30))
 ) x;
 return result;
end
$function$;

create or replace function public.memory_check_startup(p_owner_key text default 'duilio'::text)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
 p record;
 r jsonb;
 checks jsonb='[]'::jsonb;
 ok boolean=true;
 item_ok boolean;
 run_id uuid;
 cnt integer=0;
begin
 for p in select project_key from public.memory_projects where owner_key=p_owner_key and status='active'
 loop
  cnt:=cnt+1;
  begin
   r:=public.memory_resume_project(p.project_key,p_owner_key);
   item_ok:=coalesce((r->'startup'->>'protocol_present')::boolean,false)
    and coalesce((r->'startup'->>'operational_rules_loaded')::integer,0) > 0
    and exists(
      select 1 from jsonb_array_elements(r->'operational_rules') q
      where q->>'rule_key'='optimize_work_quota_before_execution'
    )
    and (r->'startup_context' @> '[{"subject_key":"phase6-evidence-controls"},{"subject_key":"phase7-proactive-project-catalog"},{"subject_key":"phase8-automatic-verification"}]'::jsonb);
   ok:=ok and item_ok;
   checks:=checks||jsonb_build_array(jsonb_build_object(
     'project_key',p.project_key,
     'passed',item_ok,
     'check','startup_phases_and_operational_rules'
   ));
  exception when others then
   ok:=false;
   checks:=checks||jsonb_build_array(jsonb_build_object('project_key',p.project_key,'passed',false,'error',sqlerrm));
  end;
 end loop;
 if cnt=0 then
   ok:=false;
   checks:=checks||'[{"passed":false,"error":"no_active_projects"}]'::jsonb;
 end if;
 insert into public.memory_startup_checks(owner_key,passed,results)
 values(p_owner_key,ok,checks) returning id into run_id;
 return jsonb_build_object(
   'run_id',run_id,
   'passed',ok,
   'checks',checks,
   'scope','Backend retrieval verifies Capa 0, phases 6/7/8 context, and active operational rules.'
 );
end
$function$;

-- ============================================================================
-- 20260917001813_memory_brain_router_graph_learning_cycle_v2
-- ============================================================================
-- Memoria Duilio: Router Cerebral + grafo vivo + ciclo de aprendizaje verificado

create unique index if not exists memory_relations_unique_active_idx
on public.memory_relations(owner_key, source_entity_id, relation_type, target_entity_id)
where valid_until is null;

create unique index if not exists memory_experiences_execution_run_idx
on public.memory_experiences ((metadata->>'execution_run_id'))
where metadata ? 'execution_run_id';

create or replace function public.memory_ensure_entity(
  p_owner_key text,
  p_entity_type text,
  p_canonical_name text,
  p_aliases text[] default '{}'::text[],
  p_external_ids jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
set search_path to ''
as $function$
declare v_id uuid;
begin
  if nullif(btrim(p_owner_key),'') is null or nullif(btrim(p_entity_type),'') is null or nullif(btrim(p_canonical_name),'') is null then
    raise exception 'owner_entity_type_and_name_required';
  end if;
  insert into public.memory_entities(owner_key,entity_type,canonical_name,aliases,external_ids,metadata)
  values(btrim(p_owner_key),btrim(p_entity_type),btrim(p_canonical_name),coalesce(p_aliases,'{}'::text[]),coalesce(p_external_ids,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb))
  on conflict(owner_key,entity_type,canonical_name) do update
    set aliases=(select array(select distinct x from unnest(coalesce(public.memory_entities.aliases,'{}'::text[]) || coalesce(excluded.aliases,'{}'::text[])) x where nullif(btrim(x),'') is not null)),
        external_ids=coalesce(public.memory_entities.external_ids,'{}'::jsonb) || coalesce(excluded.external_ids,'{}'::jsonb),
        metadata=coalesce(public.memory_entities.metadata,'{}'::jsonb) || coalesce(excluded.metadata,'{}'::jsonb),
        updated_at=now()
  returning id into v_id;
  return v_id;
end
$function$;

create or replace function public.memory_link_entities(
  p_owner_key text,
  p_source_entity_id uuid,
  p_relation_type text,
  p_target_entity_id uuid,
  p_confidence numeric default 1,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
set search_path to ''
as $function$
declare v_id uuid;
begin
  if p_source_entity_id is null or p_target_entity_id is null or p_source_entity_id=p_target_entity_id then raise exception 'invalid_relation'; end if;
  if nullif(btrim(p_relation_type),'') is null then raise exception 'relation_type_required'; end if;
  select id into v_id from public.memory_relations
   where owner_key=p_owner_key and source_entity_id=p_source_entity_id and relation_type=btrim(p_relation_type)
     and target_entity_id=p_target_entity_id and valid_until is null
   limit 1;
  if v_id is not null then
    update public.memory_relations set confidence=greatest(confidence,least(greatest(coalesce(p_confidence,1),0),1)), metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb)
    where id=v_id;
    return v_id;
  end if;
  insert into public.memory_relations(owner_key,source_entity_id,relation_type,target_entity_id,confidence,metadata)
  values(p_owner_key,p_source_entity_id,btrim(p_relation_type),p_target_entity_id,least(greatest(coalesce(p_confidence,1),0),1),coalesce(p_metadata,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end
$function$;

create or replace function public.memory_sync_project_graph(p_owner_key text default 'duilio'::text)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_memory uuid;
  v_project uuid;
  v_system uuid;
  p record;
  v_count integer:=0;
begin
  v_memory:=public.memory_ensure_entity(p_owner_key,'system','Memoria Duilio',array['Memoria 9'],jsonb_build_object('system_key','memoria-duilio'),jsonb_build_object('role','brain'));

  v_system:=public.memory_ensure_entity(p_owner_key,'executor','Chat','{}'::text[],jsonb_build_object('executor_key','chat'),jsonb_build_object('role','conversation_and_reasoning'));
  perform public.memory_link_entities(p_owner_key,v_memory,'usa',v_system,1,jsonb_build_object('source','brain_sync'));
  v_system:=public.memory_ensure_entity(p_owner_key,'executor','Work','{}'::text[],jsonb_build_object('executor_key','work'),jsonb_build_object('role','long_multistep_execution'));
  perform public.memory_link_entities(p_owner_key,v_memory,'usa',v_system,1,jsonb_build_object('source','brain_sync'));
  v_system:=public.memory_ensure_entity(p_owner_key,'orchestrator','n8n','{}'::text[],jsonb_build_object('system_key','n8n'),jsonb_build_object('role','automation'));
  perform public.memory_link_entities(p_owner_key,v_memory,'orquesta_con',v_system,1,jsonb_build_object('source','brain_sync'));
  v_system:=public.memory_ensure_entity(p_owner_key,'database','Supabase','{}'::text[],jsonb_build_object('system_key','supabase'),jsonb_build_object('role','source_of_truth'));
  perform public.memory_link_entities(p_owner_key,v_memory,'persiste_en',v_system,1,jsonb_build_object('source','brain_sync'));
  v_system:=public.memory_ensure_entity(p_owner_key,'task_system','Trello','{}'::text[],jsonb_build_object('system_key','trello'),jsonb_build_object('role','execution_board'));
  perform public.memory_link_entities(p_owner_key,v_memory,'coordina_tareas_en',v_system,1,jsonb_build_object('source','brain_sync'));
  v_system:=public.memory_ensure_entity(p_owner_key,'code_system','GitHub','{}'::text[],jsonb_build_object('system_key','github'),jsonb_build_object('role','code_repository'));
  perform public.memory_link_entities(p_owner_key,v_memory,'conecta_codigo_en',v_system,1,jsonb_build_object('source','brain_sync'));

  for p in select * from public.memory_projects where owner_key=p_owner_key and status='active' order by project_name loop
    v_project:=public.memory_ensure_entity(
      p_owner_key,'project',p.project_name,'{}'::text[],
      jsonb_build_object('project_key',p.project_key,'project_id',p.id),
      jsonb_build_object('source_system',p.source_system,'source_ref',p.source_ref)
    );
    perform public.memory_link_entities(p_owner_key,v_memory,'gestiona',v_project,1,jsonb_build_object('source','project_catalog'));
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('projects_synced',v_count,'root_entity_id',v_memory);
end
$function$;

create or replace function public.memory_graph_context(
  p_owner_key text default 'duilio'::text,
  p_project_key text default null,
  p_entity_name text default null,
  p_depth integer default 2
) returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare v_root uuid; v_depth integer:=least(greatest(coalesce(p_depth,2),1),3); v_result jsonb;
begin
  if p_project_key is not null then
    select e.id into v_root
    from public.memory_entities e
    where e.owner_key=p_owner_key and e.external_ids->>'project_key'=p_project_key
    order by e.updated_at desc limit 1;
  end if;
  if v_root is null and nullif(btrim(p_entity_name),'') is not null then
    select e.id into v_root from public.memory_entities e
    where e.owner_key=p_owner_key and (lower(e.canonical_name)=lower(btrim(p_entity_name)) or exists(select 1 from unnest(coalesce(e.aliases,'{}'::text[])) a where lower(a)=lower(btrim(p_entity_name))))
    order by e.updated_at desc limit 1;
  end if;
  if v_root is null then
    select e.id into v_root from public.memory_entities e where e.owner_key=p_owner_key and e.canonical_name='Memoria Duilio' order by e.updated_at desc limit 1;
  end if;
  if v_root is null then return jsonb_build_object('root',null,'nodes','[]'::jsonb,'edges','[]'::jsonb); end if;

  with recursive walk(entity_id,depth,path) as (
    select v_root,0,array[v_root]::uuid[]
    union all
    select case when r.source_entity_id=w.entity_id then r.target_entity_id else r.source_entity_id end,
           w.depth+1,
           w.path || case when r.source_entity_id=w.entity_id then r.target_entity_id else r.source_entity_id end
    from walk w
    join public.memory_relations r on r.owner_key=p_owner_key and r.valid_until is null and (r.source_entity_id=w.entity_id or r.target_entity_id=w.entity_id)
    where w.depth<v_depth
      and not (case when r.source_entity_id=w.entity_id then r.target_entity_id else r.source_entity_id end = any(w.path))
  ), ids as (select distinct entity_id from walk),
  nodes as (
    select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'type',e.entity_type,'name',e.canonical_name,'aliases',e.aliases,'external_ids',e.external_ids,'metadata',e.metadata) order by e.canonical_name),'[]'::jsonb) j
    from public.memory_entities e join ids i on i.entity_id=e.id
  ), edges as (
    select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'source_id',r.source_entity_id,'relation',r.relation_type,'target_id',r.target_entity_id,'confidence',r.confidence,'metadata',r.metadata) order by r.created_at),'[]'::jsonb) j
    from public.memory_relations r
    where r.owner_key=p_owner_key and r.valid_until is null and r.source_entity_id in (select entity_id from ids) and r.target_entity_id in (select entity_id from ids)
  )
  select jsonb_build_object('root',v_root,'depth',v_depth,'nodes',nodes.j,'edges',edges.j) into v_result from nodes,edges;
  return v_result;
end
$function$;

create or replace function public.memory_execution_to_experience(p_run_id uuid)
returns uuid
language plpgsql
set search_path to ''
as $function$
declare r public.memory_execution_runs%rowtype; p public.memory_projects%rowtype; v_id uuid; v_outcome text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_run_id::text,31));
  select * into r from public.memory_execution_runs where id=p_run_id;
  if not found then raise exception 'execution_run_not_found'; end if;
  if r.state='running' then return null; end if;
  select * into p from public.memory_projects where id=r.project_id;
  select id into v_id from public.memory_experiences where metadata->>'execution_run_id'=p_run_id::text limit 1;
  if v_id is not null then return v_id; end if;
  v_outcome:=case r.state when 'failed' then 'failure' when 'partial' then 'partial' else 'unknown' end;
  insert into public.memory_experiences(owner_key,project_id,problem_type,context,solution,model_name,outcome,quality_score,confidence,evidence,metadata,occurred_at,learning_status)
  values(
    coalesce(p.owner_key,'duilio'),r.project_id,'execution:'||coalesce(r.run_key,'run'),
    concat_ws(E'\n','Proyecto: '||coalesce(p.project_name,'desconocido'),'Ejecutor: '||coalesce(r.executor,'desconocido'),'Acción: '||coalesce(r.last_action,'')),
    coalesce(nullif(r.result,''),r.last_action,'Sin resultado registrado'),r.executor,v_outcome,
    case when r.state='completed' then 0.8 when r.state='partial' then 0.5 when r.state='failed' then 0.2 else 0.4 end,
    0.6,coalesce(r.evidence,'[]'::jsonb),
    jsonb_build_object('execution_run_id',r.id,'run_key',r.run_key,'card_url',r.card_url,'state',r.state,'version',r.version,'blockers',r.blockers),
    coalesce(r.finished_at,r.heartbeat_at,r.started_at,now()),'pending'
  ) returning id into v_id;
  return v_id;
end
$function$;

create or replace function public.memory_verify_execution_and_learn(
  p_run_id uuid,
  p_test_key text,
  p_result text,
  p_evidence jsonb,
  p_verified_by text,
  p_source_ref text default null
) returns jsonb
language plpgsql
set search_path to ''
as $function$
declare r public.memory_execution_runs%rowtype; v_experience uuid; v_verification uuid; v_knowledge uuid; v_source text;
begin
  select * into r from public.memory_execution_runs where id=p_run_id;
  if not found then raise exception 'execution_run_not_found'; end if;
  if r.state='running' then raise exception 'execution_still_running'; end if;
  v_experience:=public.memory_execution_to_experience(p_run_id);
  v_source:=coalesce(nullif(btrim(p_source_ref),''),nullif(btrim(r.card_url),''),'execution-run:'||p_run_id::text);
  if length(v_source)<8 then v_source:='execution-run:'||p_run_id::text; end if;
  v_verification:=public.memory_record_verification(v_experience,v_source,p_test_key,p_result,p_evidence,p_verified_by,now());
  select linked_knowledge_id into v_knowledge from public.memory_experiences where id=v_experience;
  return jsonb_build_object('run_id',p_run_id,'experience_id',v_experience,'verification_id',v_verification,'knowledge_id',v_knowledge,'learning_status',(select learning_status from public.memory_experiences where id=v_experience));
end
$function$;

create or replace function public.memory_brain_router(
  p_request text,
  p_project_key text default null,
  p_owner_key text default 'duilio'::text
) returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_project public.memory_projects%rowtype;
  v_resume jsonb:='{}'::jsonb;
  v_graph jsonb:='{}'::jsonb;
  v_rules jsonb:='[]'::jsonb;
  v_memories jsonb:='[]'::jsonb;
  v_knowledge jsonb:='[]'::jsonb;
  v_experiences jsonb:='[]'::jsonb;
  v_executor text:='chat';
  v_reason text:='Conversación, análisis o preparación antes de ejecutar.';
  q text:=coalesce(nullif(btrim(p_request),''),'estado proyecto');
begin
  if p_project_key is not null then
    select * into v_project from public.memory_projects where owner_key=p_owner_key and project_key=p_project_key and status='active';
  else
    select * into v_project from public.memory_projects
    where owner_key=p_owner_key and status='active'
      and (lower(q) like '%'||lower(project_key)||'%' or lower(q) like '%'||lower(project_name)||'%')
    order by greatest(length(project_key),length(project_name)) desc limit 1;
  end if;

  if v_project.id is not null then v_resume:=public.memory_resume_project(v_project.project_key,p_owner_key); end if;
  select coalesce(jsonb_agg(jsonb_build_object('rule_key',r.rule_key,'statement',r.statement,'confidence',r.confidence,'provenance',r.provenance) order by r.rule_key),'[]'::jsonb)
    into v_rules from public.memory_learning_rules r where r.owner_key=p_owner_key and r.status='active';
  v_graph:=public.memory_graph_context(p_owner_key,case when v_project.id is null then null else v_project.project_key end,null,2);

  begin
    select coalesce(jsonb_agg(to_jsonb(s) order by s.relevance desc),'[]'::jsonb) into v_memories
    from public.memory_search_text(q,8,null) s;
  exception when others then v_memories:='[]'::jsonb; end;

  select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'title',k.title,'statement',k.statement,'problem_type',k.problem_type,'status',k.status,'score',k.score,'confidence',k.confidence) order by k.score desc nulls last,k.updated_at desc),'[]'::jsonb)
  into v_knowledge
  from (select * from public.memory_knowledge k where k.owner_key=p_owner_key and k.status in ('active','candidate','review') and (v_project.id is null or k.project_id=v_project.id) order by k.score desc nulls last,k.updated_at desc limit 8) k;

  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'problem_type',e.problem_type,'solution',e.solution,'outcome',e.outcome,'quality_score',e.quality_score,'learning_status',e.learning_status,'occurred_at',e.occurred_at) order by e.occurred_at desc),'[]'::jsonb)
  into v_experiences
  from (select * from public.memory_experiences e where e.owner_key=p_owner_key and (v_project.id is null or e.project_id=v_project.id) order by e.occurred_at desc limit 8) e;

  if lower(q) ~ '(cada |todos los |program|automat|monitor|webhook|cuando ocurra|cada día|cada dia|semanal|diario)' then
    v_executor:='n8n'; v_reason:='La solicitud parece recurrente, condicional o de automatización.';
  elsif lower(q) ~ '(public|deploy|despleg|github|repositorio|cloudflare|naveg|sitio|archiv|modific.*app|ejecut.*varios|multipaso)' then
    v_executor:='work'; v_reason:='La solicitud parece requerir navegación, archivos/código o ejecución multipaso; revisar primero la regla de cuota de Work.';
  else
    v_executor:='chat'; v_reason:='Puede prepararse o resolverse en Chat antes de consumir ejecución externa.';
  end if;

  return jsonb_build_object(
    'router_version','1.0',
    'request',q,
    'project',case when v_project.id is null then null else jsonb_build_object('id',v_project.id,'project_key',v_project.project_key,'project_name',v_project.project_name) end,
    'suggested_executor',v_executor,
    'routing_reason',v_reason,
    'operational_rules',v_rules,
    'graph',v_graph,
    'retrieved_memory',v_memories,
    'knowledge',v_knowledge,
    'recent_experiences',v_experiences,
    'project_context',v_resume,
    'policy',jsonb_build_object('verify_before_learning',true,'capa0_before_execution',true,'work_quota_rule_required',true)
  );
end
$function$;

create or replace function public.memory_execution_update(p_run_id uuid, p_lease_token uuid, p_state text, p_action text, p_result text default null::text, p_evidence jsonb default '[]'::jsonb, p_blockers jsonb default '[]'::jsonb, p_version text default null::text)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare r public.memory_execution_runs; v_experience uuid;
begin
 if p_state not in ('running','partial','failed','completed','blocked') or p_state is null then raise exception 'invalid state'; end if;
 if coalesce(length(trim(p_action)),0)=0 then raise exception 'action required'; end if;
 if jsonb_typeof(p_evidence)<>'array' or jsonb_typeof(p_blockers)<>'array' or p_evidence is null or p_blockers is null then raise exception 'arrays required'; end if;
 if p_state<>'running' and coalesce(length(trim(p_result)),0)=0 then raise exception 'terminal result required'; end if;
 if p_state='completed' and (jsonb_array_length(p_evidence)=0 or jsonb_array_length(p_blockers)>0) then raise exception 'completion requires evidence and no blockers'; end if;
 select * into r from public.memory_execution_runs where id=p_run_id for update;
 if not found or r.lease_token is distinct from p_lease_token or r.state<>'running' or r.lease_until<=clock_timestamp() then raise exception 'invalid or expired lease'; end if;
 update public.memory_execution_runs set
 state=p_state,last_action=p_action,result=p_result,evidence=case when jsonb_array_length(p_evidence)>0 then p_evidence else evidence end,
 blockers=p_blockers,version=coalesce(p_version,version),heartbeat_at=clock_timestamp(),
 lease_until=clock_timestamp()+interval '5 minutes',finished_at=case when p_state='running' then null else clock_timestamp() end
 where id=p_run_id returning * into r;
 if p_state<>'running' then v_experience:=public.memory_execution_to_experience(r.id); end if;
 return (to_jsonb(r)-'lease_token') || jsonb_build_object('experience_id',v_experience,'learning_requires_verification',p_state<>'running');
end
$function$;

select public.memory_sync_project_graph('duilio');

-- ============================================================================
-- 20260917004745_auto_sync_projects_to_memory_brain
-- ============================================================================
create or replace function public.memory_projects_auto_sync_graph()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  perform public.memory_sync_project_graph(coalesce(new.owner_key, old.owner_key, 'duilio'));
  return coalesce(new, old);
end
$function$;

drop trigger if exists trg_memory_projects_auto_sync_graph on public.memory_projects;
create trigger trg_memory_projects_auto_sync_graph
after insert or update of project_name, status, source_system, source_ref
on public.memory_projects
for each row
execute function public.memory_projects_auto_sync_graph();

-- ============================================================================
-- 20260917011429_phase9_execution_status_view
-- ============================================================================
create or replace view public.memory_execution_status_v as
select
  p.id as project_id,
  p.project_key,
  p.project_name,
  r.id as run_id,
  r.card_url,
  r.executor,
  case
    when r.id is null then 'idle'::text
    when r.state='running' and r.lease_until<=now() then 'inactive'::text
    else r.state
  end as observed_state,
  (r.state='running' and r.lease_until>now()) as is_running,
  r.last_action,
  r.result,
  r.blockers,
  r.evidence,
  r.version,
  r.started_at,
  r.heartbeat_at,
  r.finished_at,
  greatest(coalesce(r.heartbeat_at,'epoch'::timestamptz),coalesce(r.finished_at,'epoch'::timestamptz),coalesce(r.started_at,'epoch'::timestamptz)) as last_activity_at,
  (select count(*)::int from public.memory_execution_runs hx where hx.project_id=p.id) as history_count
from public.memory_projects p
left join lateral (
  select x.*
  from public.memory_execution_runs x
  where x.project_id=p.id
  order by x.started_at desc
  limit 1
) r on true
where p.owner_key='duilio' and p.status='active';

-- ============================================================================
-- 20260917013014_phase9_trello_memory_sync
-- ============================================================================
create or replace function public.memory_sync_trello_cards(p_cards jsonb, p_board_url text default 'https://trello.com/b/4sGARptV/memoria-duilio-proyectos-y-ejecuci%C3%B3n')
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_project_id uuid;
  v_card jsonb;
  v_subject text;
  v_url text;
  v_seen text[] := array[]::text[];
  v_inserted int := 0;
  v_updated int := 0;
  v_archived int := 0;
  v_existing uuid;
  v_list text;
  v_rank int;
begin
  if p_cards is null or jsonb_typeof(p_cards) <> 'array' then
    raise exception 'p_cards must be a json array';
  end if;

  select id into v_project_id
  from public.memory_projects
  where owner_key='duilio' and project_key='memoria-duilio' and status='active'
  limit 1;

  if v_project_id is null then
    raise exception 'active memoria-duilio project not found';
  end if;

  for v_card in select value from jsonb_array_elements(p_cards)
  loop
    v_url := nullif(trim(v_card->>'url'),'');
    if v_url is null then continue; end if;
    v_subject := 'trello_card:' || v_url;
    v_seen := array_append(v_seen, v_subject);
    v_list := coalesce(nullif(trim(v_card->>'list_name'),''),'Sin lista');
    v_rank := case v_list
      when 'Ideas' then 10
      when 'Por hacer' then 20
      when 'En ejecución' then 30
      when 'Espera de vos' then 40
      when 'En prueba' then 50
      when 'Verificado y cerrado' then 60
      else 99 end;

    select id into v_existing
    from public.memory_items
    where owner_key='duilio'
      and project_id=v_project_id
      and subject_key=v_subject
      and status='active'
    limit 1;

    if v_existing is null then
      insert into public.memory_items(
        owner_key,project_id,memory_type,category,title,content,summary,
        importance,confidence,status,fingerprint,metadata,claim_state,subject_key,
        valid_from,created_at,updated_at
      ) values (
        'duilio',v_project_id,'task','trello_card',coalesce(v_card->>'name','Tarjeta Trello'),
        coalesce(v_card->>'desc',''),v_list,
        case when v_list in ('En ejecución','Espera de vos') then 9 when v_list='Por hacer' then 8 else 6 end,
        1,'active',md5('trello|'||v_url),
        jsonb_build_object(
          'source','trello','board_url',p_board_url,'card_url',v_url,'list_name',v_list,
          'list_rank',v_rank,'last_activity_at',v_card->>'last_activity_at','due',v_card->>'due',
          'due_complete',coalesce((v_card->>'due_complete')::boolean,false),'labels',coalesce(v_card->'labels','[]'::jsonb),
          'synced_at',clock_timestamp()
        ),'recorded',v_subject,clock_timestamp(),clock_timestamp(),clock_timestamp()
      );
      v_inserted := v_inserted + 1;
    else
      update public.memory_items
      set title=coalesce(v_card->>'name',title),
          content=coalesce(v_card->>'desc',content),
          summary=v_list,
          importance=case when v_list in ('En ejecución','Espera de vos') then 9 when v_list='Por hacer' then 8 else 6 end,
          confidence=1,
          metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
            'source','trello','board_url',p_board_url,'card_url',v_url,'list_name',v_list,
            'list_rank',v_rank,'last_activity_at',v_card->>'last_activity_at','due',v_card->>'due',
            'due_complete',coalesce((v_card->>'due_complete')::boolean,false),'labels',coalesce(v_card->'labels','[]'::jsonb),
            'synced_at',clock_timestamp()
          ),
          updated_at=clock_timestamp()
      where id=v_existing;
      v_updated := v_updated + 1;
    end if;
  end loop;

  if coalesce(array_length(v_seen,1),0) > 0 then
    update public.memory_items
    set status='archived', valid_until=clock_timestamp(), updated_at=clock_timestamp(),
        metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object('archived_by_sync_at',clock_timestamp())
    where owner_key='duilio' and project_id=v_project_id and category='trello_card' and status='active'
      and metadata->>'board_url'=p_board_url
      and not (subject_key = any(v_seen));
    get diagnostics v_archived = row_count;
  end if;

  update public.memory_projects
  set last_event_at=clock_timestamp(),
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'trello_sync',jsonb_build_object('board_url',p_board_url,'last_sync_at',clock_timestamp(),'card_count',jsonb_array_length(p_cards))
      ),
      updated_at=clock_timestamp()
  where id=v_project_id;

  return jsonb_build_object('ok',true,'cards',jsonb_array_length(p_cards),'inserted',v_inserted,'updated',v_updated,'archived',v_archived,'board_url',p_board_url);
end
$function$;

create or replace view public.memory_trello_queue_v as
select
  i.id,
  i.title,
  i.summary as list_name,
  (i.metadata->>'list_rank')::int as list_rank,
  i.metadata->>'card_url' as card_url,
  i.metadata->>'last_activity_at' as trello_last_activity_at,
  i.claim_state,
  i.importance,
  i.updated_at
from public.memory_items i
join public.memory_projects p on p.id=i.project_id
where i.owner_key='duilio'
  and p.project_key='memoria-duilio'
  and i.category='trello_card'
  and i.status='active'
order by (i.metadata->>'list_rank')::int, i.updated_at desc;

-- ============================================================================
-- 20260917013656_phase9_work_execution_adapter_v2
-- ============================================================================
create table if not exists public.memory_work_sessions (
  id uuid primary key default gen_random_uuid(),
  session_key text not null unique,
  run_id uuid not null unique references public.memory_execution_runs(id) on delete cascade,
  project_key text not null,
  card_url text not null,
  state text not null default 'running' check (state in ('running','partial','failed','completed','blocked','expired')),
  last_action text,
  started_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  finished_at timestamptz
);

create index if not exists memory_work_sessions_project_state_idx
  on public.memory_work_sessions(project_key,state,updated_at desc);

create or replace function public.memory_work_adapter(
  p_action text,
  p_session_key text,
  p_project_key text default null,
  p_card_url text default null,
  p_action_text text default null,
  p_result text default null,
  p_evidence jsonb default '[]'::jsonb,
  p_blockers jsonb default '[]'::jsonb,
  p_version text default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  s public.memory_work_sessions%rowtype;
  r public.memory_execution_runs%rowtype;
  j jsonb;
  rid uuid;
  tok uuid;
  target_state text;
begin
  if p_action not in ('claim','heartbeat','complete','block','fail','partial','status') then
    raise exception 'invalid work action';
  end if;
  if coalesce(length(trim(p_session_key)),0)=0 then raise exception 'session_key required'; end if;
  if jsonb_typeof(coalesce(p_evidence,'[]'::jsonb)) <> 'array' then raise exception 'evidence must be array'; end if;
  if jsonb_typeof(coalesce(p_blockers,'[]'::jsonb)) <> 'array' then raise exception 'blockers must be array'; end if;

  if p_action='claim' then
    if coalesce(length(trim(p_project_key)),0)=0 then raise exception 'project_key required'; end if;
    if coalesce(length(trim(p_card_url)),0)=0 then raise exception 'card_url required'; end if;
    if coalesce(length(trim(p_action_text)),0)=0 then raise exception 'action_text required'; end if;

    select * into s from public.memory_work_sessions where session_key=p_session_key;
    if found then
      select * into r from public.memory_execution_runs where id=s.run_id;
      return jsonb_build_object('ok',true,'action','claim','duplicate',true,'session_key',s.session_key,'run_id',s.run_id,'state',r.state,'lease_until',r.lease_until,'executor','Work');
    end if;

    j := public.memory_execution_claim(
      p_project_key,
      p_card_url,
      'work:'||p_session_key,
      'Work',
      p_action_text,
      coalesce(p_evidence,'[]'::jsonb)
    );
    if coalesce((j->>'claimed')::boolean,false)=false then
      return j || jsonb_build_object('ok',false,'action','claim','session_key',p_session_key,'executor','Work');
    end if;
    rid := (j->>'run_id')::uuid;
    insert into public.memory_work_sessions(session_key,run_id,project_key,card_url,last_action)
    values(p_session_key,rid,p_project_key,p_card_url,p_action_text)
    on conflict(session_key) do nothing;
    return (j - 'lease_token') || jsonb_build_object('ok',true,'action','claim','session_key',p_session_key,'executor','Work');
  end if;

  select * into s from public.memory_work_sessions where session_key=p_session_key for update;
  if not found then raise exception 'unknown work session'; end if;
  select * into r from public.memory_execution_runs where id=s.run_id;
  tok := r.lease_token;

  if p_action='status' then
    return jsonb_build_object(
      'ok',true,'action','status','session_key',p_session_key,'run_id',r.id,'project_key',s.project_key,
      'card_url',s.card_url,'state',r.state,'last_action',r.last_action,'result',r.result,'blockers',r.blockers,
      'evidence',r.evidence,'version',r.version,'heartbeat_at',r.heartbeat_at,'lease_until',r.lease_until,'finished_at',r.finished_at,'executor','Work'
    );
  end if;

  if coalesce(length(trim(p_action_text)),0)=0 then raise exception 'action_text required'; end if;
  target_state := case p_action when 'heartbeat' then 'running' when 'complete' then 'completed' when 'block' then 'blocked' when 'fail' then 'failed' when 'partial' then 'partial' end;

  j := public.memory_execution_update(
    s.run_id,
    tok,
    target_state,
    p_action_text,
    p_result,
    coalesce(p_evidence,'[]'::jsonb),
    coalesce(p_blockers,'[]'::jsonb),
    p_version
  );

  update public.memory_work_sessions
  set state=target_state,last_action=p_action_text,updated_at=clock_timestamp(),
      finished_at=case when target_state='running' then null else clock_timestamp() end
  where id=s.id;

  return (j - 'lease_token') || jsonb_build_object('ok',true,'action',p_action,'session_key',p_session_key,'executor','Work');
end
$function$;

revoke all on function public.memory_work_adapter(text,text,text,text,text,text,jsonb,jsonb,text) from public;
grant execute on function public.memory_work_adapter(text,text,text,text,text,text,jsonb,jsonb,text) to service_role;

create or replace view public.memory_work_sessions_v as
select ws.session_key,ws.project_key,ws.card_url,ws.state,ws.last_action,ws.started_at,ws.updated_at,ws.finished_at,
       r.executor,r.result,r.blockers,r.evidence,r.version,r.heartbeat_at,r.lease_until,
       case when r.state='running' and r.lease_until<=clock_timestamp() then 'inactive' else r.state end as observed_state
from public.memory_work_sessions ws
join public.memory_execution_runs r on r.id=ws.run_id;

-- ============================================================================
-- 20260917013919_phase9_work_adapter_integrity
-- ============================================================================
create or replace function public.memory_trello_canonical_url(p_url text)
returns text
language sql
immutable
set search_path to ''
as $function$
  select case
    when p_url ~ '^https://trello[.]com/c/[A-Za-z0-9]+' then substring(p_url from '^(https://trello[.]com/c/[A-Za-z0-9]+)')
    else p_url
  end
$function$;

create or replace function public.memory_work_adapter(
  p_action text,
  p_session_key text,
  p_project_key text default null,
  p_card_url text default null,
  p_action_text text default null,
  p_result text default null,
  p_evidence jsonb default '[]'::jsonb,
  p_blockers jsonb default '[]'::jsonb,
  p_version text default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  s public.memory_work_sessions%rowtype;
  r public.memory_execution_runs%rowtype;
  j jsonb;
  rid uuid;
  tok uuid;
  target_state text;
  v_card_url text;
begin
  if p_action not in ('claim','heartbeat','complete','block','fail','partial','status') then raise exception 'invalid work action'; end if;
  if coalesce(length(trim(p_session_key)),0)=0 then raise exception 'session_key required'; end if;
  if jsonb_typeof(coalesce(p_evidence,'[]'::jsonb)) <> 'array' then raise exception 'evidence must be array'; end if;
  if jsonb_typeof(coalesce(p_blockers,'[]'::jsonb)) <> 'array' then raise exception 'blockers must be array'; end if;

  if p_action='claim' then
    if coalesce(length(trim(p_project_key)),0)=0 then raise exception 'project_key required'; end if;
    if coalesce(length(trim(p_card_url)),0)=0 then raise exception 'card_url required'; end if;
    if coalesce(length(trim(p_action_text)),0)=0 then raise exception 'action_text required'; end if;
    v_card_url := public.memory_trello_canonical_url(p_card_url);

    select * into s from public.memory_work_sessions where session_key=p_session_key;
    if found then
      select * into r from public.memory_execution_runs where id=s.run_id;
      return jsonb_build_object('ok',true,'action','claim','duplicate',true,'session_key',s.session_key,'run_id',s.run_id,'state',r.state,'lease_until',r.lease_until,'executor','Work');
    end if;

    j := public.memory_execution_claim(p_project_key,v_card_url,'work:'||p_session_key,'Work',p_action_text,coalesce(p_evidence,'[]'::jsonb));
    if coalesce((j->>'claimed')::boolean,false)=false then
      return j || jsonb_build_object('ok',false,'action','claim','session_key',p_session_key,'executor','Work');
    end if;
    rid := (j->>'run_id')::uuid;
    insert into public.memory_work_sessions(session_key,run_id,project_key,card_url,last_action)
    values(p_session_key,rid,p_project_key,v_card_url,p_action_text)
    on conflict(session_key) do nothing;
    return (j - 'lease_token') || jsonb_build_object('ok',true,'action','claim','session_key',p_session_key,'executor','Work');
  end if;

  select * into s from public.memory_work_sessions where session_key=p_session_key for update;
  if not found then raise exception 'unknown work session'; end if;
  select * into r from public.memory_execution_runs where id=s.run_id;
  tok := r.lease_token;

  if p_action='status' then
    return jsonb_build_object('ok',true,'action','status','session_key',p_session_key,'run_id',r.id,'project_key',s.project_key,'card_url',s.card_url,'state',r.state,'last_action',r.last_action,'result',r.result,'blockers',r.blockers,'evidence',r.evidence,'version',r.version,'heartbeat_at',r.heartbeat_at,'lease_until',r.lease_until,'finished_at',r.finished_at,'executor','Work');
  end if;

  if coalesce(length(trim(p_action_text)),0)=0 then raise exception 'action_text required'; end if;
  target_state := case p_action when 'heartbeat' then 'running' when 'complete' then 'completed' when 'block' then 'blocked' when 'fail' then 'failed' when 'partial' then 'partial' end;
  j := public.memory_execution_update(s.run_id,tok,target_state,p_action_text,p_result,coalesce(p_evidence,'[]'::jsonb),coalesce(p_blockers,'[]'::jsonb),p_version);
  update public.memory_work_sessions set state=target_state,last_action=p_action_text,updated_at=clock_timestamp(),finished_at=case when target_state='running' then null else clock_timestamp() end where id=s.id;
  return (j - 'lease_token') || jsonb_build_object('ok',true,'action',p_action,'session_key',p_session_key,'executor','Work');
end
$function$;

revoke all on function public.memory_work_adapter(text,text,text,text,text,text,jsonb,jsonb,text) from public;
grant execute on function public.memory_work_adapter(text,text,text,text,text,text,jsonb,jsonb,text) to service_role;

create or replace view public.memory_execution_integrity_v as
with q as (
  select t.id,t.title,t.list_name,t.list_rank,t.card_url,
         public.memory_trello_canonical_url(t.card_url) canonical_card_url,
         t.updated_at trello_synced_at
  from public.memory_trello_queue_v t
), latest as (
  select distinct on (r.card_url)
         r.card_url,r.id run_id,r.executor,r.state,r.last_action,r.result,r.blockers,r.evidence,r.version,r.heartbeat_at,r.lease_until,r.finished_at,r.started_at
  from public.memory_execution_runs r
  order by r.card_url,r.started_at desc
)
select q.id,q.title,q.list_name,q.list_rank,q.card_url,q.canonical_card_url,q.trello_synced_at,
       l.run_id,l.executor,l.state,l.last_action,l.result,l.blockers,l.evidence,l.version,l.heartbeat_at,l.lease_until,l.finished_at,
       case
         when q.list_name <> 'En ejecución' then 'not_running_column'
         when l.run_id is null then 'missing_execution'
         when l.state='running' and l.lease_until>clock_timestamp() and jsonb_array_length(l.evidence)>0 then 'verified_running'
         when l.state='running' and l.lease_until<=clock_timestamp() then 'stale_execution'
         when l.state in ('completed','partial','failed','blocked','expired') then 'no_active_executor'
         else 'unverified_execution'
       end as integrity_state
from q left join latest l on l.card_url=q.canonical_card_url;

-- ============================================================================
-- 20260917021232_memory_duilio_dashboard_access
-- ============================================================================
create table if not exists public.memory_dashboard_access (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  label text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  expires_at timestamptz
);

alter table public.memory_dashboard_access enable row level security;
revoke all on public.memory_dashboard_access from anon, authenticated;

grant select, insert, update, delete on public.memory_dashboard_access to service_role;

create index if not exists memory_dashboard_access_active_idx
  on public.memory_dashboard_access(active, expires_at);

-- ============================================================================
-- 20260917021929_memory_dashboard_payload_v1
-- ============================================================================
create or replace function public.memory_dashboard_payload()
returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
with phase as (
  select to_jsonb(p) as j
  from public.memory_phase_progress p
  where p.project_key='memoria-duilio' and p.phase=9
  order by p.updated_at desc
  limit 1
), cards as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'title',i.title,
    'list_name',i.list_name,
    'card_url',i.card_url,
    'integrity_state',i.integrity_state,
    'executor',i.executor,
    'state',i.state,
    'last_action',i.last_action,
    'result',i.result,
    'blockers',coalesce(i.blockers,'[]'::jsonb),
    'version',i.version,
    'heartbeat_at',i.heartbeat_at,
    'lease_until',i.lease_until,
    'finished_at',i.finished_at
  ) order by i.list_rank, i.title),'[]'::jsonb) as j
  from public.memory_execution_integrity_v i
  where i.list_name in ('En ejecución','Espera de vos','En prueba')
), runs as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'project_key',s.project_key,
    'project_name',s.project_name,
    'executor',s.executor,
    'observed_state',s.observed_state,
    'is_running',s.is_running,
    'last_action',s.last_action,
    'result',s.result,
    'blockers',coalesce(s.blockers,'[]'::jsonb),
    'version',s.version,
    'last_activity_at',s.last_activity_at,
    'card_url',s.card_url
  ) order by s.last_activity_at desc nulls last),'[]'::jsonb) as j
  from public.memory_execution_status_v s
), counts as (
  select jsonb_build_object(
    'trello_open',(select count(*) from public.memory_trello_queue_v),
    'trello_in_execution',(select count(*) from public.memory_execution_integrity_v where list_name='En ejecución'),
    'verified_running',(select count(*) from public.memory_execution_integrity_v where list_name='En ejecución' and integrity_state='verified_running'),
    'missing_execution',(select count(*) from public.memory_execution_integrity_v where list_name='En ejecución' and integrity_state<>'verified_running')
  ) as j
)
select jsonb_build_object(
  'generated_at',clock_timestamp(),
  'phase9',coalesce((select j from phase),'{}'::jsonb),
  'counts',(select j from counts),
  'cards',(select j from cards),
  'runs',(select j from runs)
);
$function$;
revoke all on function public.memory_dashboard_payload() from public, anon, authenticated;
grant execute on function public.memory_dashboard_payload() to service_role;

-- ============================================================================
-- 20260919041849_memory_multi_ai_orchestrator_v1_1
-- ============================================================================
create table if not exists public.memory_executor_registry (
  executor_key text primary key,
  display_name text not null,
  executor_type text not null,
  status text not null default 'pending_connection'
    check (status in ('ready','pending_connection','disabled','error')),
  enabled boolean not null default true,
  automatic boolean not null default false,
  capabilities text[] not null default '{}'::text[],
  cost_class smallint not null default 3 check (cost_class between 1 and 5),
  quality_class smallint not null default 3 check (quality_class between 1 and 5),
  latency_class smallint not null default 3 check (latency_class between 1 and 5),
  max_concurrency integer not null default 1 check (max_concurrency >= 1),
  metadata jsonb not null default '{}'::jsonb,
  last_health_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.memory_executor_registry enable row level security;

create table if not exists public.memory_orchestrator_decisions (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  project_id uuid references public.memory_projects(id) on delete set null,
  request_text text not null,
  task_type text not null,
  selected_executor text references public.memory_executor_registry(executor_key),
  routing_reason text not null,
  candidates jsonb not null default '[]'::jsonb,
  constraints jsonb not null default '{}'::jsonb,
  status text not null default 'selected'
    check (status in ('selected','queued','dispatched','completed','cancelled','failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.memory_orchestrator_decisions enable row level security;
create index if not exists memory_orchestrator_decisions_project_idx
  on public.memory_orchestrator_decisions(project_id, created_at desc);

create table if not exists public.memory_execution_queue (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid not null references public.memory_orchestrator_decisions(id) on delete cascade,
  project_id uuid references public.memory_projects(id) on delete set null,
  card_url text,
  executor_key text not null references public.memory_executor_registry(executor_key),
  task_type text not null,
  task_text text not null,
  priority smallint not null default 50 check (priority between 0 and 100),
  state text not null default 'pending'
    check (state in ('pending','needs_adapter','ready','claimed','running','blocked','completed','failed','cancelled')),
  dispatch_after timestamptz not null default now(),
  claimed_by text,
  claimed_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  result jsonb,
  evidence jsonb not null default '[]'::jsonb,
  blockers jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.memory_execution_queue enable row level security;
create index if not exists memory_execution_queue_pick_idx
  on public.memory_execution_queue(state, priority desc, dispatch_after, created_at);

insert into public.memory_executor_registry
(executor_key,display_name,executor_type,status,enabled,automatic,capabilities,cost_class,quality_class,latency_class,max_concurrency,metadata,last_health_at)
values
('chatgpt-chat','ChatGPT','llm','ready',true,false,
 array['conversation','analysis','sql','planning','writing','light_code'],1,4,1,1,
 '{"dispatch_mode":"conversation","native_dispatch":false,"notes":"Ideal para preparar, analizar y resolver tareas cortas sin consumir Work."}'::jsonb,now()),
('chatgpt-work','ChatGPT Work','agent','ready',true,false,
 array['code','repository','files','browser','multi_step','deployment','long_task'],4,5,4,1,
 '{"dispatch_mode":"work_adapter","native_dispatch":false,"adapter":"memory_work_adapter","notes":"El adaptador existe; falta un hook nativo para iniciar Work automáticamente."}'::jsonb,now()),
('n8n','n8n','automation','ready',true,true,
 array['automation','recurring','webhook','integration','scheduled','api'],1,3,2,5,
 '{"dispatch_mode":"workflow","native_dispatch":true,"connector":"Memoria Duilio n8n API"}'::jsonb,now()),
('claude-code','Claude Code','code_agent','pending_connection',true,false,
 array['code','repository','tests','refactor','debug','git'],2,5,3,2,
 '{"dispatch_mode":"external_adapter","native_dispatch":false,"requires":"Claude Code instalado y autenticado en PC/servidor/runner"}'::jsonb,null)
on conflict (executor_key) do update set
  display_name=excluded.display_name,
  executor_type=excluded.executor_type,
  capabilities=excluded.capabilities,
  cost_class=excluded.cost_class,
  quality_class=excluded.quality_class,
  latency_class=excluded.latency_class,
  max_concurrency=excluded.max_concurrency,
  metadata=public.memory_executor_registry.metadata || excluded.metadata,
  updated_at=now();

create or replace function public.memory_classify_task(p_request text)
returns text
language plpgsql
immutable
set search_path to ''
as $$
declare q text := lower(coalesce(p_request,''));
begin
  if q ~ '(cada |todos los |program|automat|monitor|webhook|cuando ocurra|diario|semanal|mensual|cron|scheduler)' then
    return 'automation';
  elsif q ~ '(repo|repositorio|github|codigo|código|program|bug|error|test|prueba|refactor|commit|pull request|deploy|despleg|archivo|react|vite|sql.*funcion|sql.*función)' then
    return 'code';
  elsif q ~ '(investig|buscar|comparar|document|informe|analiz)' then
    return 'research';
  elsif q ~ '(muchos pasos|multipaso|proyecto completo|ejecut.*todo|hacer todo|hacelo todo)' then
    return 'multi_step';
  else
    return 'conversation';
  end if;
end
$$;

create or replace function public.memory_select_executor_v2(
  p_request text,
  p_project_key text default null,
  p_prefer_executor text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_task text;
  v_candidates jsonb;
  v_selected text;
  v_reason text;
begin
  if coalesce(length(trim(p_request)),0)=0 then raise exception 'request required'; end if;
  v_task := public.memory_classify_task(p_request);

  with scored as (
    select
      e.executor_key,
      e.display_name,
      e.status,
      e.automatic,
      e.cost_class,
      e.quality_class,
      e.latency_class,
      e.metadata,
      (
        case
          when p_prefer_executor is not null and e.executor_key=p_prefer_executor then 120
          when v_task='automation' and 'automation'=any(e.capabilities) then 100
          when v_task='code' and e.executor_key='claude-code' and e.status='ready' then 108
          when v_task='code' and e.executor_key='chatgpt-work' then 92
          when v_task='code' and e.executor_key='chatgpt-chat' then 55
          when v_task='research' and e.executor_key='chatgpt-chat' then 92
          when v_task='research' and e.executor_key='chatgpt-work' then 78
          when v_task='multi_step' and e.executor_key='chatgpt-work' then 98
          when v_task='multi_step' and e.executor_key='n8n' then 72
          when v_task='conversation' and e.executor_key='chatgpt-chat' then 100
          else 20
        end
        + (e.quality_class * 2)
        - (e.cost_class * 3)
        - (e.latency_class)
      )::int as score
    from public.memory_executor_registry e
    where e.enabled=true and e.status='ready'
  ), ranked as (
    select * from scored order by score desc, cost_class asc, executor_key
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'executor_key',executor_key,
      'display_name',display_name,
      'status',status,
      'automatic',automatic,
      'score',score,
      'cost_class',cost_class,
      'quality_class',quality_class,
      'latency_class',latency_class,
      'dispatch_mode',metadata->>'dispatch_mode'
    ) order by score desc, cost_class asc, executor_key),'[]'::jsonb),
    (array_agg(executor_key order by score desc, cost_class asc, executor_key))[1]
  into v_candidates, v_selected
  from ranked;

  if v_selected is null then
    raise exception 'no ready executor available';
  end if;

  v_reason := case
    when v_task='automation' then 'Automatización/repetición detectada; priorizar un ejecutor automático.'
    when v_task='code' and v_selected='claude-code' then 'Tarea de código/repositorio; Claude Code está conectado y disponible.'
    when v_task='code' then 'Tarea de código/repositorio; Claude Code aún no está conectado, se usa el mejor fallback disponible.'
    when v_task='multi_step' then 'Trabajo largo o multipaso; se prioriza un agente con ejecución prolongada.'
    when v_task='research' then 'Investigación/análisis; se prioriza resolver en Chat antes de gastar ejecución pesada.'
    else 'Tarea conversacional o corta; se prioriza Chat por costo y latencia.'
  end;

  return jsonb_build_object(
    'router_version','2.0',
    'project_key',p_project_key,
    'task_type',v_task,
    'selected_executor',v_selected,
    'routing_reason',v_reason,
    'candidates',v_candidates,
    'claude_code_status',(select status from public.memory_executor_registry where executor_key='claude-code')
  );
end
$$;

create or replace function public.memory_orchestrate_request(
  p_request text,
  p_project_key text default null,
  p_card_url text default null,
  p_prefer_executor text default null,
  p_priority smallint default 50
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_project public.memory_projects%rowtype;
  v_route jsonb;
  v_decision public.memory_orchestrator_decisions%rowtype;
  v_queue public.memory_execution_queue%rowtype;
  v_executor public.memory_executor_registry%rowtype;
  v_state text;
begin
  if coalesce(length(trim(p_request)),0)=0 then raise exception 'request required'; end if;
  if p_priority < 0 or p_priority > 100 then raise exception 'priority out of range'; end if;

  if p_project_key is not null then
    select * into v_project from public.memory_projects
    where owner_key='duilio' and project_key=p_project_key and status='active' limit 1;
  else
    select * into v_project
    from public.memory_projects
    where owner_key='duilio' and status='active'
      and (
        lower(p_request) like '%'||lower(project_key)||'%'
        or lower(p_request) like '%'||lower(project_name)||'%'
      )
    order by greatest(length(project_key),length(project_name)) desc
    limit 1;
  end if;

  v_route := public.memory_select_executor_v2(p_request,
    case when v_project.id is null then p_project_key else v_project.project_key end,
    p_prefer_executor);

  select * into v_executor
  from public.memory_executor_registry
  where executor_key=v_route->>'selected_executor';

  insert into public.memory_orchestrator_decisions(
    project_id,request_text,task_type,selected_executor,routing_reason,candidates,constraints,status
  ) values (
    v_project.id,p_request,v_route->>'task_type',v_route->>'selected_executor',
    v_route->>'routing_reason',coalesce(v_route->'candidates','[]'::jsonb),
    jsonb_build_object('priority',p_priority,'card_url',p_card_url),'queued'
  ) returning * into v_decision;

  v_state := case
    when v_executor.automatic and coalesce((v_executor.metadata->>'native_dispatch')::boolean,false) then 'ready'
    else 'needs_adapter'
  end;

  insert into public.memory_execution_queue(
    decision_id,project_id,card_url,executor_key,task_type,task_text,priority,state,metadata
  ) values (
    v_decision.id,v_project.id,p_card_url,v_executor.executor_key,v_route->>'task_type',
    p_request,p_priority,v_state,
    jsonb_build_object(
      'routing_reason',v_route->>'routing_reason',
      'dispatch_mode',v_executor.metadata->>'dispatch_mode',
      'automatic',v_executor.automatic
    )
  ) returning * into v_queue;

  return jsonb_build_object(
    'ok',true,
    'decision_id',v_decision.id,
    'queue_id',v_queue.id,
    'queue_state',v_queue.state,
    'project',case when v_project.id is null then null else jsonb_build_object('project_key',v_project.project_key,'project_name',v_project.project_name) end,
    'route',v_route
  );
end
$$;

create or replace view public.memory_orchestrator_status_v as
select
  e.executor_key,
  e.display_name,
  e.status,
  e.enabled,
  e.automatic,
  e.capabilities,
  e.cost_class,
  e.quality_class,
  e.latency_class,
  e.metadata,
  e.last_health_at,
  count(q.id) filter (where q.state in ('pending','needs_adapter','ready','claimed','running','blocked')) as open_jobs,
  count(q.id) filter (where q.state='running') as running_jobs
from public.memory_executor_registry e
left join public.memory_execution_queue q on q.executor_key=e.executor_key
group by e.executor_key,e.display_name,e.status,e.enabled,e.automatic,e.capabilities,
         e.cost_class,e.quality_class,e.latency_class,e.metadata,e.last_health_at;

create or replace function public.memory_orchestrator_payload()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
select jsonb_build_object(
  'generated_at',clock_timestamp(),
  'executors',coalesce((select jsonb_agg(to_jsonb(x) order by x.executor_key)
    from public.memory_orchestrator_status_v x),'[]'::jsonb),
  'queue',coalesce((select jsonb_agg(to_jsonb(q) order by q.priority desc,q.created_at)
    from (
      select q.id,q.executor_key,q.task_type,q.task_text,q.priority,q.state,q.card_url,
             q.created_at,q.started_at,q.finished_at,q.blockers,
             p.project_key,p.project_name
      from public.memory_execution_queue q
      left join public.memory_projects p on p.id=q.project_id
      where q.state not in ('completed','cancelled')
      order by q.priority desc,q.created_at
      limit 50
    ) q),'[]'::jsonb),
  'recent_decisions',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc)
    from (
      select d.id,d.request_text,d.task_type,d.selected_executor,d.routing_reason,
             d.status,d.created_at,p.project_key
      from public.memory_orchestrator_decisions d
      left join public.memory_projects p on p.id=d.project_id
      order by d.created_at desc
      limit 30
    ) d),'[]'::jsonb)
);
$$;

insert into public.memory_project_connectors(
  project_id,connector_type,connector_name,status,automatic,metadata
)
select p.id,'multi-ai-orchestrator','Memoria Duilio Orquestador v1','connected',true,
       '{"router":"memory_select_executor_v2","queue":"memory_execution_queue","payload":"memory_orchestrator_payload"}'::jsonb
from public.memory_projects p
where p.owner_key='duilio' and p.project_key='memoria-duilio' and p.status='active'
  and not exists (
    select 1 from public.memory_project_connectors c
    where c.project_id=p.id and c.connector_type='multi-ai-orchestrator'
  );

insert into public.memory_project_connectors(
  project_id,connector_type,connector_name,status,automatic,metadata
)
select p.id,'claude-code','Claude Code','pending',false,
       '{"executor_key":"claude-code","connection_state":"pending","requires":"instalación + autenticación + runner/adaptador"}'::jsonb
from public.memory_projects p
where p.owner_key='duilio' and p.project_key='memoria-duilio' and p.status='active'
  and not exists (
    select 1 from public.memory_project_connectors c
    where c.project_id=p.id and c.connector_type='claude-code'
  );

-- ============================================================================
-- 20260919041917_memory_multi_ai_worker_protocol_v1
-- ============================================================================
create or replace function public.memory_executor_heartbeat(
  p_executor_key text,
  p_status text default 'ready',
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare e public.memory_executor_registry%rowtype;
begin
  if p_status not in ('ready','pending_connection','disabled','error') then
    raise exception 'invalid executor status';
  end if;
  update public.memory_executor_registry
  set status=p_status,
      last_health_at=clock_timestamp(),
      metadata=coalesce(metadata,'{}'::jsonb) || coalesce(p_metadata,'{}'::jsonb),
      updated_at=clock_timestamp()
  where executor_key=p_executor_key
  returning * into e;
  if not found then raise exception 'unknown executor'; end if;

  if p_status='ready' then
    update public.memory_execution_queue
    set state='ready',updated_at=clock_timestamp()
    where executor_key=p_executor_key and state='needs_adapter';
  end if;

  return jsonb_build_object(
    'ok',true,'executor_key',e.executor_key,'status',e.status,
    'last_health_at',e.last_health_at,
    'released_jobs',(select count(*) from public.memory_execution_queue q
      where q.executor_key=p_executor_key and q.state='ready')
  );
end
$$;

create or replace function public.memory_queue_claim(
  p_executor_key text,
  p_worker_id text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  e public.memory_executor_registry%rowtype;
  q public.memory_execution_queue%rowtype;
begin
  if coalesce(length(trim(p_worker_id)),0)=0 then raise exception 'worker_id required'; end if;
  select * into e from public.memory_executor_registry
    where executor_key=p_executor_key and enabled=true and status='ready';
  if not found then
    return jsonb_build_object('ok',false,'reason','executor_not_ready','executor_key',p_executor_key);
  end if;

  select * into q
  from public.memory_execution_queue
  where executor_key=p_executor_key
    and state in ('ready','needs_adapter','pending')
    and dispatch_after<=clock_timestamp()
  order by priority desc,created_at
  for update skip locked
  limit 1;

  if not found then
    return jsonb_build_object('ok',true,'claimed',false,'reason','no_job');
  end if;

  update public.memory_execution_queue
  set state='claimed',claimed_by=p_worker_id,claimed_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=q.id
  returning * into q;

  update public.memory_orchestrator_decisions set status='dispatched',updated_at=clock_timestamp()
  where id=q.decision_id and status='queued';

  return jsonb_build_object(
    'ok',true,'claimed',true,
    'job',jsonb_build_object(
      'id',q.id,'decision_id',q.decision_id,'project_id',q.project_id,
      'card_url',q.card_url,'executor_key',q.executor_key,'task_type',q.task_type,
      'task_text',q.task_text,'priority',q.priority,'metadata',q.metadata
    )
  );
end
$$;

create or replace function public.memory_queue_update(
  p_queue_id uuid,
  p_worker_id text,
  p_state text,
  p_result jsonb default null,
  p_evidence jsonb default '[]'::jsonb,
  p_blockers jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare q public.memory_execution_queue%rowtype;
begin
  if p_state not in ('running','blocked','completed','failed') then
    raise exception 'invalid queue state';
  end if;
  if jsonb_typeof(coalesce(p_evidence,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_blockers,'[]'::jsonb))<>'array' then
    raise exception 'evidence and blockers must be arrays';
  end if;

  select * into q from public.memory_execution_queue where id=p_queue_id for update;
  if not found then raise exception 'unknown queue job'; end if;
  if q.claimed_by is distinct from p_worker_id then raise exception 'worker mismatch'; end if;
  if q.state not in ('claimed','running','blocked') then raise exception 'job is not active'; end if;

  update public.memory_execution_queue
  set state=p_state,
      started_at=case when p_state='running' then coalesce(started_at,clock_timestamp()) else started_at end,
      finished_at=case when p_state in ('completed','failed') then clock_timestamp() else null end,
      result=coalesce(p_result,result),
      evidence=case when jsonb_array_length(coalesce(p_evidence,'[]'::jsonb))>0 then p_evidence else evidence end,
      blockers=coalesce(p_blockers,'[]'::jsonb),
      updated_at=clock_timestamp()
  where id=p_queue_id returning * into q;

  if p_state='completed' and jsonb_array_length(q.evidence)=0 then
    raise exception 'completion requires evidence';
  end if;

  if p_state in ('completed','failed') then
    update public.memory_orchestrator_decisions
      set status=case when p_state='completed' then 'completed' else 'failed' end,
          updated_at=clock_timestamp()
      where id=q.decision_id;
  end if;

  return jsonb_build_object(
    'ok',true,'queue_id',q.id,'state',q.state,'result',q.result,
    'evidence',q.evidence,'blockers',q.blockers,'finished_at',q.finished_at
  );
end
$$;

-- ============================================================================
-- 20260919041952_memory_multi_ai_router_classification_fix_v1
-- ============================================================================
create or replace function public.memory_classify_task(p_request text)
returns text
language plpgsql
immutable
set search_path to ''
as $$
declare q text := lower(coalesce(p_request,''));
begin
  if q ~ '(repo|repositorio|github|c[oó]digo|programaci[oó]n|bug|error|tests?|pruebas?|refactor|commit|pull request|deploy|despleg|archivo|react|vite|funci[oó]n sql)' then
    return 'code';
  elsif q ~ '(cada |todos los |automat|monitor|webhook|cuando ocurra|diario|semanal|mensual|cron|scheduler|programad[oa])' then
    return 'automation';
  elsif q ~ '(muchos pasos|multipaso|proyecto completo|ejecut.*todo|hacer todo|hacelo todo)' then
    return 'multi_step';
  elsif q ~ '(investig|buscar|comparar|document|informe|analiz)' then
    return 'research';
  else
    return 'conversation';
  end if;
end
$$;

-- ============================================================================
-- 20260919042204_memory_multi_ai_security_lockdown_v1
-- ============================================================================
alter view public.memory_orchestrator_status_v set (security_invoker = true);
revoke all on public.memory_orchestrator_status_v from anon, authenticated;
grant select on public.memory_orchestrator_status_v to service_role;

revoke execute on function public.memory_select_executor_v2(text,text,text) from public, anon, authenticated;
revoke execute on function public.memory_orchestrate_request(text,text,text,text,smallint) from public, anon, authenticated;
revoke execute on function public.memory_orchestrator_payload() from public, anon, authenticated;
revoke execute on function public.memory_executor_heartbeat(text,text,jsonb) from public, anon, authenticated;
revoke execute on function public.memory_queue_claim(text,text) from public, anon, authenticated;
revoke execute on function public.memory_queue_update(uuid,text,text,jsonb,jsonb,jsonb) from public, anon, authenticated;

grant execute on function public.memory_select_executor_v2(text,text,text) to service_role;
grant execute on function public.memory_orchestrate_request(text,text,text,text,smallint) to service_role;
grant execute on function public.memory_orchestrator_payload() to service_role;
grant execute on function public.memory_executor_heartbeat(text,text,jsonb) to service_role;
grant execute on function public.memory_queue_claim(text,text) to service_role;
grant execute on function public.memory_queue_update(uuid,text,text,jsonb,jsonb,jsonb) to service_role;

-- ============================================================================
-- 20260919045402_memory_security_hardening_work_adapter_v1
-- ============================================================================
-- 1) Cerrar RPC backend-only que todavía estaban expuestas.
revoke execute on function public.memory_work_adapter(text,text,text,text,text,text,jsonb,jsonb,text)
  from public, anon, authenticated;
revoke execute on function public.memory_sync_trello_cards(jsonb,text)
  from public, anon, authenticated;
grant execute on function public.memory_work_adapter(text,text,text,text,text,text,jsonb,jsonb,text)
  to service_role;
grant execute on function public.memory_sync_trello_cards(jsonb,text)
  to service_role;

-- 2) Proteger tabla de sesiones Work.
alter table public.memory_work_sessions enable row level security;
revoke all on table public.memory_work_sessions from anon, authenticated;
grant select,insert,update,delete on table public.memory_work_sessions to service_role;

-- 3) Las vistas operativas no deben bypassear RLS ni quedar expuestas al cliente.
alter view public.memory_work_sessions_v set (security_invoker = true);
alter view public.memory_execution_status_v set (security_invoker = true);
alter view public.memory_trello_queue_v set (security_invoker = true);
alter view public.memory_execution_integrity_v set (security_invoker = true);

revoke all on table public.memory_work_sessions_v from anon, authenticated;
revoke all on table public.memory_execution_status_v from anon, authenticated;
revoke all on table public.memory_trello_queue_v from anon, authenticated;
revoke all on table public.memory_execution_integrity_v from anon, authenticated;

grant select on table public.memory_work_sessions_v to service_role;
grant select on table public.memory_execution_status_v to service_role;
grant select on table public.memory_trello_queue_v to service_role;
grant select on table public.memory_execution_integrity_v to service_role;

-- ============================================================================
-- 20260919052425_memory_operating_model_and_home_v1
-- ============================================================================
create table if not exists public.memory_source_of_truth (
  system_key text primary key,
  display_name text not null,
  primary_role text not null,
  authoritative_for text[] not null default '{}',
  write_policy text not null,
  read_priority smallint not null default 50,
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default clock_timestamp()
);

alter table public.memory_source_of_truth enable row level security;
revoke all on table public.memory_source_of_truth from public, anon, authenticated;
grant select,insert,update,delete on table public.memory_source_of_truth to service_role;

insert into public.memory_source_of_truth
(system_key,display_name,primary_role,authoritative_for,write_policy,read_priority,metadata)
values
('memoria-duilio','Memoria Duilio','cerebro y orquestador',
 array['intencion','contexto','routing','navegacion','referencias'],
 'Coordina y referencia. No duplica como verdad primaria los estados de otras herramientas.',10,
 '{"rule":"orchestrate_not_duplicate"}'::jsonb),
('trello','Trello','estado operativo',
 array['estado_tarea','proxima_accion','columna','bloqueo_operativo'],
 'Toda transición operativa de tarea se escribe y verifica en Trello.',20,
 '{"board":"Memoria Duilio — Proyectos y ejecución"}'::jsonb),
('supabase','Supabase','verdad técnica',
 array['ejecucion_real','heartbeat','lease','memoria_estructurada','grafo','auditoria','routing'],
 'Registra hechos técnicos verificables y evidencia; no reemplaza el estado operativo de Trello.',15,
 '{}'::jsonb),
('github','GitHub','código y versiones',
 array['codigo','commit','rama','pull_request','release','artefacto_versionado'],
 'Toda versión de código recuperable debe apuntar a commit/PR/release verificable.',30,
 '{}'::jsonb),
('notion','Notion','documentación larga e histórica',
 array['documentacion','especificacion','historial_narrativo','manual'],
 'Documenta; no gobierna si una tarea está ejecutándose o cerrada.',40,
 '{}'::jsonb),
('n8n','n8n','automatización',
 array['workflow','webhook','cron','integracion_automatica'],
 'Ejecuta automatizaciones e informa resultado a Supabase/Trello según corresponda.',25,
 '{}'::jsonb),
('whatsapp','WhatsApp','avisos y canal rápido',
 array['notificacion','aviso','interaccion_rapida'],
 'Transporta avisos; no es repositorio de tareas ni memoria canónica.',60,
 '{}'::jsonb)
on conflict (system_key) do update
set display_name=excluded.display_name,
    primary_role=excluded.primary_role,
    authoritative_for=excluded.authoritative_for,
    write_policy=excluded.write_policy,
    read_priority=excluded.read_priority,
    metadata=excluded.metadata,
    enabled=true,
    updated_at=clock_timestamp();

create or replace function public.memory_home_payload_v1()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with
sources as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'system_key',s.system_key,
    'name',s.display_name,
    'role',s.primary_role,
    'authoritative_for',s.authoritative_for,
    'write_policy',s.write_policy
  ) order by s.read_priority,s.system_key),'[]'::jsonb) j
  from public.memory_source_of_truth s
  where s.enabled
),
waiting as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'title',i.title,'card_url',i.card_url,'state',i.list_name,
    'blockers',coalesce(i.blockers,'[]'::jsonb),
    'last_action',i.last_action,'executor',i.executor
  ) order by i.title),'[]'::jsonb) j
  from public.memory_execution_integrity_v i
  where i.list_name='Espera de vos'
),
running as (
  select coalesce(jsonb_agg(x.j order by x.sort_at desc),'[]'::jsonb) j
  from (
    select jsonb_build_object(
      'kind','execution',
      'project_key',s.project_key,'project_name',s.project_name,
      'card_url',s.card_url,'executor',s.executor,
      'state',s.observed_state,'last_action',s.last_action,
      'version',s.version,'last_activity_at',s.last_activity_at
    ) j, s.last_activity_at sort_at
    from public.memory_execution_status_v s
    where s.is_running is true and s.observed_state='running'
    union all
    select jsonb_build_object(
      'kind','queue',
      'project_key',p.project_key,'project_name',p.project_name,
      'card_url',q.card_url,'executor',q.executor_key,
      'state',q.state,'last_action',q.task_text,
      'version',null,'last_activity_at',coalesce(q.started_at,q.claimed_at,q.created_at)
    ) j, coalesce(q.started_at,q.claimed_at,q.created_at) sort_at
    from public.memory_execution_queue q
    left join public.memory_projects p on p.id=q.project_id
    where q.state in ('claimed','running')
  ) x
),
projects as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'project_key',p.project_key,
    'project_name',p.project_name,
    'type',p.project_type,
    'connector_status',p.connector_status,
    'last_event_at',p.last_event_at,
    'execution_state',coalesce(s.observed_state,'idle'),
    'executor',s.executor,
    'last_action',s.last_action,
    'version',s.version,
    'last_activity_at',s.last_activity_at
  ) order by p.project_name),'[]'::jsonb) j
  from public.memory_projects p
  left join public.memory_execution_status_v s on s.project_id=p.id
  where p.owner_key='duilio' and p.status='active'
),
today_cards as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'title',q.title,'state',q.list_name,'card_url',q.card_url,
    'importance',q.importance,'updated_at',q.updated_at
  ) order by
    case q.list_name when 'Espera de vos' then 1 when 'En prueba' then 2 when 'Por hacer' then 3 else 9 end,
    q.importance desc nulls last,q.updated_at desc
  ),'[]'::jsonb) j
  from (
    select *
    from public.memory_trello_queue_v
    where list_name in ('Espera de vos','En prueba','Por hacer')
    order by
      case list_name when 'Espera de vos' then 1 when 'En prueba' then 2 when 'Por hacer' then 3 else 9 end,
      importance desc nulls last,updated_at desc
    limit 12
  ) q
),
counts as (
  select jsonb_build_object(
    'por_hacer',(select count(*) from public.memory_trello_queue_v where list_name='Por hacer'),
    'en_ejecucion',(select count(*) from public.memory_execution_integrity_v where list_name='En ejecución'),
    'en_prueba',(select count(*) from public.memory_trello_queue_v where list_name='En prueba'),
    'espera_de_vos',(select count(*) from public.memory_trello_queue_v where list_name='Espera de vos'),
    'ejecuciones_reales',(select count(*) from public.memory_execution_status_v where is_running is true and observed_state='running')
  ) j
),
sync_health as (
  select coalesce(metadata->'trello_sync','{}'::jsonb) j
  from public.memory_projects
  where owner_key='duilio' and project_key='memoria-duilio'
  limit 1
)
select jsonb_build_object(
  'generated_at',clock_timestamp(),
  'operating_model_version','1.0',
  'today',jsonb_build_object(
    'counts',(select j from counts),
    'priority_items',(select j from today_cards),
    'trello_sync',coalesce((select j from sync_health),'{}'::jsonb)
  ),
  'projects',(select j from projects),
  'running',(select j from running),
  'waiting_for_you',(select j from waiting),
  'source_of_truth',(select j from sources)
);
$$;

revoke execute on function public.memory_home_payload_v1() from public,anon,authenticated;
grant execute on function public.memory_home_payload_v1() to service_role;

-- ============================================================================
-- 20260919052556_memory_source_router_and_query_plan_v1
-- ============================================================================
create or replace function public.memory_source_router_v1(p_request text)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  q text := lower(coalesce(p_request,''));
  primary_key text;
  support_keys text[];
begin
  if q ~ '(corriendo|ejecuci[oó]n real|ejecutor|heartbeat|lease|agente activo|qu[eé] est[aá] ejecutando)' then
    primary_key := 'supabase';
    support_keys := array['trello'];
  elsif q ~ '(pendiente|por hacer|en prueba|espera de vos|tarjeta|tarea|pr[oó]xima acci[oó]n|estado del tablero)' then
    primary_key := 'trello';
    support_keys := array['supabase'];
  elsif q ~ '(c[oó]digo|repositorio|repo|github|commit|pull request|\bpr\b|rama|release|apk|versi[oó]n.*c[oó]digo)' then
    primary_key := 'github';
    support_keys := array['trello','supabase'];
  elsif q ~ '(documentaci[oó]n|manual|notion|historial narrativo|especificaci[oó]n)' then
    primary_key := 'notion';
    support_keys := array['trello'];
  elsif q ~ '(automatiz|\bn8n\b|webhook|cron|programaci[oó]n recurrente|cada d[ií]a|cada lunes)' then
    primary_key := 'n8n';
    support_keys := array['supabase','trello'];
  elsif q ~ '(whatsapp|avisame|aviso|notificaci[oó]n)' then
    primary_key := 'whatsapp';
    support_keys := array['n8n'];
  else
    primary_key := 'memoria-duilio';
    support_keys := array['trello','supabase'];
  end if;

  return jsonb_build_object(
    'request',p_request,
    'primary_source',(
      select jsonb_build_object(
        'system_key',s.system_key,'name',s.display_name,'role',s.primary_role,
        'authoritative_for',s.authoritative_for,'write_policy',s.write_policy
      )
      from public.memory_source_of_truth s
      where s.system_key=primary_key and s.enabled
    ),
    'supporting_sources',coalesce((
      select jsonb_agg(jsonb_build_object(
        'system_key',s.system_key,'name',s.display_name,'role',s.primary_role
      ) order by array_position(support_keys,s.system_key))
      from public.memory_source_of_truth s
      where s.system_key=any(support_keys) and s.enabled
    ),'[]'::jsonb)
  );
end;
$$;

revoke execute on function public.memory_source_router_v1(text) from public,anon,authenticated;
grant execute on function public.memory_source_router_v1(text) to service_role;

create or replace function public.memory_query_plan_v1(
  p_request text,
  p_project_key text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  source_plan jsonb;
  executor_plan jsonb;
begin
  source_plan := public.memory_source_router_v1(p_request);
  executor_plan := public.memory_select_executor_v2(p_request,p_project_key,null);
  return jsonb_build_object(
    'generated_at',clock_timestamp(),
    'request',p_request,
    'project_key',p_project_key,
    'source_plan',source_plan,
    'executor_plan',executor_plan
  );
end;
$$;

revoke execute on function public.memory_query_plan_v1(text,text) from public,anon,authenticated;
grant execute on function public.memory_query_plan_v1(text,text) to service_role;

-- ============================================================================
-- 20260919052616_memory_source_router_precedence_fix_v1
-- ============================================================================
create or replace function public.memory_source_router_v1(p_request text)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  q text := lower(coalesce(p_request,''));
  primary_key text;
  support_keys text[];
begin
  if q ~ '(c[oó]digo|repositorio|repo|github|commit|pull request|\bpr\b|rama|release|apk|versi[oó]n.*c[oó]digo)' then
    primary_key := 'github'; support_keys := array['trello','supabase'];
  elsif q ~ '(automatiz|\bn8n\b|webhook|cron|programaci[oó]n recurrente|cada d[ií]a|cada lunes|cada semana|todos los d[ií]as)' then
    primary_key := 'n8n'; support_keys := array['supabase','trello'];
  elsif q ~ '(corriendo|ejecuci[oó]n real|ejecutor|heartbeat|lease|agente activo|qu[eé] est[aá] ejecutando)' then
    primary_key := 'supabase'; support_keys := array['trello'];
  elsif q ~ '(pendiente|por hacer|en prueba|espera de vos|tarjeta|tarea|pr[oó]xima acci[oó]n|estado del tablero)' then
    primary_key := 'trello'; support_keys := array['supabase'];
  elsif q ~ '(documentaci[oó]n|manual|notion|historial narrativo|especificaci[oó]n)' then
    primary_key := 'notion'; support_keys := array['trello'];
  elsif q ~ '(whatsapp|avisame|aviso|notificaci[oó]n)' then
    primary_key := 'whatsapp'; support_keys := array['n8n'];
  else
    primary_key := 'memoria-duilio'; support_keys := array['trello','supabase'];
  end if;

  return jsonb_build_object(
    'request',p_request,
    'primary_source',(
      select jsonb_build_object(
        'system_key',s.system_key,'name',s.display_name,'role',s.primary_role,
        'authoritative_for',s.authoritative_for,'write_policy',s.write_policy)
      from public.memory_source_of_truth s
      where s.system_key=primary_key and s.enabled),
    'supporting_sources',coalesce((
      select jsonb_agg(jsonb_build_object(
        'system_key',s.system_key,'name',s.display_name,'role',s.primary_role)
        order by array_position(support_keys,s.system_key))
      from public.memory_source_of_truth s
      where s.system_key=any(support_keys) and s.enabled),'[]'::jsonb)
  );
end;
$$;

-- ============================================================================
-- 20260920232439_memory_duilio_integrity_gate_v1
-- ============================================================================
create table if not exists public.memory_integrity_incidents (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  project_id uuid references public.memory_projects(id) on delete cascade,
  project_key text,
  inconsistency_type text not null,
  severity text not null default 'blocking',
  status text not null default 'open',
  fingerprint text not null,
  summary text not null,
  details jsonb not null default '{}'::jsonb,
  detected_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution jsonb not null default '{}'::jsonb,
  unique(owner_key,fingerprint)
);

create index if not exists memory_integrity_incidents_open_idx
on public.memory_integrity_incidents(owner_key,status,severity,project_key);

alter table public.memory_integrity_incidents enable row level security;

create or replace function public.memory_refresh_integrity(p_owner_key text default 'duilio')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz := now();
  v_open integer;
begin
  -- Version drift between GitHub authority and observed sources.
  insert into public.memory_integrity_incidents(
    owner_key,project_id,project_key,inconsistency_type,severity,status,fingerprint,summary,details,detected_at,last_seen_at
  )
  select
    p_owner_key,v.project_id,v.project_key,'version_drift','blocking','open',
    'version_drift:'||v.project_key,
    'Las versiones observadas no coinciden con GitHub.',
    jsonb_build_object('canonical_version',v.canonical_version,'sources',v.sources),
    v_now,v_now
  from public.memory_project_version_consistency_v v
  join public.memory_projects p on p.id=v.project_id
  where p.owner_key=p_owner_key
    and p.status='active'
    and v.canonical_version is not null
    and v.consistent=false
  on conflict(owner_key,fingerprint) do update set
    status='open', severity='blocking', summary=excluded.summary, details=excluded.details,
    last_seen_at=v_now, resolved_at=null, resolution='{}'::jsonb;

  -- Automatic capture declared but no automatic connected connector exists.
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
  where p.owner_key=p_owner_key
    and p.status='active'
    and p.auto_capture_enabled=true
    and not exists (
      select 1 from public.memory_project_connectors c
      where c.project_id=p.id and c.automatic=true and c.status='connected'
    )
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='blocking',summary=excluded.summary,details=excluded.details,
    last_seen_at=v_now,resolved_at=null,resolution='{}'::jsonb;

  -- Automatic connectors must actually be connected.
  insert into public.memory_integrity_incidents(
    owner_key,project_id,project_key,inconsistency_type,severity,status,fingerprint,summary,details,detected_at,last_seen_at
  )
  select
    p_owner_key,p.id,p.project_key,'automatic_connector_not_connected','blocking','open',
    'automatic_connector_not_connected:'||p.project_key||':'||c.connector_type||':'||c.connector_name,
    'Un conector marcado automático no está conectado.',
    jsonb_build_object('connector_type',c.connector_type,'connector_name',c.connector_name,'status',c.status),
    v_now,v_now
  from public.memory_project_connectors c
  join public.memory_projects p on p.id=c.project_id
  where p.owner_key=p_owner_key and p.status='active'
    and c.automatic=true and c.status<>'connected'
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='blocking',summary=excluded.summary,details=excluded.details,
    last_seen_at=v_now,resolved_at=null,resolution='{}'::jsonb;

  -- Resolve managed incidents not seen in this refresh.
  update public.memory_integrity_incidents i
     set status='resolved',
         resolved_at=v_now,
         resolution=jsonb_build_object('reason','condition_no_longer_present','resolved_at',v_now)
   where i.owner_key=p_owner_key
     and i.status='open'
     and i.inconsistency_type in ('version_drift','automatic_capture_without_connector','automatic_connector_not_connected')
     and i.last_seen_at < v_now;

  select count(*) into v_open
  from public.memory_integrity_incidents
  where owner_key=p_owner_key and status='open' and severity='blocking';

  return jsonb_build_object(
    'checked_at',v_now,
    'blocking_open',v_open,
    'passed',(v_open=0)
  );
end;
$$;

revoke all on function public.memory_refresh_integrity(text) from public;
grant execute on function public.memory_refresh_integrity(text) to service_role;

create or replace function public.memory_integrity_gate(
  p_project_key text default null,
  p_owner_key text default 'duilio'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_refresh jsonb;
  v_items jsonb;
  v_count integer;
begin
  v_refresh := public.memory_refresh_integrity(p_owner_key);

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'id',id,
           'project_key',project_key,
           'type',inconsistency_type,
           'summary',summary,
           'details',details,
           'detected_at',detected_at,
           'last_seen_at',last_seen_at
         ) order by detected_at desc),'[]'::jsonb)
    into v_count,v_items
  from public.memory_integrity_incidents
  where owner_key=p_owner_key
    and status='open'
    and severity='blocking'
    and (p_project_key is null or project_key=p_project_key);

  return jsonb_build_object(
    'passed',(v_count=0),
    'blocked',(v_count>0),
    'state',case when v_count>0 then 'BLOQUEADO_POR_INCONSISTENCIA' else 'CONSISTENTE' end,
    'blocking_count',v_count,
    'incidents',v_items,
    'checked_at',now()
  );
end;
$$;

revoke all on function public.memory_integrity_gate(text,text) from public;
grant execute on function public.memory_integrity_gate(text,text) to service_role;

-- Hard operational rule.
insert into public.memory_learning_rules(
  owner_key,rule_key,statement,confidence,evidence_count,success_count,failure_count,status,provenance,created_at,updated_at
)
values(
 'duilio',
 'block_on_cross_source_inconsistency',
 'Antes de informar un estado vigente, versión, próxima acción o cierre, Memoria Duilio debe reconciliar las fuentes según memory_source_of_truth. Si existe una inconsistencia bloqueante entre fuentes, el proyecto queda BLOQUEADO_POR_INCONSISTENCIA: no se puede presentar ningún dato conflictivo como vigente hasta reconciliarlo y registrar evidencia. GitHub manda en código/versiones; Trello en estado operativo; Supabase en ejecución real; Notion en documentación.',
 1.0,1,1,0,'active',
 jsonb_build_object('source','user_instruction','date','2026-09-20','incident','Feli version drift Trello/GitHub/Supabase'),
 now(),now()
)
on conflict(owner_key,rule_key) do update set
 statement=excluded.statement,confidence=1.0,status='active',
 evidence_count=memory_learning_rules.evidence_count+1,
 success_count=memory_learning_rules.success_count+1,
 provenance=excluded.provenance,updated_at=now();

-- Constitution 6.1.0: inherit 6.0.0 plus integrity gate.
update public.memory_constitution set status='historical'
where status='active' and version<>'6.1.0';

insert into public.memory_constitution(
 version,status,purpose,principles,assistant_identity,user_collaboration_model,reasoning_policy,
 affective_policy,migration_policy,parent_version,change_summary,behavior_dna,content_hash,activated_at,metadata
)
select
 '6.1.0','active',purpose,
 principles || jsonb_build_array(
   'bloquear estados vigentes cuando las fuentes autorizadas se contradicen',
   'reconciliar antes de responder, cerrar o avanzar'
 ),
 assistant_identity,user_collaboration_model,
 reasoning_policy || jsonb_build_object(
   'integrity_gate','Obligatorio antes de informar estado vigente, versión, cierre o próxima acción.',
   'on_inconsistency','BLOQUEADO_POR_INCONSISTENCIA hasta reconciliación con evidencia'
 ),
 affective_policy,migration_policy,'6.0.0',
 'Agrega bloqueo obligatorio por inconsistencias entre fuentes de verdad y reconciliación previa.',
 behavior_dna || jsonb_build_object(
   'integrity',jsonb_build_array(
     'consultar la fuente autoritativa antes de declarar estado vigente',
     'no elegir silenciosamente entre fuentes contradictorias',
     'bloquear y registrar la inconsistencia',
     'reconciliar y guardar evidencia antes de continuar'
   )
 ),
 null,now(),
 metadata || jsonb_build_object('integrity_gate_version',1,'activated_reason','Feli cross-source version inconsistency')
from public.memory_constitution
where version='6.0.0'
on conflict(version) do update set
 status='active',activated_at=now(),
 change_summary=excluded.change_summary,
 principles=excluded.principles,
 reasoning_policy=excluded.reasoning_policy,
 behavior_dna=excluded.behavior_dna,
 metadata=excluded.metadata;

-- Surface integrity in project resume; do not hide the project, but explicitly block "vigente".
create or replace function public.memory_resume_project(p_project_key text, p_owner_key text default 'duilio')
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
 pid uuid;
 result jsonb;
 startup jsonb;
 pinned jsonb;
 operational_rules jsonb;
 integrity jsonb;
begin
 select id into pid from public.memory_projects
 where project_key=p_project_key and owner_key=p_owner_key and status='active';
 if pid is null then raise exception 'project_not_found'; end if;

 integrity := public.memory_integrity_gate(p_project_key,p_owner_key);

 select coalesce(jsonb_agg(x order by x.subject_key,x.id),'[]'::jsonb) into startup
 from (
  select m.id,m.title,m.content,m.summary,m.claim_state,m.subject_key,
   m.updated_at,m.valid_from,m.valid_until,p.project_key,
   v.source_ref,v.test_key,v.tested_at,v.verified_by
  from public.memory_items m join public.memory_projects p on p.id=m.project_id
  left join public.memory_verifications v on v.id=m.verification_id
  where p.project_key='memoria-duilio' and p.owner_key=p_owner_key and p.status='active'
   and m.owner_key=p_owner_key and m.status='active'
   and m.subject_key in ('capa0-startup-phase-continuity','phase6-evidence-controls',
     'phase7-proactive-project-catalog','phase8-automatic-verification')
   and (m.valid_from is null or m.valid_from<=now())
   and (m.valid_until is null or m.valid_until>now())
 ) x;

 select coalesce(jsonb_agg(jsonb_build_object(
   'id',r.id,'rule_key',r.rule_key,'statement',r.statement,'confidence',r.confidence,
   'status',r.status,'provenance',r.provenance,'updated_at',r.updated_at
 ) order by r.rule_key),'[]'::jsonb)
 into operational_rules
 from public.memory_learning_rules r
 where r.owner_key=p_owner_key and r.status='active';

 select coalesce(jsonb_agg(m.id),'[]'::jsonb) into pinned
 from public.memory_items m
 where m.project_id=pid and m.owner_key=p_owner_key and m.status='active'
  and m.subject_key is not null
  and (m.valid_from is null or m.valid_from<=now())
  and (m.valid_until is null or m.valid_until>now());

 select jsonb_build_object(
  'project_key',p_project_key,
  'as_of',now(),
  'integrity',integrity,
  'effective_state',case when coalesce((integrity->>'blocked')::boolean,false)
                         then 'BLOQUEADO_POR_INCONSISTENCIA' else 'VIGENTE' end,
  'items',coalesce(jsonb_agg(x order by x.updated_at desc,x.id),'[]'::jsonb),
  'interpretation','Only claim_state=verified has a recorded successful test. Requested, executed and recorded are not verified completion.',
  'startup_context',startup,
  'operational_rules',operational_rules,
  'startup',jsonb_build_object(
    'version','0.4',
    'required_before_response',true,
    'integrity_gate_required',true,
    'integrity_passed',coalesce((integrity->>'passed')::boolean,false),
    'protocol_present',exists(select 1 from jsonb_array_elements(startup) s where s->>'subject_key'='capa0-startup-phase-continuity'),
    'operational_rules_loaded',jsonb_array_length(operational_rules),
    'phase_keys',jsonb_build_array(6,7,8),
    'scope','Backend retrieval. Consumers must read startup_context, operational_rules and integrity before routing or execution.',
    'project_state_policy','all current named subjects plus 30 recent items',
    'pinned_item_ids',pinned
  )
 ) into result
 from (
  select m.id,m.title,m.content,m.summary,m.claim_state,m.subject_key,m.updated_at,m.valid_from,m.valid_until,
    v.source_ref,v.test_key,v.tested_at,v.verified_by
  from public.memory_items m left join public.memory_verifications v on v.id=m.verification_id
  where m.project_id=pid and m.owner_key=p_owner_key and m.status='active'
   and (m.valid_from is null or m.valid_from<=now())
   and (m.valid_until is null or m.valid_until>now())
   and (m.subject_key is not null or m.id in (
    select r.id from public.memory_items r
    where r.project_id=pid and r.owner_key=p_owner_key and r.status='active'
      and (r.valid_from is null or r.valid_from<=now())
      and (r.valid_until is null or r.valid_until>now())
    order by r.updated_at desc,r.id limit 30))
 ) x;
 return result;
end
$function$;

create or replace function public.memory_check_startup(p_owner_key text default 'duilio')
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
 p record;
 r jsonb;
 gate jsonb;
 checks jsonb='[]'::jsonb;
 ok boolean=true;
 item_ok boolean;
 run_id uuid;
 cnt integer=0;
begin
 gate := public.memory_integrity_gate(null,p_owner_key);
 ok := not coalesce((gate->>'blocked')::boolean,true);
 checks := checks || jsonb_build_array(jsonb_build_object(
   'check','global_integrity_gate',
   'passed',not coalesce((gate->>'blocked')::boolean,true),
   'integrity',gate
 ));

 for p in select project_key from public.memory_projects where owner_key=p_owner_key and status='active'
 loop
  cnt:=cnt+1;
  begin
   r:=public.memory_resume_project(p.project_key,p_owner_key);
   item_ok:=coalesce((r->'startup'->>'protocol_present')::boolean,false)
    and coalesce((r->'startup'->>'operational_rules_loaded')::integer,0) > 0
    and coalesce((r->'startup'->>'integrity_passed')::boolean,false)
    and exists(
      select 1 from jsonb_array_elements(r->'operational_rules') q
      where q->>'rule_key'='optimize_work_quota_before_execution'
    )
    and exists(
      select 1 from jsonb_array_elements(r->'operational_rules') q
      where q->>'rule_key'='block_on_cross_source_inconsistency'
    )
    and (r->'startup_context' @> '[{"subject_key":"phase6-evidence-controls"},{"subject_key":"phase7-proactive-project-catalog"},{"subject_key":"phase8-automatic-verification"}]'::jsonb);
   ok:=ok and item_ok;
   checks:=checks||jsonb_build_array(jsonb_build_object(
     'project_key',p.project_key,'passed',item_ok,'check','startup_phases_rules_and_integrity'
   ));
  exception when others then
   ok:=false;
   checks:=checks||jsonb_build_array(jsonb_build_object('project_key',p.project_key,'passed',false,'error',sqlerrm));
  end;
 end loop;

 if cnt=0 then
   ok:=false;
   checks:=checks||'[{"passed":false,"error":"no_active_projects"}]'::jsonb;
 end if;

 insert into public.memory_startup_checks(owner_key,passed,results)
 values(p_owner_key,ok,checks) returning id into run_id;

 return jsonb_build_object(
   'run_id',run_id,'passed',ok,'checks',checks,
   'scope','Backend retrieval verifies Capa 0, phases 6/7/8, operational rules, and cross-source integrity gate.'
 );
end
$function$;

update public.memory_source_of_truth
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
  'integrity_gate_required',true,
  'conflict_policy','block_and_reconcile',
  'never_silently_choose_conflicting_source',true
),
updated_at=now()
where enabled=true;

-- ============================================================================
-- 20260920232828_memory_duilio_safe_self_heal_v1
-- ============================================================================
create or replace function public.memory_auto_repair_safe_inconsistencies(
  p_owner_key text default 'duilio'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz := now();
  v_connectors_fixed integer := 0;
  v_projects_fixed integer := 0;
  v_rows integer := 0;
begin
  -- Safe repair 1: a connector cannot be both automatic and not connected.
  update public.memory_project_connectors c
     set automatic=false,
         metadata=coalesce(c.metadata,'{}'::jsonb) || jsonb_build_object(
           'auto_repaired_at',v_now,
           'auto_repair_reason','automatic connector was not connected',
           'previous_automatic',true
         ),
         updated_at=v_now
  from public.memory_projects p
  where p.id=c.project_id
    and p.owner_key=p_owner_key
    and p.status='active'
    and c.automatic=true
    and c.status<>'connected';
  get diagnostics v_connectors_fixed = row_count;

  -- Safe repair 2: a project cannot claim automatic capture without at least one automatic connected connector.
  update public.memory_projects p
     set auto_capture_enabled=false,
         capture_mode=case when p.capture_mode='automatic' then 'assisted' else p.capture_mode end,
         metadata=coalesce(p.metadata,'{}'::jsonb) || jsonb_build_object(
           'auto_repaired_at',v_now,
           'auto_repair_reason','automatic capture disabled because no automatic connected connector exists',
           'previous_auto_capture_enabled',true
         ),
         updated_at=v_now
  where p.owner_key=p_owner_key
    and p.status='active'
    and p.auto_capture_enabled=true
    and not exists (
      select 1
      from public.memory_project_connectors c
      where c.project_id=p.id
        and c.automatic=true
        and c.status='connected'
    );
  get diagnostics v_projects_fixed = row_count;

  perform public.memory_refresh_integrity(p_owner_key);

  return jsonb_build_object(
    'repaired_at',v_now,
    'connectors_fixed',v_connectors_fixed,
    'projects_fixed',v_projects_fixed,
    'policy','safe_reversible_only'
  );
end;
$$;

revoke all on function public.memory_auto_repair_safe_inconsistencies(text) from public;
grant execute on function public.memory_auto_repair_safe_inconsistencies(text) to service_role;

-- Upgrade the integrity refresh so safe administrative drift self-heals first.
create or replace function public.memory_refresh_integrity(p_owner_key text default 'duilio')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_now timestamptz := now();
  v_open integer;
begin
  -- Version drift between GitHub authority and observed sources.
  insert into public.memory_integrity_incidents(
    owner_key,project_id,project_key,inconsistency_type,severity,status,fingerprint,summary,details,detected_at,last_seen_at
  )
  select
    p_owner_key,v.project_id,v.project_key,'version_drift','blocking','open',
    'version_drift:'||v.project_key,
    'Las versiones observadas no coinciden con GitHub.',
    jsonb_build_object('canonical_version',v.canonical_version,'sources',v.sources),
    v_now,v_now
  from public.memory_project_version_consistency_v v
  join public.memory_projects p on p.id=v.project_id
  where p.owner_key=p_owner_key
    and p.status='active'
    and v.canonical_version is not null
    and v.consistent=false
  on conflict(owner_key,fingerprint) do update set
    status='open', severity='blocking', summary=excluded.summary, details=excluded.details,
    last_seen_at=v_now, resolved_at=null, resolution='{}'::jsonb;

  -- Configuration inconsistencies that remain after safe self-repair.
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
  where p.owner_key=p_owner_key
    and p.status='active'
    and p.auto_capture_enabled=true
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
    p_owner_key,p.id,p.project_key,'automatic_connector_not_connected','blocking','open',
    'automatic_connector_not_connected:'||p.project_key||':'||c.connector_type||':'||c.connector_name,
    'Un conector marcado automático no está conectado.',
    jsonb_build_object('connector_type',c.connector_type,'connector_name',c.connector_name,'status',c.status),
    v_now,v_now
  from public.memory_project_connectors c
  join public.memory_projects p on p.id=c.project_id
  where p.owner_key=p_owner_key and p.status='active'
    and c.automatic=true and c.status<>'connected'
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='blocking',summary=excluded.summary,details=excluded.details,
    last_seen_at=v_now,resolved_at=null,resolution='{}'::jsonb;

  -- Resolve managed incidents no longer present.
  update public.memory_integrity_incidents i
     set status='resolved',
         resolved_at=v_now,
         resolution=jsonb_build_object('reason','condition_no_longer_present','resolved_at',v_now)
   where i.owner_key=p_owner_key
     and i.status='open'
     and i.inconsistency_type in ('version_drift','automatic_capture_without_connector','automatic_connector_not_connected')
     and not (
       (i.inconsistency_type='version_drift' and exists (
          select 1 from public.memory_project_version_consistency_v v
          where v.project_key=i.project_key and v.consistent=false
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

  return jsonb_build_object(
    'checked_at',v_now,
    'blocking_open',v_open,
    'passed',(v_open=0)
  );
end;
$$;

-- Make the gate perform safe self-healing before deciding to block.
create or replace function public.memory_integrity_gate(
  p_project_key text default null,
  p_owner_key text default 'duilio'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_repair jsonb;
  v_refresh jsonb;
  v_items jsonb;
  v_count integer;
begin
  v_repair := public.memory_auto_repair_safe_inconsistencies(p_owner_key);
  v_refresh := public.memory_refresh_integrity(p_owner_key);

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'id',id,
           'project_key',project_key,
           'type',inconsistency_type,
           'summary',summary,
           'details',details,
           'detected_at',detected_at,
           'last_seen_at',last_seen_at
         ) order by detected_at desc),'[]'::jsonb)
    into v_count,v_items
  from public.memory_integrity_incidents
  where owner_key=p_owner_key
    and status='open'
    and severity='blocking'
    and (p_project_key is null or project_key=p_project_key);

  return jsonb_build_object(
    'passed',(v_count=0),
    'blocked',(v_count>0),
    'state',case when v_count>0 then 'BLOQUEADO_POR_INCONSISTENCIA' else 'CONSISTENTE' end,
    'blocking_count',v_count,
    'incidents',v_items,
    'auto_repair',v_repair,
    'checked_at',now()
  );
end;
$$;

-- Operational rule: fix safe reversible inconsistencies without asking.
insert into public.memory_learning_rules(
  owner_key,rule_key,statement,confidence,evidence_count,success_count,failure_count,status,provenance,created_at,updated_at
)
values(
 'duilio',
 'auto_repair_safe_inconsistencies_without_asking',
 'Cuando Memoria Duilio detecte una inconsistencia administrativa reversible y verificable, debe corregirla automáticamente sin pedir permiso: por ejemplo, quitar automatic=true de un conector que no está conectado, o bajar un proyecto de automatic a assisted si no existe conector automático real. Debe conservar evidencia del cambio. Sólo debe bloquear y pedir decisión cuando la corrección implique borrar datos, publicar, gastar, tocar producción, cambiar una fuente autoritativa o elegir entre datos contradictorios no resolubles automáticamente.',
 1.0,1,1,0,'active',
 jsonb_build_object('source','user_instruction','date','2026-09-20','scope','safe_reversible_integrity_repairs'),
 now(),now()
)
on conflict(owner_key,rule_key) do update set
 statement=excluded.statement,confidence=1.0,status='active',
 evidence_count=memory_learning_rules.evidence_count+1,
 success_count=memory_learning_rules.success_count+1,
 provenance=excluded.provenance,updated_at=now();

-- Update constitution 6.1.0 with self-heal policy.
update public.memory_constitution
set reasoning_policy = reasoning_policy || jsonb_build_object(
      'safe_auto_repair','Corregir automáticamente inconsistencias administrativas reversibles antes de bloquear.'
    ),
    behavior_dna = behavior_dna || jsonb_build_object(
      'self_healing',jsonb_build_array(
        'corregir sin preguntar lo reversible y verificable',
        'no marcar automático lo que no tiene conector real',
        'registrar evidencia de cada autorreparación',
        'pedir decisión sólo ante riesgo, ambigüedad real o acción sensible'
      )
    ),
    change_summary='Bloqueo por inconsistencias + autorreparación segura de drift administrativo.',
    metadata=metadata || jsonb_build_object('safe_auto_repair',true),
    activated_at=now()
where version='6.1.0';

-- ============================================================================
-- 20260920233132_memory_duilio_self_integrity_v2
-- ============================================================================
create or replace function public.memory_record_project_version(
  p_project_key text,
  p_source_system text,
  p_version text,
  p_source_ref text default null,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project public.memory_projects%rowtype;
  v_authority text;
  v_canonical text;
  v_mismatches jsonb;
  v_consistent boolean;
  v_external_id text;
begin
  select * into v_project
  from public.memory_projects
  where owner_key='duilio' and project_key=p_project_key
  limit 1;

  if v_project.id is null then raise exception 'Unknown project_key: %',p_project_key; end if;
  if p_version is null or btrim(p_version)='' then raise exception 'Version is required'; end if;

  v_authority := lower(coalesce(nullif(v_project.metadata->>'version_authority',''),'github'));

  insert into public.memory_project_version_observations(
    project_id,source_system,version,source_ref,observed_at,evidence,updated_at
  ) values (
    v_project.id,lower(p_source_system),btrim(p_version),p_source_ref,now(),coalesce(p_evidence,'{}'::jsonb),now()
  )
  on conflict(project_id,source_system) do update set
    version=excluded.version,source_ref=excluded.source_ref,observed_at=excluded.observed_at,
    evidence=excluded.evidence,updated_at=now();

  select version into v_canonical
  from public.memory_project_version_observations
  where project_id=v_project.id and source_system=v_authority
  limit 1;

  select coalesce(
    jsonb_agg(jsonb_build_object(
      'source_system',source_system,'version',version,'source_ref',source_ref,'observed_at',observed_at
    ) order by source_system)
    filter (where v_canonical is not null and version is distinct from v_canonical),
    '[]'::jsonb
  )
  into v_mismatches
  from public.memory_project_version_observations
  where project_id=v_project.id;

  v_consistent := v_canonical is not null and jsonb_array_length(v_mismatches)=0;

  update public.memory_projects
  set last_event_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'current_version',v_canonical,
        'version_authority',v_authority,
        'version_consistent',v_consistent,
        'version_mismatches',v_mismatches,
        'version_checked_at',now()
      ),
      updated_at=now()
  where id=v_project.id;

  v_external_id:=lower(p_source_system)||':'||coalesce(p_source_ref,p_version);

  insert into public.memory_ingest_events(
    owner_key,source_type,source_name,external_id,event_type,title,content,summary,source_url,
    category,memory_type,importance,occurred_at,metadata,status,processed_at,
    project_id,project_key,project_name
  ) values (
    'duilio',lower(p_source_system),lower(p_source_system),v_external_id,'version_observed',
    'Versión observada '||p_project_key||' '||p_version,
    'Se observó versión '||p_version||' en '||lower(p_source_system)||'.',
    case
      when v_canonical is null then 'Autoridad de versión todavía no observada.'
      when v_consistent then 'Versión consistente con la fuente autoritativa.'
      else 'INCONSISTENCIA de versión detectada contra la fuente autoritativa.'
    end,
    p_source_ref,'project_activity','observation',8,now(),
    jsonb_build_object(
      'version',p_version,'canonical_version',v_canonical,'version_authority',v_authority,
      'source_system',lower(p_source_system),'consistent',v_consistent,'mismatches',v_mismatches,
      'evidence',coalesce(p_evidence,'{}'::jsonb)
    ),
    'processed',now(),v_project.id,p_project_key,v_project.project_name
  )
  on conflict(owner_key,source_type,external_id,event_type) do update set
    title=excluded.title,content=excluded.content,summary=excluded.summary,source_url=excluded.source_url,
    occurred_at=excluded.occurred_at,metadata=excluded.metadata,status='processed',processed_at=now(),
    project_id=excluded.project_id,project_key=excluded.project_key,project_name=excluded.project_name;

  return jsonb_build_object(
    'project_key',p_project_key,'version_authority',v_authority,
    'canonical_version',v_canonical,'consistent',v_consistent,'mismatches',v_mismatches
  );
end;
$$;

create or replace view public.memory_project_version_consistency_v as
with base as (
  select p.id project_id,p.project_key,p.project_name,
         lower(coalesce(nullif(p.metadata->>'version_authority',''),'github')) version_authority
  from public.memory_projects p
), canonical as (
  select b.*,o.version canonical_version,o.source_ref authority_ref,o.observed_at authority_observed_at
  from base b
  left join public.memory_project_version_observations o
    on o.project_id=b.project_id and o.source_system=b.version_authority
)
select c.project_id,c.project_key,c.project_name,c.canonical_version,
       c.authority_ref as github_ref,
       c.authority_observed_at as github_observed_at,
       coalesce(jsonb_agg(jsonb_build_object(
         'source_system',o.source_system,'version',o.version,'source_ref',o.source_ref,
         'observed_at',o.observed_at,'matches_authority',(o.version=c.canonical_version)
       ) order by o.source_system) filter(where o.id is not null),'[]'::jsonb) sources,
       case
         when c.canonical_version is null then false
         else coalesce(bool_and(o.version=c.canonical_version) filter(where o.id is not null),true)
       end consistent,
       c.version_authority
from canonical c
left join public.memory_project_version_observations o on o.project_id=c.project_id
group by c.project_id,c.project_key,c.project_name,c.canonical_version,
         c.authority_ref,c.authority_observed_at,c.version_authority;

update public.memory_projects
set source_system='supabase+trello+notion+n8n',
    source_ref='supabase://pddsehshgfynpmibjqhj/memory_constitution',
    metadata =
      (coalesce(metadata,'{}'::jsonb) - 'trello_execution')
      || jsonb_build_object(
        'version_authority','supabase',
        'current_version','6.1.0',
        'current_state',jsonb_build_object(
          'constitution','6.1.0',
          'integrity_gate','active',
          'safe_auto_repair',true,
          'trello_cards',47,
          'trello_sync_verified_at',now(),
          'n8n_connector','connected',
          'github_repository','not_canonical_yet',
          'github_repository_task','https://trello.com/c/LMkOwvC3'
        ),
        'historical_trello_execution',coalesce(metadata->'trello_execution','{}'::jsonb),
        'self_reviewed_at',now()
      ),
    last_event_at=now(),
    updated_at=now()
where owner_key='duilio' and project_key='memoria-duilio';

select public.memory_record_project_version(
  'memoria-duilio','supabase','6.1.0',
  'supabase://pddsehshgfynpmibjqhj/memory_constitution/6.1.0',
  jsonb_build_object('authority','memory_constitution','status','active')
);

select public.memory_record_project_version(
  'memoria-duilio','notion','6.1.0',
  'https://app.notion.com/p/3d0277d8646b818f92cac1b62319cbd3',
  jsonb_build_object('document','Memoria Duilio','status','updated')
);

insert into public.memory_learning_rules(
 owner_key,rule_key,statement,confidence,evidence_count,success_count,failure_count,status,provenance,created_at,updated_at
) values (
 'duilio','self_integrity_applies_to_memoria_duilio',
 'Las mismas reglas de integridad, autoridad de fuentes, bloqueo y autorreparación se aplican a Memoria Duilio sobre sí misma. Memoria Duilio no está exenta del gate: debe revisar su propia Constitución, conectores, snapshots, documentación y estado antes de declarar consistencia.',
 1.0,1,1,0,'active',
 jsonb_build_object('source','user_instruction','date','2026-09-20','scope','memoria-duilio-self-audit'),
 now(),now()
)
on conflict(owner_key,rule_key) do update set
 statement=excluded.statement,confidence=1,status='active',
 evidence_count=memory_learning_rules.evidence_count+1,
 success_count=memory_learning_rules.success_count+1,
 provenance=excluded.provenance,updated_at=now();

update public.memory_constitution
set reasoning_policy=reasoning_policy || jsonb_build_object(
      'self_integrity','Memoria Duilio debe someterse al mismo gate y autorreparación que los demás proyectos.'
    ),
    behavior_dna=behavior_dna || jsonb_build_object(
      'self_audit',jsonb_build_array(
        'revisar su propia consistencia',
        'no autoexcluirse de los controles',
        'autocorregir drift propio seguro y reversible'
      )
    ),
    change_summary='Bloqueo por inconsistencias + autorreparación segura + autoauditoría de Memoria Duilio.',
    metadata=metadata || jsonb_build_object('self_integrity_required',true),
    activated_at=now()
where version='6.1.0';

-- ============================================================================
-- 20260920233715_memory_duilio_separate_constitution_from_software_version
-- ============================================================================
update public.memory_projects
set metadata =
  (coalesce(metadata,'{}'::jsonb)
    - 'current_version'
    - 'version_consistent'
    - 'version_mismatches'
    - 'version_checked_at')
  || jsonb_build_object(
      'software_version', null,
      'software_version_status','SIN_VERSION_CANONICA',
      'software_version_authority','github',
      'github_repository_status','pending_creation_or_recovery',
      'constitution_version','6.1.0',
      'constitution_authority','supabase',
      'constitution_ref','supabase://pddsehshgfynpmibjqhj/memory_constitution/6.1.0',
      'version_model_corrected_at',now()
    ),
    updated_at=now()
where owner_key='duilio' and project_key='memoria-duilio';

delete from public.memory_project_version_observations
where project_id=(select id from public.memory_projects where owner_key='duilio' and project_key='memoria-duilio')
  and source_system in ('supabase','notion');

insert into public.memory_learning_rules(
 owner_key,rule_key,statement,confidence,evidence_count,success_count,failure_count,status,provenance,created_at,updated_at
) values (
 'duilio','separate_software_version_from_internal_schema_versions',
 'No confundir una versión interna de Constitución, esquema, API o Edge Function con la versión canónica del software/proyecto. Para Memoria Duilio, 6.1.0 es constitution_version. La software_version queda SIN_VERSION_CANONICA hasta que exista o se recupere el repositorio GitHub canónico y se etiquete allí una versión.',
 1.0,1,1,0,'active',
 jsonb_build_object('source','user_correction','date','2026-09-20','project','memoria-duilio'),
 now(),now()
)
on conflict(owner_key,rule_key) do update set
 statement=excluded.statement,confidence=1,status='active',
 evidence_count=memory_learning_rules.evidence_count+1,
 success_count=memory_learning_rules.success_count+1,
 provenance=excluded.provenance,updated_at=now();

update public.memory_constitution
set reasoning_policy=reasoning_policy || jsonb_build_object(
      'version_semantics','Separar siempre software_version de constitution/schema/API/function versions.'
    ),
    change_summary='Bloqueo por inconsistencias + autorreparación + autoauditoría + semántica estricta de versiones.',
    metadata=metadata || jsonb_build_object('software_version_semantics_strict',true),
    activated_at=now()
where version='6.1.0';

-- ============================================================================
-- 20260920234237_memory_daily_schedule_run_ledger_v1
-- ============================================================================
create table if not exists public.memory_scheduled_runs (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  schedule_key text not null,
  run_key text not null,
  scheduled_for timestamptz,
  started_at timestamptz not null default now(),
  last_heartbeat_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'started'
    check (status in ('started','running','completed','incomplete','failed')),
  step text not null default 'start',
  summary text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_key,run_key)
);

create index if not exists memory_scheduled_runs_schedule_started_idx
  on public.memory_scheduled_runs(owner_key,schedule_key,started_at desc);

alter table public.memory_scheduled_runs enable row level security;
revoke all on public.memory_scheduled_runs from anon, authenticated;

create or replace function public.memory_schedule_run_start(
  p_schedule_key text,
  p_run_key text,
  p_scheduled_for timestamptz default null,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  insert into public.memory_scheduled_runs(
    owner_key,schedule_key,run_key,scheduled_for,status,step,details
  ) values(
    'duilio',p_schedule_key,p_run_key,p_scheduled_for,'started','start',
    coalesce(p_details,'{}'::jsonb)
  )
  on conflict(owner_key,run_key) do update set
    last_heartbeat_at=now(),
    updated_at=now(),
    details=memory_scheduled_runs.details || excluded.details
  returning id into v_id;

  return jsonb_build_object('ok',true,'id',v_id,'run_key',p_run_key,'status','started','recorded_at',now());
end;
$$;

create or replace function public.memory_schedule_run_step(
  p_run_key text,
  p_status text,
  p_step text,
  p_summary text default null,
  p_details jsonb default '{}'::jsonb,
  p_finish boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_row public.memory_scheduled_runs%rowtype;
begin
  if p_status not in ('started','running','completed','incomplete','failed') then
    raise exception 'invalid status %',p_status;
  end if;

  update public.memory_scheduled_runs
  set status=p_status,
      step=p_step,
      summary=coalesce(p_summary,summary),
      details=coalesce(details,'{}'::jsonb)||coalesce(p_details,'{}'::jsonb),
      last_heartbeat_at=now(),
      finished_at=case when p_finish then now() else finished_at end,
      updated_at=now()
  where owner_key='duilio' and run_key=p_run_key
  returning * into v_row;

  if v_row.id is null then raise exception 'run not found: %',p_run_key; end if;

  return jsonb_build_object(
    'ok',true,'run_key',v_row.run_key,'status',v_row.status,'step',v_row.step,
    'started_at',v_row.started_at,'finished_at',v_row.finished_at
  );
end;
$$;

revoke all on function public.memory_schedule_run_start(text,text,timestamptz,jsonb) from public;
revoke all on function public.memory_schedule_run_step(text,text,text,text,jsonb,boolean) from public;
grant execute on function public.memory_schedule_run_start(text,text,timestamptz,jsonb) to service_role;
grant execute on function public.memory_schedule_run_step(text,text,text,text,jsonb,boolean) to service_role;

insert into public.memory_learning_rules(
 owner_key,rule_key,statement,confidence,evidence_count,success_count,failure_count,status,provenance,created_at,updated_at
) values (
 'duilio','scheduled_run_ledger_before_work',
 'Toda programación operativa de Memoria Duilio debe registrar primero su corrida en memory_scheduled_runs antes de leer o modificar tareas. Trello es evidencia operativa adicional, pero no el único registro. La corrida debe actualizar pasos/heartbeat y cerrar completed, incomplete o failed con evidencia verificable.',
 1.0,1,1,0,'active',
 jsonb_build_object('source','user_instruction','date','2026-09-20','incident','08:00 scheduler fired without operational trace'),
 now(),now()
)
on conflict(owner_key,rule_key) do update set
 statement=excluded.statement,confidence=1,status='active',
 evidence_count=memory_learning_rules.evidence_count+1,
 success_count=memory_learning_rules.success_count+1,
 provenance=excluded.provenance,updated_at=now();

-- ============================================================================
-- 20260920234638_memory_schedule_dispatch_trace_v1
-- ============================================================================
create table if not exists public.memory_schedule_dispatch_events (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null default 'duilio',
  schedule_key text not null,
  run_key text not null,
  stage text not null,
  target_system text not null,
  operation text not null,
  status text not null check (status in ('sent','received','ok','error','timeout','missing')),
  request_ref text,
  response_code text,
  response_summary text,
  error_message text,
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists memory_schedule_dispatch_events_run_idx
  on public.memory_schedule_dispatch_events(owner_key,run_key,occurred_at);

alter table public.memory_schedule_dispatch_events enable row level security;
revoke all on public.memory_schedule_dispatch_events from anon, authenticated;

create or replace function public.memory_schedule_dispatch_event(
  p_schedule_key text,
  p_run_key text,
  p_stage text,
  p_target_system text,
  p_operation text,
  p_status text,
  p_request_ref text default null,
  p_response_code text default null,
  p_response_summary text default null,
  p_error_message text default null,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  if p_status not in ('sent','received','ok','error','timeout','missing') then
    raise exception 'invalid dispatch status %',p_status;
  end if;

  insert into public.memory_schedule_dispatch_events(
    owner_key,schedule_key,run_key,stage,target_system,operation,status,
    request_ref,response_code,response_summary,error_message,details
  ) values(
    'duilio',p_schedule_key,p_run_key,p_stage,p_target_system,p_operation,p_status,
    p_request_ref,p_response_code,p_response_summary,p_error_message,coalesce(p_details,'{}'::jsonb)
  ) returning id into v_id;

  return jsonb_build_object('ok',true,'id',v_id,'run_key',p_run_key,'stage',p_stage,'status',p_status,'recorded_at',now());
end;
$$;

revoke all on function public.memory_schedule_dispatch_event(text,text,text,text,text,text,text,text,text,text,jsonb) from public;
grant execute on function public.memory_schedule_dispatch_event(text,text,text,text,text,text,text,text,text,text,jsonb) to service_role;

create or replace view public.memory_schedule_run_diagnostics_v as
select
  r.run_key,
  r.schedule_key,
  r.scheduled_for,
  r.started_at,
  r.last_heartbeat_at,
  r.finished_at,
  r.status as run_status,
  r.step as run_step,
  r.summary,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'stage',e.stage,
        'target_system',e.target_system,
        'operation',e.operation,
        'status',e.status,
        'response_code',e.response_code,
        'response_summary',e.response_summary,
        'error_message',e.error_message,
        'occurred_at',e.occurred_at
      ) order by e.occurred_at
    ) filter (where e.id is not null),
    '[]'::jsonb
  ) as dispatch_events
from public.memory_scheduled_runs r
left join public.memory_schedule_dispatch_events e
  on e.owner_key=r.owner_key and e.run_key=r.run_key
where r.owner_key='duilio'
group by r.run_key,r.schedule_key,r.scheduled_for,r.started_at,r.last_heartbeat_at,
         r.finished_at,r.status,r.step,r.summary;

insert into public.memory_learning_rules(
  owner_key,rule_key,statement,confidence,evidence_count,success_count,failure_count,status,provenance,created_at,updated_at
) values (
  'duilio',
  'scheduled_dispatch_requires_ack_and_error_trace',
  'Toda programación crítica debe trazar cada salto scheduler→proceso→destino con evidencia de envío, recepción y resultado. Si un destino devuelve error o timeout debe guardarse código/resumen/error. Si el scheduler figura ejecutado pero no existe ledger de proceso, el watchdog debe clasificarlo como fallo entre scheduler y worker, no como fallo de Trello.',
  1.0,1,1,0,'active',
  jsonb_build_object('source','user_instruction','date','2026-09-20','incident','08:00 did not reach Trello'),
  now(),now()
)
on conflict(owner_key,rule_key) do update set
  statement=excluded.statement,confidence=1,status='active',
  evidence_count=memory_learning_rules.evidence_count+1,
  success_count=memory_learning_rules.success_count+1,
  provenance=excluded.provenance,updated_at=now();

-- ============================================================================
-- 20260921001804_memory_integrity_live_source_freshness_v1
-- ============================================================================
create or replace view public.memory_project_version_consistency_v as
with base as (
  select
    p.id as project_id,
    p.project_key,
    p.project_name,
    lower(coalesce(
      nullif(p.metadata->>'software_version_authority',''),
      nullif(p.metadata->>'version_authority',''),
      'github'
    )) as version_authority
  from public.memory_projects p
),
canonical as (
  select
    b.project_id,b.project_key,b.project_name,b.version_authority,
    o.version as canonical_version,
    o.source_ref as authority_ref,
    o.observed_at as authority_observed_at
  from base b
  left join public.memory_project_version_observations o
    on o.project_id=b.project_id
   and o.source_system=b.version_authority
)
select
  c.project_id,
  c.project_key,
  c.project_name,
  c.canonical_version,
  c.authority_ref as github_ref,
  c.authority_observed_at as github_observed_at,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'source_system',o.source_system,
        'version',o.version,
        'source_ref',o.source_ref,
        'observed_at',o.observed_at,
        'matches_authority',o.version=c.canonical_version
      ) order by o.source_system
    ) filter (where o.id is not null),
    '[]'::jsonb
  ) as sources,
  case
    when c.canonical_version is null then false
    else coalesce(bool_and(o.version=c.canonical_version) filter (where o.id is not null),true)
  end as consistent,
  c.version_authority
from canonical c
left join public.memory_project_version_observations o on o.project_id=c.project_id
group by c.project_id,c.project_key,c.project_name,c.canonical_version,
         c.authority_ref,c.authority_observed_at,c.version_authority;

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
      nullif(mp.metadata->>'software_version_authority',''),
      nullif(mp.metadata->>'version_authority',''),
      'github'
    )) as version_authority,
    coalesce(
      nullif(mp.metadata->>'github_repo',''),
      case when mp.source_ref like 'https://github.com/%' then mp.source_ref else null end
    ) as github_repo
  from public.memory_projects mp
  where mp.owner_key='duilio' and mp.status='active'
)
select
  p.project_id,
  p.project_key,
  p.project_name,
  p.version_authority,
  case when p.version_authority='github' then p.github_repo else p.source_ref end as authority_ref,
  o.version as observed_version,
  o.observed_at,
  case
    when p.version_authority='github'
      and p.github_repo is not null
      and coalesce(p.metadata->>'github_repository_status','') <> 'pending_creation'
      then true
    when p.version_authority<>'github'
      and nullif(p.source_ref,'') is not null
      and p.source_ref not in (p.project_key,'supervision','doinglio','conexion','oleum','puente-ia','redes-revalsoftia','n8n-sql-automatizaciones','revalsoft-saas')
      then true
    else false
  end as refresh_required,
  case
    when not (
      (p.version_authority='github' and p.github_repo is not null
       and coalesce(p.metadata->>'github_repository_status','') <> 'pending_creation')
      or
      (p.version_authority<>'github' and nullif(p.source_ref,'') is not null
       and p.source_ref not in (p.project_key,'supervision','doinglio','conexion','oleum','puente-ia','redes-revalsoftia','n8n-sql-automatizaciones','revalsoft-saas'))
    ) then 'not_applicable'
    when o.id is null then 'missing'
    when o.observed_at < now() - interval '2 hours' then 'stale'
    else 'fresh'
  end as freshness_state
from p
left join public.memory_project_version_observations o
  on o.project_id=p.project_id and o.source_system=p.version_authority;

create or replace function public.memory_record_project_version(
  p_project_key text,
  p_source_system text,
  p_version text,
  p_source_ref text default null,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_project public.memory_projects%rowtype;
  v_authority text;
  v_canonical text;
  v_mismatches jsonb;
  v_consistent boolean;
  v_external_id text;
begin
  select * into v_project
  from public.memory_projects
  where owner_key='duilio' and project_key=p_project_key
  limit 1;

  if v_project.id is null then raise exception 'Unknown project_key: %',p_project_key; end if;
  if p_version is null or btrim(p_version)='' then raise exception 'Version is required'; end if;

  v_authority := lower(coalesce(
    nullif(v_project.metadata->>'software_version_authority',''),
    nullif(v_project.metadata->>'version_authority',''),
    'github'
  ));

  insert into public.memory_project_version_observations(
    project_id,source_system,version,source_ref,observed_at,evidence,updated_at
  ) values (
    v_project.id,lower(p_source_system),btrim(p_version),p_source_ref,now(),coalesce(p_evidence,'{}'::jsonb),now()
  )
  on conflict(project_id,source_system) do update set
    version=excluded.version,source_ref=excluded.source_ref,observed_at=excluded.observed_at,
    evidence=excluded.evidence,updated_at=now();

  select version into v_canonical
  from public.memory_project_version_observations
  where project_id=v_project.id and source_system=v_authority
  limit 1;

  select coalesce(
    jsonb_agg(jsonb_build_object(
      'source_system',source_system,'version',version,'source_ref',source_ref,'observed_at',observed_at
    ) order by source_system)
    filter (where v_canonical is not null and version is distinct from v_canonical),
    '[]'::jsonb
  )
  into v_mismatches
  from public.memory_project_version_observations
  where project_id=v_project.id;

  v_consistent := v_canonical is not null and jsonb_array_length(v_mismatches)=0;

  update public.memory_projects
  set last_event_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'current_version',v_canonical,
        'software_version_authority',v_authority,
        'version_consistent',v_consistent,
        'version_mismatches',v_mismatches,
        'version_checked_at',now()
      ),
      updated_at=now()
  where id=v_project.id;

  v_external_id:=lower(p_source_system)||':'||coalesce(p_source_ref,p_version);

  insert into public.memory_ingest_events(
    owner_key,source_type,source_name,external_id,event_type,title,content,summary,source_url,
    category,memory_type,importance,occurred_at,metadata,status,processed_at,
    project_id,project_key,project_name
  ) values (
    'duilio',lower(p_source_system),lower(p_source_system),v_external_id,'version_observed',
    'Versión observada '||p_project_key||' '||p_version,
    'Se observó versión '||p_version||' en '||lower(p_source_system)||'.',
    case
      when v_canonical is null then 'Autoridad de versión todavía no observada.'
      when v_consistent then 'Versión consistente con la fuente autoritativa.'
      else 'INCONSISTENCIA de versión detectada contra la fuente autoritativa.'
    end,
    p_source_ref,'project_activity','observation',8,now(),
    jsonb_build_object(
      'version',p_version,'canonical_version',v_canonical,'version_authority',v_authority,
      'source_system',lower(p_source_system),'consistent',v_consistent,'mismatches',v_mismatches,
      'evidence',coalesce(p_evidence,'{}'::jsonb)
    ),
    'processed',now(),v_project.id,p_project_key,v_project.project_name
  )
  on conflict(owner_key,source_type,external_id,event_type) do update set
    title=excluded.title,content=excluded.content,summary=excluded.summary,source_url=excluded.source_url,
    occurred_at=excluded.occurred_at,metadata=excluded.metadata,status='processed',processed_at=now(),
    project_id=excluded.project_id,project_key=excluded.project_key,project_name=excluded.project_name;

  return jsonb_build_object(
    'project_key',p_project_key,'version_authority',v_authority,
    'canonical_version',v_canonical,'consistent',v_consistent,'mismatches',v_mismatches
  );
end;
$$;

create or replace function public.memory_refresh_integrity(p_owner_key text default 'duilio')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
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
    p_owner_key,r.project_id,r.project_key,'authority_observation_stale','blocking','open',
    'authority_observation_stale:'||r.project_key||':'||r.version_authority,
    'La observación de la fuente autoritativa está vencida; debe refrescarse antes de declarar consistencia.',
    jsonb_build_object('version_authority',r.version_authority,'authority_ref',r.authority_ref,'observed_at',r.observed_at,'freshness_state',r.freshness_state),
    v_now,v_now
  from public.memory_integrity_source_requirements_v r
  where r.refresh_required=true and r.freshness_state='stale'
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='blocking',summary=excluded.summary,details=excluded.details,
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
    p_owner_key,p.id,p.project_key,'automatic_connector_not_connected','blocking','open',
    'automatic_connector_not_connected:'||p.project_key||':'||c.connector_type||':'||c.connector_name,
    'Un conector marcado automático no está conectado.',
    jsonb_build_object('connector_type',c.connector_type,'connector_name',c.connector_name,'status',c.status),
    v_now,v_now
  from public.memory_project_connectors c
  join public.memory_projects p on p.id=c.project_id
  where p.owner_key=p_owner_key and p.status='active'
    and c.automatic=true and c.status<>'connected'
  on conflict(owner_key,fingerprint) do update set
    status='open',severity='blocking',summary=excluded.summary,details=excluded.details,
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
$$;

insert into public.memory_learning_rules(
 owner_key,rule_key,statement,confidence,evidence_count,success_count,failure_count,status,provenance,created_at,updated_at
) values (
 'duilio','integrity_must_refresh_authoritative_sources_before_pass',
 'El proceso de integridad no puede declarar CONSISTENTE usando solamente observaciones cacheadas. Antes del gate debe recorrer todos los proyectos activos, refrescar en vivo las fuentes autoritativas configuradas y registrar las observaciones. La ausencia o antigüedad de evidencia autoritativa es una inconsistencia bloqueante hasta ser refrescada.',
 1.0,1,1,0,'active',
 jsonb_build_object('source','user_instruction','date','2026-09-20','incident','Supervisión no detectada por observaciones de versión ausentes'),
 now(),now()
)
on conflict(owner_key,rule_key) do update set
 statement=excluded.statement,confidence=1,status='active',
 evidence_count=memory_learning_rules.evidence_count+1,
 success_count=memory_learning_rules.success_count+1,
 provenance=excluded.provenance,updated_at=now();

-- ============================================================================
-- 20260921003137_classify_canonical_and_candidate_versions
-- ============================================================================
create or replace view public.memory_project_version_consistency_v
with (security_invoker = true) as
with base as (
  select
    p.id as project_id,
    p.project_key,
    p.project_name,
    lower(coalesce(
      nullif(p.metadata->>'software_version_authority',''),
      nullif(p.metadata->>'version_authority',''),
      'github'
    )) as version_authority
  from public.memory_projects p
),
canonical as (
  select
    b.project_id,
    b.project_key,
    b.project_name,
    b.version_authority,
    o.version as canonical_version,
    o.source_ref as authority_ref,
    o.observed_at as authority_observed_at
  from base b
  left join public.memory_project_version_observations o
    on o.project_id=b.project_id
   and o.source_system=b.version_authority
),
classified as (
  select
    o.*,
    case
      when o.source_system=c.version_authority then 'canonical'
      when coalesce(o.evidence->>'version_role','') in ('canonical','mirror') then o.evidence->>'version_role'
      when o.evidence ? 'candidate' or o.evidence ? 'documented_candidate' then 'candidate'
      else 'mirror'
    end as version_role
  from public.memory_project_version_observations o
  join canonical c on c.project_id=o.project_id
)
select
  c.project_id,
  c.project_key,
  c.project_name,
  c.canonical_version,
  c.authority_ref as github_ref,
  c.authority_observed_at as github_observed_at,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'source_system',o.source_system,
        'version',o.version,
        'source_ref',o.source_ref,
        'observed_at',o.observed_at,
        'version_role',o.version_role,
        'matches_authority',
          case when o.version_role in ('canonical','mirror')
               then o.version=c.canonical_version
               else null end
      )
      order by o.source_system
    ) filter (where o.id is not null),
    '[]'::jsonb
  ) as sources,
  case
    when c.canonical_version is null then false
    else coalesce(
      bool_and(o.version=c.canonical_version)
        filter (where o.id is not null and o.version_role in ('canonical','mirror')),
      true
    )
  end as consistent,
  c.version_authority
from canonical c
left join classified o on o.project_id=c.project_id
group by c.project_id,c.project_key,c.project_name,c.canonical_version,
         c.authority_ref,c.authority_observed_at,c.version_authority;

comment on view public.memory_project_version_consistency_v is
'Compara únicamente versiones canónicas o espejos. Conserva candidatas/documentales como evidencia sin tratarlas como drift de la versión canónica.';
