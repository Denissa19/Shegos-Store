begin;

alter table public.ventas
  add column if not exists cupon_codigo text,
  add column if not exists descuento_porcentaje numeric(5,2),
  add column if not exists descuento_usd numeric(12,2),
  add column if not exists precio_original_usd numeric(12,2);

create table if not exists public.cupones_descuento (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  categoria text not null check (categoria in ('satisfaccion','volumen','fidelidad','otro')),
  porcentaje numeric(5,2) not null check (porcentaje between 5 and 10),
  compra_minima_mxn numeric(12,2) not null default 600 check (compra_minima_mxn >= 600),
  creador_email text not null,
  creador_rol text not null check (creador_rol in ('CEO','ADMIN')),
  plantilla text not null check (plantilla in ('deni','maidas')),
  cliente text,
  motivo text,
  usos_maximos integer not null default 1 check (usos_maximos = 1),
  usos integer not null default 0 check (usos between 0 and usos_maximos),
  estado text not null default 'activo' check (estado in ('activo','usado','anulado')),
  creado_en timestamptz not null default now(),
  expira_en timestamptz not null default (now() + interval '30 days'),
  actualizado_en timestamptz not null default now()
);

create table if not exists public.cupones_redenciones (
  id uuid primary key default gen_random_uuid(),
  cupon_id uuid not null references public.cupones_descuento(id),
  codigo text not null,
  venta_id text not null,
  cliente text,
  subtotal_usd numeric(12,2) not null,
  descuento_usd numeric(12,2) not null,
  creado_en timestamptz not null default now(),
  unique (cupon_id, venta_id)
);

create index if not exists cupones_descuento_estado_expira_idx
  on public.cupones_descuento (estado, expira_en);
create index if not exists cupones_redenciones_codigo_idx
  on public.cupones_redenciones (codigo, creado_en desc);

alter table public.cupones_descuento enable row level security;
alter table public.cupones_redenciones enable row level security;

drop policy if exists cupones_descuento_equipo_select on public.cupones_descuento;
create policy cupones_descuento_equipo_select on public.cupones_descuento
  for select to authenticated
  using (lower(coalesce(auth.jwt() ->> 'email','')) in ('codedenissa19@gmail.com','carlos.arteaga.milan.2008@gmail.com'));

drop policy if exists cupones_descuento_equipo_update on public.cupones_descuento;
create policy cupones_descuento_equipo_update on public.cupones_descuento
  for update to authenticated
  using (lower(coalesce(auth.jwt() ->> 'email','')) in ('codedenissa19@gmail.com','carlos.arteaga.milan.2008@gmail.com'))
  with check (lower(coalesce(auth.jwt() ->> 'email','')) in ('codedenissa19@gmail.com','carlos.arteaga.milan.2008@gmail.com'));

drop policy if exists cupones_redenciones_equipo_select on public.cupones_redenciones;
create policy cupones_redenciones_equipo_select on public.cupones_redenciones
  for select to authenticated
  using (lower(coalesce(auth.jwt() ->> 'email','')) in ('codedenissa19@gmail.com','carlos.arteaga.milan.2008@gmail.com'));

revoke all on public.cupones_descuento from anon, public;
revoke all on public.cupones_redenciones from anon, public;
grant select, update on public.cupones_descuento to authenticated;
grant select on public.cupones_redenciones to authenticated;

create or replace function public.crear_cupon_descuento(
  p_codigo text,
  p_categoria text,
  p_porcentaje numeric,
  p_compra_minima_mxn numeric default 600,
  p_cliente text default null,
  p_motivo text default null
)
returns public.cupones_descuento
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email',''));
  v_rol text;
  v_plantilla text;
  v_row public.cupones_descuento;
begin
  if v_email = 'codedenissa19@gmail.com' then
    v_rol := 'CEO'; v_plantilla := 'deni';
  elsif v_email = 'carlos.arteaga.milan.2008@gmail.com' then
    v_rol := 'ADMIN'; v_plantilla := 'maidas';
  else
    raise exception 'No tienes permiso para generar cupones.' using errcode = '42501';
  end if;
  if coalesce(p_codigo,'') !~ '^[A-Z0-9-]{6,24}$' then
    raise exception 'El código no tiene un formato válido.' using errcode = '22023';
  end if;
  if p_categoria not in ('satisfaccion','volumen','fidelidad','otro') then
    raise exception 'Selecciona una categoría válida.' using errcode = '22023';
  end if;
  if p_porcentaje < 5 or p_porcentaje > 10 then
    raise exception 'El descuento debe estar entre 5%% y 10%%.' using errcode = '22023';
  end if;
  if p_compra_minima_mxn < 600 then
    raise exception 'La compra mínima debe ser de al menos 600 MXN.' using errcode = '22023';
  end if;

  insert into public.cupones_descuento
    (codigo,categoria,porcentaje,compra_minima_mxn,creador_email,creador_rol,plantilla,cliente,motivo)
  values
    (upper(p_codigo),p_categoria,p_porcentaje,p_compra_minima_mxn,v_email,v_rol,v_plantilla,
     nullif(trim(coalesce(p_cliente,'')),''),nullif(trim(coalesce(p_motivo,'')),''))
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.registrar_venta_con_cupon(
  p_codigo text,
  p_venta jsonb,
  p_tasa_usd_mxn numeric default 18.67
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email',''));
  v_cupon public.cupones_descuento;
  v_codigo text := upper(trim(coalesce(p_codigo,'')));
  v_subtotal numeric(12,2);
  v_descuento numeric(12,2);
  v_total numeric(12,2);
  v_costo numeric(12,2);
  v_venta jsonb := p_venta;
  v_columnas text;
  v_valores text;
  v_keys_count integer;
  v_cols_count integer;
  v_insertada jsonb;
  v_venta_id text;
begin
  if v_email not in ('codedenissa19@gmail.com','carlos.arteaga.milan.2008@gmail.com') then
    raise exception 'No tienes permiso para aplicar cupones.' using errcode = '42501';
  end if;
  if p_tasa_usd_mxn is null or p_tasa_usd_mxn <= 0 then
    raise exception 'La tasa de cambio no es válida.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_venta) <> 'object' or coalesce(p_venta ->> 'ingreso','') !~ '^\d+(\.\d{1,2})?$' then
    raise exception 'El precio de la venta no es válido.' using errcode = '22023';
  end if;

  select * into v_cupon
  from public.cupones_descuento
  where codigo = v_codigo
  for update;
  if not found then raise exception 'No existe el cupón %.',v_codigo using errcode = 'P0001'; end if;
  if v_cupon.estado <> 'activo' then raise exception 'El cupón ya fue usado o anulado.' using errcode = 'P0001'; end if;
  if v_cupon.expira_en <= now() then raise exception 'El cupón venció.' using errcode = 'P0001'; end if;
  if v_cupon.usos >= v_cupon.usos_maximos then raise exception 'El cupón ya alcanzó su límite de uso.' using errcode = 'P0001'; end if;
  if v_cupon.cliente is not null and lower(trim(coalesce(p_venta ->> 'cliente',''))) <> lower(trim(v_cupon.cliente)) then
    raise exception 'Este cupón fue generado para otro cliente.' using errcode = 'P0001';
  end if;

  v_subtotal := (p_venta ->> 'ingreso')::numeric;
  if v_subtotal * p_tasa_usd_mxn < v_cupon.compra_minima_mxn then
    raise exception 'El subtotal no alcanza la compra mínima de % MXN.',v_cupon.compra_minima_mxn using errcode = 'P0001';
  end if;
  v_descuento := round(v_subtotal * v_cupon.porcentaje / 100,2);
  v_total := greatest(0,v_subtotal-v_descuento);
  v_costo := coalesce(nullif(p_venta ->> 'costo_real','')::numeric,0);
  v_venta := p_venta || jsonb_build_object(
    'cupon_codigo',v_cupon.codigo,
    'descuento_porcentaje',v_cupon.porcentaje,
    'descuento_usd',v_descuento,
    'precio_original_usd',v_subtotal,
    'ingreso',v_total,
    'monto_recibido',v_total,
    'ganancia_neta',v_total-v_costo,
    'margen',case when v_total > 0 then to_char(round(((v_total-v_costo)/v_total)*100,1),'FM999990.0')||'%' else '0%' end
  );

  select count(*) into v_keys_count from jsonb_object_keys(v_venta);
  select
    string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position),
    string_agg(format('r.%I', c.column_name), ', ' order by c.ordinal_position),
    count(*)
  into v_columnas,v_valores,v_cols_count
  from information_schema.columns c
  join jsonb_object_keys(v_venta) as k(key) on k.key=c.column_name
  where c.table_schema='public' and c.table_name='ventas';
  if v_keys_count <> v_cols_count then
    raise exception 'El registro contiene campos que no existen en public.ventas. Ejecuta la migración de cupones.' using errcode = '42703';
  end if;

  execute format(
    'insert into public.ventas as v (%s) select %s from jsonb_populate_record(null::public.ventas, $1) as r returning to_jsonb(v)',
    v_columnas,v_valores
  ) into v_insertada using v_venta;

  v_venta_id := coalesce(v_insertada ->> 'id',v_insertada ->> 'id_pedido');
  insert into public.cupones_redenciones(cupon_id,codigo,venta_id,cliente,subtotal_usd,descuento_usd)
  values(v_cupon.id,v_cupon.codigo,coalesce(v_venta_id,gen_random_uuid()::text),nullif(v_insertada ->> 'cliente',''),v_subtotal,v_descuento);
  update public.cupones_descuento
  set usos=usos+1,
      estado=case when usos+1 >= usos_maximos then 'usado' else estado end,
      actualizado_en=now()
  where id=v_cupon.id;

  return v_insertada;
end;
$$;

revoke all on function public.crear_cupon_descuento(text,text,numeric,numeric,text,text) from public, anon;
revoke all on function public.registrar_venta_con_cupon(text,jsonb,numeric) from public, anon;
grant execute on function public.crear_cupon_descuento(text,text,numeric,numeric,text,text) to authenticated;
grant execute on function public.registrar_venta_con_cupon(text,jsonb,numeric) to authenticated;

notify pgrst, 'reload schema';
commit;

