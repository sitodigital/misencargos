-- MIS ENCARGOS — esquema inicial Supabase
-- Ejecuta todo este archivo en Supabase > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.workspaces (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 invite_code text not null unique default upper(substr(encode(gen_random_bytes(8),'hex'),1,8)),
 created_by uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
create table if not exists public.workspace_members (
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 joined_at timestamptz not null default now(),
 primary key(workspace_id,user_id)
);
create table if not exists public.notes (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 created_by uuid not null references auth.users(id),
 title text not null,
 description text default '',
 status text not null default 'Nuevo' check(status in ('Nuevo','En proceso','Esperando respuesta','Terminado')),
 priority text not null default 'Normal' check(priority in ('Baja','Normal','Urgente')),
 due_date date not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.attachments (
 id uuid primary key default gen_random_uuid(),
 note_id uuid not null references public.notes(id) on delete cascade,
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 uploaded_by uuid not null references auth.users(id),
 file_name text not null,
 storage_path text not null,
 public_url text not null,
 mime_type text,
 size_bytes bigint,
 created_at timestamptz not null default now()
);
create table if not exists public.comments (
 id uuid primary key default gen_random_uuid(),
 note_id uuid not null references public.notes(id) on delete cascade,
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 user_id uuid not null references auth.users(id),
 body text not null check(length(body) between 1 and 5000),
 created_at timestamptz not null default now()
);

create or replace function public.is_workspace_member(wid uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.workspace_members m where m.workspace_id=wid and m.user_id=auth.uid()); $$;

create or replace function public.create_workspace(workspace_name text)
returns public.workspaces language plpgsql security definer set search_path=public
as $$
declare w public.workspaces;
begin
 if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
 if exists(select 1 from public.workspace_members where user_id=auth.uid()) then raise exception 'Tu cuenta ya pertenece a un espacio'; end if;
 insert into public.workspaces(name,created_by) values (left(coalesce(nullif(trim(workspace_name),''),'Nuestro espacio'),80),auth.uid()) returning * into w;
 insert into public.workspace_members(workspace_id,user_id) values(w.id,auth.uid());
 return w;
end; $$;

create or replace function public.join_workspace(code_input text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare w public.workspaces;
begin
 if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
 if exists(select 1 from public.workspace_members where user_id=auth.uid()) then raise exception 'Tu cuenta ya pertenece a un espacio'; end if;
 select * into w from public.workspaces where invite_code=upper(trim(code_input));
 if w.id is null then raise exception 'Código de invitación no válido'; end if;
 insert into public.workspace_members(workspace_id,user_id) values(w.id,auth.uid());
 return w.id;
end; $$;

alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.notes enable row level security;
alter table public.attachments enable row level security;
alter table public.comments enable row level security;

create policy "members read workspace" on public.workspaces for select to authenticated using(public.is_workspace_member(id));
create policy "members read memberships" on public.workspace_members for select to authenticated using(public.is_workspace_member(workspace_id));
create policy "members read notes" on public.notes for select to authenticated using(public.is_workspace_member(workspace_id));
create policy "members create notes" on public.notes for insert to authenticated with check(public.is_workspace_member(workspace_id) and created_by=auth.uid());
create policy "members update notes" on public.notes for update to authenticated using(public.is_workspace_member(workspace_id)) with check(public.is_workspace_member(workspace_id));
create policy "members delete notes" on public.notes for delete to authenticated using(public.is_workspace_member(workspace_id));
create policy "members read attachments" on public.attachments for select to authenticated using(public.is_workspace_member(workspace_id));
create policy "members add attachments" on public.attachments for insert to authenticated with check(public.is_workspace_member(workspace_id) and uploaded_by=auth.uid());
create policy "members remove attachments" on public.attachments for delete to authenticated using(public.is_workspace_member(workspace_id));
create policy "members read comments" on public.comments for select to authenticated using(public.is_workspace_member(workspace_id));
create policy "members add comments" on public.comments for insert to authenticated with check(public.is_workspace_member(workspace_id) and user_id=auth.uid());
create policy "members delete own comments" on public.comments for delete to authenticated using(user_id=auth.uid());



-- Fecha de entrega: permite actualizar instalaciones que ya tenían la tabla notes.
alter table public.notes add column if not exists due_date date;
update public.notes set due_date=current_date where due_date is null;
alter table public.notes alter column due_date set not null;

create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(),
 workspace_id uuid not null references public.workspaces(id) on delete cascade,
 note_id uuid references public.notes(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 notification_type text not null check(notification_type in ('new_note','due_tomorrow','due_today','overdue')),
 title text not null,
 body text not null default '',
 read_at timestamptz,
 created_at timestamptz not null default now()
);
create unique index if not exists notifications_once_per_note_type_user
 on public.notifications(note_id,user_id,notification_type) where note_id is not null;
create index if not exists notifications_user_unread
 on public.notifications(user_id,created_at desc) where read_at is null;
alter table public.notifications enable row level security;
drop policy if exists "users read own notifications" on public.notifications;
create policy "users read own notifications" on public.notifications
 for select to authenticated using(user_id=auth.uid() and public.is_workspace_member(workspace_id));
drop policy if exists "users update own notifications" on public.notifications;
create policy "users update own notifications" on public.notifications
 for update to authenticated using(user_id=auth.uid() and public.is_workspace_member(workspace_id))
 with check(user_id=auth.uid() and public.is_workspace_member(workspace_id));

create or replace function public.notify_new_note()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.notifications(workspace_id,note_id,user_id,notification_type,title,body)
 select new.workspace_id,new.id,m.user_id,'new_note','Nuevo encargo',new.title
 from public.workspace_members m
 where m.workspace_id=new.workspace_id and m.user_id<>new.created_by
 on conflict do nothing;
 return new;
end; $$;
drop trigger if exists trg_notify_new_note on public.notes;
create trigger trg_notify_new_note after insert on public.notes
 for each row execute function public.notify_new_note();

create or replace function public.generate_due_notifications()
returns void language plpgsql security definer set search_path=public
as $$
begin
 insert into public.notifications(workspace_id,note_id,user_id,notification_type,title,body)
 select n.workspace_id,n.id,m.user_id,'due_tomorrow','Entrega mañana',n.title
 from public.notes n join public.workspace_members m on m.workspace_id=n.workspace_id
 where n.status<>'Terminado' and n.due_date=current_date+1 on conflict do nothing;
 insert into public.notifications(workspace_id,note_id,user_id,notification_type,title,body)
 select n.workspace_id,n.id,m.user_id,'due_today','Entrega hoy',n.title
 from public.notes n join public.workspace_members m on m.workspace_id=n.workspace_id
 where n.status<>'Terminado' and n.due_date=current_date on conflict do nothing;
 insert into public.notifications(workspace_id,note_id,user_id,notification_type,title,body)
 select n.workspace_id,n.id,m.user_id,'overdue','Encargo vencido',n.title
 from public.notes n join public.workspace_members m on m.workspace_id=n.workspace_id
 where n.status<>'Terminado' and n.due_date<current_date on conflict do nothing;
end; $$;

create extension if not exists pg_cron with schema pg_catalog;
select cron.unschedule(jobid) from cron.job where jobname='mis-encargos-due-reminders';
select cron.schedule('mis-encargos-due-reminders','0 * * * *','select public.generate_due_notifications()');
do $$ begin
 alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null;
end $$;

-- Bucket privado para archivos. No se exponen públicamente.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('encargos','encargos',false,15728640,
 array['image/jpeg','image/png','image/webp','image/gif','application/pdf',
 'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
 'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
 'text/plain','application/zip','application/octet-stream',
 'audio/webm','audio/ogg','audio/mp4','audio/mpeg','audio/wav','audio/x-wav'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

create policy "workspace members read files" on storage.objects for select to authenticated
using(bucket_id='encargos' and public.is_workspace_member(((storage.foldername(name))[1])::uuid));
create policy "workspace members upload files" on storage.objects for insert to authenticated
with check(bucket_id='encargos' and public.is_workspace_member(((storage.foldername(name))[1])::uuid));
create policy "workspace members delete files" on storage.objects for delete to authenticated
using(bucket_id='encargos' and public.is_workspace_member(((storage.foldername(name))[1])::uuid));

-- Realtime para cambios en notas. Ejecutar si la tabla aún no está publicada:
alter publication supabase_realtime add table public.notes;
