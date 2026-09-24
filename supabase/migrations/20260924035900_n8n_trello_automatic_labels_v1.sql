-- Memoria Duilio 0.6.5 — Trello label automation with n8n.
-- Re-run safely; no credential or token values stored in the migration.
-- Requires existing universal intake functions from earlier migrations.

CREATE OR REPLACE FUNCTION public.memory_projects_default_trello_presentation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
 v_name text;
 v_colors text[]:=array['blue','green','orange','purple','sky','lime','pink','red','yellow','black'];
 v_color text;
begin
 v_name:=coalesce(nullif(btrim(new.canonical_name),''),nullif(btrim(new.project_name),''),new.project_key);
 if nullif(coalesce(new.metadata->'trello'->>'label_name',''),'') is null then
   v_color:=v_colors[(get_byte(decode(md5(lower(new.project_key)),'hex'),0) % array_length(v_colors,1))+1];
   new.metadata:=coalesce(new.metadata,'{}'::jsonb)
     ||jsonb_build_object('trello',jsonb_build_object(
         'title_prefix',v_name,'label_name',v_name,'label_color',v_color,
         'label_provisioning','pending','auto_color_algorithm','md5_first_byte_palette_v1'));
 end if;
 return new;
end;
$function$

drop trigger if exists trg_memory_projects_default_trello_presentation on public.memory_projects;
create trigger trg_memory_projects_default_trello_presentation
before insert on public.memory_projects
for each row execute function public.memory_projects_default_trello_presentation();

select public.memory_ingest_project_event(
 'trello','workspace:5fa44242375608633d50f8a2','project.discovered',
 'project:viaje-india','card','https://trello.com/c/mxzvrGA2','Viaje India','viaje-india','Viaje India',
 jsonb_build_object('origin','existing_trello_card','requested_by','duilio',
   'trello_title_prefix','Viaje India','trello_label_name','Viaje India','trello_color','green')
) where not exists(
 select 1 from public.memory_projects where owner_key='duilio' and project_key='viaje-india' and status='active'
);

select public.memory_ingest_project_event(
 'trello','workspace:5fa44242375608633d50f8a2','project.discovered',
 'project:whatsapp-pagos-fifo','card','https://trello.com/c/QOKhAfdr','WhatsApp pagos FIFO','whatsapp-pagos-fifo','WhatsApp pagos FIFO',
 jsonb_build_object('origin','existing_trello_card','requested_by','duilio',
   'trello_title_prefix','WhatsApp pagos FIFO','trello_label_name','WhatsApp pagos FIFO','trello_color','lime')
) where not exists(
 select 1 from public.memory_projects where owner_key='duilio' and project_key='whatsapp-pagos-fifo' and status='active'
);

select public.memory_ingest_project_event(
 'trello','workspace:5fa44242375608633d50f8a2','project.discovered',
 'project:capacitacion-ia-estaciones','card','https://trello.com/c/T2xmrKV5','Capacitación IA — Estaciones de Servicio','capacitacion-ia-estaciones','Capacitación IA — Estaciones de Servicio',
 jsonb_build_object('origin','existing_trello_card','requested_by','duilio',
   'trello_title_prefix','Capacitación IA — Estaciones de Servicio','trello_label_name','Capacitación IA','trello_color','blue_light')
) where not exists(
 select 1 from public.memory_projects where owner_key='duilio' and project_key='capacitacion-ia-estaciones' and status='active'
);

with v(project_key,title_prefix,label_name,label_color,label_id,parent) as (
values
('viaje-india','Viaje India','Viaje India','green','6aa35638b2a5a021d29b654c',null),
('whatsapp-pagos-fifo','WhatsApp pagos FIFO','WhatsApp pagos FIFO','lime',null,null),
('capacitacion-ia-estaciones','Capacitación IA','Capacitación IA','blue_light',null,null),
('capitan-rodolfo','Capitán Rodolfo','Capitán Rodolfo','orange_light',null,'doinglio'),
('ruben','Ruben','Ruben','purple_light',null,'doinglio'),
('conexion','Proyecto Conexión','Proyecto Conexión','sky',null,null)
)
update public.memory_projects p
set metadata=coalesce(p.metadata,'{}'::jsonb) || jsonb_build_object(
 'trello',jsonb_strip_nulls(coalesce(p.metadata->'trello','{}'::jsonb)||
 jsonb_build_object(
   'title_prefix',v.title_prefix,'label_name',v.label_name,
   'label_color',v.label_color,
   'label_id',coalesce(p.metadata->'trello'->>'label_id',
     case when v.label_id is null then null else
      'ari:cloud:trello::label/workspace/5fa44242375608633d50f8a2/'||v.label_id end),
   'inherited_from',v.parent,
   'label_provisioning',coalesce(p.metadata->'trello'->>'label_provisioning',
     case when v.label_id is null then 'pending' else 'already_exists' end)
 ))),updated_at=clock_timestamp()
from v where p.project_key=v.project_key and p.owner_key='duilio' and p.status='active';

CREATE OR REPLACE FUNCTION public.memory_verify_n8n_label_bootstrap_token(p_token text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'extensions', 'pg_temp'
AS $function$
select coalesce(
 (select p_token is not null and
         extensions.digest(convert_to(p_token,'UTF8'),'sha256')=
         extensions.digest(convert_to(decrypted_secret,'UTF8'),'sha256')
  from vault.decrypted_secrets
  where name='memory_duilio_sync_token' limit 1),
 false);
$function$

revoke execute on function public.memory_verify_n8n_label_bootstrap_token(text) from public,anon,authenticated;
grant execute on function public.memory_verify_n8n_label_bootstrap_token(text) to service_role;

CREATE OR REPLACE FUNCTION public.memory_trello_label_manifest()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
select jsonb_build_object(
 'projects',coalesce(jsonb_agg(jsonb_build_object(
   'project_key',p.project_key,
   'title_prefix',p.metadata->'trello'->>'title_prefix',
   'label_name',p.metadata->'trello'->>'label_name',
   'label_color',p.metadata->'trello'->>'label_color',
   'label_id',p.metadata->'trello'->>'label_id',
   'inherited_from',p.metadata->'trello'->>'inherited_from'
 ) order by p.project_key),'[]'::jsonb),
 'board_id','6aa35638b2a5a021d29b646b',
 'generated_at',now()
)
from public.memory_projects p
where p.owner_key='duilio' and p.status='active'
 and nullif(p.metadata->'trello'->>'label_name','') is not null;
$function$

revoke execute on function public.memory_trello_label_manifest() from public,anon,authenticated;
grant execute on function public.memory_trello_label_manifest() to service_role;

CREATE OR REPLACE FUNCTION public.memory_trello_register_label(p_label_name text, p_label_id text, p_color text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_count integer;
begin
 if nullif(btrim(p_label_name),'') is null
   or p_label_id !~ '^[a-fA-F0-9]{24}$'
   or nullif(btrim(p_color),'') is null then
   return jsonb_build_object('ok',false,'reason','invalid_label');
 end if;
 update public.memory_projects p
 set metadata=coalesce(p.metadata,'{}'::jsonb) || jsonb_build_object(
   'trello',coalesce(p.metadata->'trello','{}'::jsonb)||jsonb_build_object(
     'label_id','ari:cloud:trello::label/workspace/5fa44242375608633d50f8a2/'||lower(p_label_id),
     'label_color_actual',p_color,
     'label_provisioning','created',
     'label_last_verified_at',clock_timestamp()
   )
 ),updated_at=clock_timestamp()
 where p.owner_key='duilio' and p.status='active'
   and lower(p.metadata->'trello'->>'label_name')=lower(btrim(p_label_name));
 get diagnostics v_count=row_count;
 return jsonb_build_object('ok',v_count>0,'updated',v_count,'label_name',p_label_name,'label_id',p_label_id);
end $function$

revoke execute on function public.memory_trello_register_label(text,text,text) from public,anon,authenticated;
grant execute on function public.memory_trello_register_label(text,text,text) to service_role;

create table if not exists public.memory_n8n_workflow_specs(
 spec_key text primary key,workflow_name text not null,spec jsonb not null,
 external_workflow_id text,status text not null default 'draft',
 result jsonb not null default '{}'::jsonb,updated_at timestamptz not null default now()
);
alter table public.memory_n8n_workflow_specs enable row level security;
drop policy if exists memory_n8n_workflow_specs_backend_only on public.memory_n8n_workflow_specs;
create policy memory_n8n_workflow_specs_backend_only
on public.memory_n8n_workflow_specs for all to anon,authenticated using(false) with check(false);
revoke all on public.memory_n8n_workflow_specs from public,anon,authenticated;
grant select,insert,update on public.memory_n8n_workflow_specs to service_role;

-- Intentionally do not overwrite the LIVE workflow spec or credential IDs.
-- Exported portable n8n spec lives under /n8n with credential placeholders.
