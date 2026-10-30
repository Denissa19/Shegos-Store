create table if not exists private.catalogo_cuentas_import_config (
  id boolean primary key default true check (id),
  search_url text not null,
  next_url text not null default '',
  actualizado_en timestamptz not null default now()
);

create table if not exists private.catalogo_cuentas_lzt_source (
  listing_id text primary key,
  cuenta_id uuid not null unique references public.catalogo_cuentas(id) on delete cascade,
  url_fuente text not null,
  costo_original_usd numeric(12,2) not null check (costo_original_usd >= 0),
  porcentaje_aumento numeric(5,2) not null default 47.62 check (porcentaje_aumento = 47.62),
  actualizado_en timestamptz not null default now()
);

alter table private.catalogo_cuentas_import_config enable row level security;
alter table private.catalogo_cuentas_lzt_source enable row level security;

create or replace function public.catalogo_lzt_import_state()
returns table(search_url text, next_url text)
language plpgsql security definer set search_path to 'pg_catalog'
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  return query select c.search_url, c.next_url
    from private.catalogo_cuentas_import_config c where c.id = true;
end;
$function$;

create or replace function public.catalogo_lzt_set_next_url(p_next_url text)
returns void
language plpgsql security definer set search_path to 'pg_catalog'
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  update private.catalogo_cuentas_import_config
  set next_url = coalesce(p_next_url, ''), actualizado_en = now()
  where id = true;
end;
$function$;

create or replace function public.catalogo_lzt_upsert_account(
  p_listing_id text,
  p_source_url text,
  p_ceo_id uuid,
  p_title text,
  p_skin_count integer,
  p_featured_skins text[],
  p_has_stw boolean,
  p_idle_days integer,
  p_source_cost numeric,
  p_image_paths text[],
  p_description text
)
returns uuid
language plpgsql security definer set search_path to 'pg_catalog'
as $function$
declare
  v_account_id uuid;
  v_status text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if not exists (select 1 from public.usuarios_roles r where r.id = p_ceo_id and r.rol = 'CEO' and r.activo) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_listing_id !~ '^[0-9]+$' or p_source_url !~ '^https://lzt\.market/[0-9]+/?$' then
    raise exception 'Referencia de publicación no válida';
  end if;
  if p_title is null or btrim(p_title) = '' or p_source_cost < 0 then
    raise exception 'Datos de cuenta incompletos';
  end if;

  select s.cuenta_id into v_account_id
  from private.catalogo_cuentas_lzt_source s where s.listing_id = p_listing_id;

  if v_account_id is null then
    insert into public.catalogo_cuentas
      (titulo,cantidad_skins,skins_destacadas,tiene_stw,dias_inactividad,precio_usd,descripcion,estado,creado_por,imagenes_skins)
    values
      (left(btrim(p_title),100),greatest(coalesce(p_skin_count,0),0),coalesce(p_featured_skins,'{}'),coalesce(p_has_stw,false),greatest(coalesce(p_idle_days,0),0),round(p_source_cost * 1.4762,2),coalesce(p_description,''),'disponible',p_ceo_id,coalesce(p_image_paths,'{}'))
    returning id into v_account_id;
  else
    select estado into v_status from public.catalogo_cuentas where id = v_account_id;
    update public.catalogo_cuentas set
      titulo=left(btrim(p_title),100),cantidad_skins=greatest(coalesce(p_skin_count,0),0),
      skins_destacadas=coalesce(p_featured_skins,'{}'),tiene_stw=coalesce(p_has_stw,false),
      dias_inactividad=greatest(coalesce(p_idle_days,0),0),precio_usd=round(p_source_cost * 1.4762,2),
      descripcion=coalesce(p_description,''),estado=case when v_status='vendida' then v_status else 'disponible' end,
      imagenes_skins=coalesce(p_image_paths,'{}'),actualizado_en=now()
    where id=v_account_id;
  end if;

  insert into private.catalogo_cuentas_detalle
    (cuenta_id,referencia_interna,costo_adquisicion_usd,notas_internas,actualizado_en)
  values (v_account_id,p_source_url,p_source_cost,'Importada desde enlace público de inventario.',now())
  on conflict (cuenta_id) do update set
    referencia_interna=excluded.referencia_interna,
    costo_adquisicion_usd=excluded.costo_adquisicion_usd,
    actualizado_en=now();

  insert into private.catalogo_cuentas_lzt_source
    (listing_id,cuenta_id,url_fuente,costo_original_usd,porcentaje_aumento,actualizado_en)
  values (p_listing_id,v_account_id,p_source_url,p_source_cost,47.62,now())
  on conflict (listing_id) do update set
    cuenta_id=excluded.cuenta_id,url_fuente=excluded.url_fuente,
    costo_original_usd=excluded.costo_original_usd,porcentaje_aumento=47.62,actualizado_en=now();

  return v_account_id;
end;
$function$;

revoke all on function public.catalogo_lzt_import_state() from public, anon, authenticated;
revoke all on function public.catalogo_lzt_set_next_url(text) from public, anon, authenticated;
revoke all on function public.catalogo_lzt_upsert_account(text,text,uuid,text,integer,text[],boolean,integer,numeric,text[],text) from public, anon, authenticated;
grant execute on function public.catalogo_lzt_import_state() to service_role;
grant execute on function public.catalogo_lzt_set_next_url(text) to service_role;
grant execute on function public.catalogo_lzt_upsert_account(text,text,uuid,text,integer,text[],boolean,integer,numeric,text[],text) to service_role;

