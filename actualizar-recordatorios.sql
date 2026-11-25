-- Mis Encargos: los recordatorios deben seguir activos en "Terminado"
-- y detenerse únicamente cuando el estado sea "Finalizado".
-- Ejecutar una sola vez en Supabase > SQL Editor.

create or replace function public.generate_due_notifications()
returns void language plpgsql security definer set search_path=public
as $$
begin
 insert into public.notifications(workspace_id,note_id,user_id,notification_type,title,body)
 select n.workspace_id,n.id,m.user_id,'due_tomorrow','Entrega mañana',n.title
 from public.notes n join public.workspace_members m on m.workspace_id=n.workspace_id
 where n.status <> 'Finalizado' and n.due_date=current_date+1
 on conflict do nothing;

 insert into public.notifications(workspace_id,note_id,user_id,notification_type,title,body)
 select n.workspace_id,n.id,m.user_id,'due_today','Entrega hoy',n.title
 from public.notes n join public.workspace_members m on m.workspace_id=n.workspace_id
 where n.status <> 'Finalizado' and n.due_date=current_date
 on conflict do nothing;

 insert into public.notifications(workspace_id,note_id,user_id,notification_type,title,body)
 select n.workspace_id,n.id,m.user_id,'overdue','Encargo vencido',n.title
 from public.notes n join public.workspace_members m on m.workspace_id=n.workspace_id
 where n.status <> 'Finalizado' and n.due_date<current_date
 on conflict do nothing;
end;
$$;
