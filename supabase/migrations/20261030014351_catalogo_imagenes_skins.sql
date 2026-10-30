alter table public.catalogo_cuentas
  add column if not exists imagenes_skins text[] not null default '{}';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('catalogo-skins', 'catalogo-skins', false, 5242880, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists catalogo_skins_staff_read on storage.objects;
create policy catalogo_skins_staff_read
  on storage.objects for select to authenticated
  using (bucket_id = 'catalogo-skins' and public.es_staff());

drop policy if exists catalogo_skins_ceo_insert on storage.objects;
create policy catalogo_skins_ceo_insert
  on storage.objects for insert to authenticated
  with check (bucket_id = 'catalogo-skins' and public.es_staff() and public.rol_actual() = 'CEO');

drop policy if exists catalogo_skins_ceo_update on storage.objects;
create policy catalogo_skins_ceo_update
  on storage.objects for update to authenticated
  using (bucket_id = 'catalogo-skins' and public.es_staff() and public.rol_actual() = 'CEO')
  with check (bucket_id = 'catalogo-skins' and public.es_staff() and public.rol_actual() = 'CEO');

drop policy if exists catalogo_skins_ceo_delete on storage.objects;
create policy catalogo_skins_ceo_delete
  on storage.objects for delete to authenticated
  using (bucket_id = 'catalogo-skins' and public.es_staff() and public.rol_actual() = 'CEO');

create or replace function public.guardar_imagenes_catalogo_cuenta(p_id uuid, p_imagenes_skins text[])
returns void
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
begin
  if auth.uid() is null or not public.es_staff() or public.rol_actual() <> 'CEO' then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update public.catalogo_cuentas
  set imagenes_skins = coalesce(p_imagenes_skins, '{}'), actualizado_en = now()
  where id = p_id;

  if not found then raise exception 'Cuenta no encontrada'; end if;
end;
$function$;

grant execute on function public.guardar_imagenes_catalogo_cuenta(uuid, text[]) to authenticated;

