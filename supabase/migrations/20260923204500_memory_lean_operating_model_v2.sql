-- Memoria Duilio Lean 2.0
-- Simplifica el camino operativo sin eliminar capacidades históricas.

update public.memory_source_of_truth
set
  primary_role = case system_key
    when 'memoria-duilio' then 'contexto y orquestación'
    when 'supabase' then 'estado técnico y memoria'
    when 'trello' then 'pendientes y estado de tareas'
    when 'n8n' then 'ejecución automática'
    when 'github' then 'código y versiones'
    when 'notion' then 'documentación'
    when 'whatsapp' then 'notificaciones'
    else primary_role end,
  authoritative_for = case system_key
    when 'memoria-duilio' then array['intencion','contexto','routing']::text[]
    when 'supabase' then array['proyectos','memoria','ejecucion_real','evidencia','auditoria']::text[]
    when 'trello' then array['estado_tarea','proxima_accion','bloqueo_operativo']::text[]
    when 'n8n' then array['workflow','webhook','cron','integracion_automatica']::text[]
    when 'github' then array['codigo','version','commit','rama','release']::text[]
    when 'notion' then array['documentacion','especificacion','historial_narrativo']::text[]
    when 'whatsapp' then array['notificacion','aviso']::text[]
    else authoritative_for end,
  write_policy = case system_key
    when 'memoria-duilio' then 'Coordina y recupera contexto; no duplica la verdad primaria de otras herramientas.'
    when 'supabase' then 'Guarda proyecto, memoria, ejecución y evidencia verificable.'
    when 'trello' then 'Muestra pendientes y transición operativa de tareas.'
    when 'n8n' then 'Ejecuta automatizaciones y devuelve resultado/evidencia a Supabase.'
    when 'github' then 'Toda versión de código debe apuntar a commit o release verificable.'
    when 'notion' then 'Documenta; no gobierna ejecución, pendientes ni versión.'
    when 'whatsapp' then 'Notifica; no funciona como repositorio de memoria ni tareas.'
    else write_policy end,
  metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
    'lean_model', true,
    'lean_model_version', '2.0',
    'core_runtime', system_key in ('memoria-duilio','supabase','trello','n8n','github'),
    'support_only', system_key in ('notion','whatsapp')
  ),
  updated_at = now()
where system_key in ('memoria-duilio','supabase','trello','n8n','github','notion','whatsapp');

create or replace function public.memory_home_payload_v1()
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
with
sources as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'system_key',s.system_key,
    'name',s.display_name,
    'role',s.primary_role,
    'authoritative_for',s.authoritative_for,
    'write_policy',s.write_policy,
    'core_runtime',coalesce((s.metadata->>'core_runtime')::boolean,false),
    'support_only',coalesce((s.metadata->>'support_only')::boolean,false)
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
learning as (
  select jsonb_build_object(
    'active',(select count(*) from public.memory_knowledge where owner_key='duilio' and status='active'),
    'candidate',(select count(*) from public.memory_knowledge where owner_key='duilio' and status='candidate'),
    'deprecated',(select count(*) from public.memory_knowledge where owner_key='duilio' and status='deprecated'),
    'pending_experiences',(select count(*) from public.memory_experiences where owner_key='duilio' and learning_status='pending'),
    'observed_experiences',(select count(*) from public.memory_experiences where owner_key='duilio' and learning_status='observed'),
    'learned_experiences',(select count(*) from public.memory_experiences where owner_key='duilio' and learning_status='learned'),
    'recent',coalesce((
      select jsonb_agg(jsonb_build_object(
        'title',k.title,'statement',k.statement,'status',k.status,'type',k.knowledge_type,
        'confidence',k.confidence,'evidence_count',k.evidence_count,'updated_at',k.updated_at
      ) order by k.updated_at desc)
      from (
        select *
        from public.memory_knowledge
        where owner_key='duilio' and status in ('active','candidate')
        order by updated_at desc
        limit 8
      ) k
    ),'[]'::jsonb)
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
  'operating_model_version','2.0-lean',
  'core',jsonb_build_array('estado','pendientes','ejecucion','aprendizaje'),
  'today',jsonb_build_object(
    'counts',(select j from counts),
    'priority_items',(select j from today_cards),
    'trello_sync',coalesce((select j from sync_health),'{}'::jsonb)
  ),
  'projects',(select j from projects),
  'running',(select j from running),
  'waiting_for_you',(select j from waiting),
  'learning',(select j from learning),
  'source_of_truth',(select j from sources)
);
$function$;

comment on function public.memory_home_payload_v1() is
'Payload operativo Lean 2.0: estado, pendientes, ejecucion y aprendizaje. Grafos y control avanzado quedan fuera del camino normal.';
