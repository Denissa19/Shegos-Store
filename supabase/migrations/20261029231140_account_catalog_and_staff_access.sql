create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.catalogo_cuentas (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  cantidad_skins integer not null default 0 check (cantidad_skins >= 0),
  skins_destacadas text[] not null default '{}',
  tiene_stw boolean not null default false,
  dias_inactividad integer not null default 0 check (dias_inactividad >= 0),
  precio_usd numeric(10,2) not null check (precio_usd >= 0),
  descripcion text not null default '',
  estado text not null default 'disponible' check (estado in ('disponible','reservada','vendida')),
  creado_por uuid not null default auth.uid() references auth.users(id),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
alter table public.catalogo_cuentas enable row level security;
revoke all on public.catalogo_cuentas from anon, public;
grant select on public.catalogo_cuentas to authenticated;
drop policy if exists catalogo_cuentas_staff_select on public.catalogo_cuentas;
create policy catalogo_cuentas_staff_select on public.catalogo_cuentas
for select to authenticated
using (
  (select public.es_staff())
  and ((select public.rol_actual()) = 'CEO' or estado = 'disponible')
);

create table if not exists private.catalogo_cuentas_detalle (
  cuenta_id uuid primary key references public.catalogo_cuentas(id) on delete cascade,
  referencia_interna text not null default '',
  costo_adquisicion_usd numeric(10,2) check (costo_adquisicion_usd is null or costo_adquisicion_usd >= 0),
  notas_internas text not null default '',
  actualizado_en timestamptz not null default now()
);
alter table private.catalogo_cuentas_detalle enable row level security;
revoke all on private.catalogo_cuentas_detalle from public, anon, authenticated;

create or replace function public.guardar_cuenta_catalogo(
  p_id uuid,p_titulo text,p_cantidad_skins integer,p_skins_destacadas text[],
  p_tiene_stw boolean,p_dias_inactividad integer,p_precio_usd numeric,
  p_descripcion text,p_estado text,p_referencia_interna text,
  p_costo_adquisicion_usd numeric,p_notas_internas text
) returns uuid language plpgsql security definer set search_path=pg_catalog
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.es_staff() or public.rol_actual() <> 'CEO' then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_titulo is null or length(pg_catalog.btrim(p_titulo))=0 then raise exception 'El título es obligatorio'; end if;
  if p_estado not in ('disponible','reservada','vendida') then raise exception 'Estado no válido'; end if;
  if p_id is null then
    insert into public.catalogo_cuentas(titulo,cantidad_skins,skins_destacadas,tiene_stw,dias_inactividad,precio_usd,descripcion,estado,creado_por)
    values(pg_catalog.btrim(p_titulo),p_cantidad_skins,coalesce(p_skins_destacadas,'{}'),p_tiene_stw,p_dias_inactividad,p_precio_usd,coalesce(p_descripcion,''),p_estado,auth.uid())
    returning id into v_id;
  else
    update public.catalogo_cuentas set titulo=pg_catalog.btrim(p_titulo),cantidad_skins=p_cantidad_skins,
      skins_destacadas=coalesce(p_skins_destacadas,'{}'),tiene_stw=p_tiene_stw,
      dias_inactividad=p_dias_inactividad,precio_usd=p_precio_usd,descripcion=coalesce(p_descripcion,''),
      estado=p_estado,actualizado_en=now()
    where id=p_id returning id into v_id;
    if v_id is null then raise exception 'Cuenta no encontrada'; end if;
  end if;
  insert into private.catalogo_cuentas_detalle(cuenta_id,referencia_interna,costo_adquisicion_usd,notas_internas,actualizado_en)
  values(v_id,coalesce(p_referencia_interna,''),p_costo_adquisicion_usd,coalesce(p_notas_internas,''),now())
  on conflict(cuenta_id) do update set referencia_interna=excluded.referencia_interna,
    costo_adquisicion_usd=excluded.costo_adquisicion_usd,notas_internas=excluded.notas_internas,actualizado_en=now();
  return v_id;
end;
$$;
revoke all on function public.guardar_cuenta_catalogo(uuid,text,integer,text[],boolean,integer,numeric,text,text,text,numeric,text) from public,anon;
grant execute on function public.guardar_cuenta_catalogo(uuid,text,integer,text[],boolean,integer,numeric,text,text,text,numeric,text) to authenticated;

create or replace function public.leer_detalle_catalogo_cuenta(p_id uuid)
returns table(referencia_interna text,costo_adquisicion_usd numeric,notas_internas text)
language plpgsql security definer set search_path=pg_catalog as $$
begin
  if auth.uid() is null or not public.es_staff() or public.rol_actual() <> 'CEO' then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  return query select d.referencia_interna,d.costo_adquisicion_usd,d.notas_internas
    from private.catalogo_cuentas_detalle d where d.cuenta_id=p_id;
end;
$$;
revoke all on function public.leer_detalle_catalogo_cuenta(uuid) from public,anon;
grant execute on function public.leer_detalle_catalogo_cuenta(uuid) to authenticated;

drop policy if exists catalogo_productos_staff_all on public.catalogo_productos;
create policy catalogo_productos_staff_all on public.catalogo_productos
for all to authenticated using ((select public.es_staff())) with check ((select public.es_staff()));
grant select,insert,update,delete on public.catalogo_productos to authenticated;
revoke all on public.catalogo_productos from anon;

insert into public.usuarios_roles(id,nombre_completo,rol,activo)
select u.id,'Admin','Admin'::public.rol_usuario,true from auth.users u
where lower(u.email)=lower('carlos.arteaga.milan.2008@gmail.com')
on conflict(id) do update set nombre_completo=excluded.nombre_completo,rol=excluded.rol,activo=true;

create index if not exists idx_catalogo_cuentas_estado on public.catalogo_cuentas(estado);
create index if not exists idx_catalogo_cuentas_tiene_stw on public.catalogo_cuentas(tiene_stw);
