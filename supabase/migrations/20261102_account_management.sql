-- Inventario de cuentas de Fortnite y asignación transaccional de regalos.
-- Ejecutar una sola vez en Supabase SQL Editor. El seed no sobrescribe cambios existentes.

create table if not exists public.cuentas_gestion (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  epic_account_id text not null default '',
  stw_level integer,
  pavos_disponibles integer not null default 0 check (pavos_disponibles >= 0),
  pavos_generados_mes integer not null default 0 check (pavos_generados_mes >= 0),
  pavos_generados_periodo date not null default date_trunc('month', current_date)::date,
  regalos_disponibles integer not null default 5 check (regalos_disponibles between 0 and 5),
  regalos_dia date not null default current_date,
  actualizado_en timestamptz not null default now()
);

alter table public.cuentas_gestion
  add column if not exists pavos_generados_mes integer not null default 0 check (pavos_generados_mes >= 0),
  add column if not exists pavos_generados_periodo date not null default date_trunc('month', current_date)::date;

alter table public.cuentas_gestion enable row level security;
drop policy if exists "Panel autenticado puede leer cuentas de gestión" on public.cuentas_gestion;
create policy "Panel autenticado puede leer cuentas de gestión"
  on public.cuentas_gestion for select to authenticated
  using ((auth.jwt() ->> 'email') in ('codedenissa19@gmail.com', 'carlos.arteaga.milan.2008@gmail.com'));
drop policy if exists "Panel autenticado puede administrar cuentas de gestión" on public.cuentas_gestion;
create policy "Panel autenticado puede administrar cuentas de gestión"
  on public.cuentas_gestion for all to authenticated
  using ((auth.jwt() ->> 'email') in ('codedenissa19@gmail.com', 'carlos.arteaga.milan.2008@gmail.com'))
  with check ((auth.jwt() ->> 'email') in ('codedenissa19@gmail.com', 'carlos.arteaga.milan.2008@gmail.com'));

insert into public.cuentas_gestion
  (nombre, epic_account_id, stw_level, pavos_disponibles, regalos_disponibles, regalos_dia)
values
  ('Maidas-S', '', 135, 3000, 5, current_date),
  ('Maidas-OS', '', 110, 1450, 5, current_date),
  ('Shegos么1', '', 106, 1600, 5, current_date),
  ('Shegos么2', '', 61, 1950, 5, current_date),
  ('Shegos么3', '', 63, 1950, 5, current_date),
  ('Shegos么4', '', 65, 4200, 5, current_date),
  ('Denissa_7u7', '', null, 4800, 5, current_date)
on conflict (nombre) do nothing;

alter table public.ventas
  add column if not exists cuentas_regalo jsonb not null default '[]'::jsonb;

create table if not exists public.cuentas_gestion_ventas (
  id uuid primary key default gen_random_uuid(),
  venta_ref text not null,
  cuenta_id uuid not null references public.cuentas_gestion(id),
  fecha_venta date not null,
  aplicado_dia date not null default current_date,
  pavos integer not null check (pavos > 0),
  ingreso_mxn numeric(12,2) not null default 0,
  unique (venta_ref, cuenta_id)
);

alter table public.cuentas_gestion_ventas enable row level security;
drop policy if exists "Panel autenticado puede leer actividad de cuentas" on public.cuentas_gestion_ventas;
create policy "Panel autenticado puede leer actividad de cuentas"
  on public.cuentas_gestion_ventas for select to authenticated
  using ((auth.jwt() ->> 'email') in ('codedenissa19@gmail.com', 'carlos.arteaga.milan.2008@gmail.com'));

create or replace function public.sync_cuentas_gestion_venta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref text;
  v_total_pavos integer := 0;
  v_ingreso_mxn numeric(12,2) := 0;
  v_alloc jsonb;
  v_item jsonb;
  v_cuenta_id uuid;
  v_pavos integer;
  v_affected integer;
  v_old_mov record;
begin
  if tg_op = 'DELETE' then
    for v_old_mov in select * from public.cuentas_gestion_ventas where venta_ref = old.id::text loop
      update public.cuentas_gestion
        set pavos_disponibles = pavos_disponibles + v_old_mov.pavos,
            regalos_disponibles = case
              when regalos_dia = current_date and v_old_mov.aplicado_dia = current_date
                then least(5, regalos_disponibles + 1)
              else regalos_disponibles end,
            regalos_dia = case when regalos_dia < current_date then current_date else regalos_dia end,
            actualizado_en = now()
        where id = v_old_mov.cuenta_id;
    end loop;
    delete from public.cuentas_gestion_ventas where venta_ref = old.id::text;
    return old;
  end if;

  v_ref := coalesce(new.id::text, new.id_pedido::text);

  if tg_op = 'UPDATE' and coalesce(old.cuentas_regalo, '[]'::jsonb) = coalesce(new.cuentas_regalo, '[]'::jsonb) then
    select coalesce(sum((x->>'pavos')::integer), 0)
      into v_total_pavos
      from jsonb_array_elements(coalesce(new.cuentas_regalo, '[]'::jsonb)) x;
    if v_total_pavos > 0 then
      v_ingreso_mxn := round(coalesce(new.ingreso, 0) * 18.67, 2);
      update public.cuentas_gestion_ventas
        set fecha_venta = coalesce(new.created_at::date, current_date),
            ingreso_mxn = round(v_ingreso_mxn * pavos / v_total_pavos, 2)
        where venta_ref = v_ref;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    for v_old_mov in select * from public.cuentas_gestion_ventas where venta_ref = old.id::text loop
      update public.cuentas_gestion
        set pavos_disponibles = pavos_disponibles + v_old_mov.pavos,
            regalos_disponibles = case
              when regalos_dia = current_date and v_old_mov.aplicado_dia = current_date
                then least(5, regalos_disponibles + 1)
              else regalos_disponibles end,
            regalos_dia = case when regalos_dia < current_date then current_date else regalos_dia end,
            actualizado_en = now()
        where id = v_old_mov.cuenta_id;
    end loop;
    delete from public.cuentas_gestion_ventas where venta_ref = old.id::text;
  end if;

  v_alloc := coalesce(new.cuentas_regalo, '[]'::jsonb);
  if jsonb_typeof(v_alloc) <> 'array' then
    raise exception 'La asignación de cuentas para el regalo no tiene formato válido.';
  end if;
  select coalesce(sum((x->>'pavos')::integer), 0) into v_total_pavos
    from jsonb_array_elements(v_alloc) x;
  if v_total_pavos = 0 then return new; end if;
  if exists (select 1 from jsonb_array_elements(v_alloc) x where coalesce((x->>'pavos')::integer, 0) <= 0) then
    raise exception 'Cada cuenta seleccionada debe tener una cantidad de pavos mayor a cero.';
  end if;

  v_ingreso_mxn := round(coalesce(new.ingreso, 0) * 18.67, 2);
  for v_item in select value from jsonb_array_elements(v_alloc) loop
    v_cuenta_id := (v_item->>'cuenta_id')::uuid;
    v_pavos := (v_item->>'pavos')::integer;
    update public.cuentas_gestion
      set regalos_disponibles = (case when regalos_dia < current_date then 5 else regalos_disponibles end) - 1,
          regalos_dia = current_date,
          pavos_disponibles = pavos_disponibles - v_pavos,
          actualizado_en = now()
      where id = v_cuenta_id
        and pavos_disponibles >= v_pavos
        and (case when regalos_dia < current_date then 5 else regalos_disponibles end) > 0;
    get diagnostics v_affected = row_count;
    if v_affected <> 1 then
      raise exception 'La cuenta seleccionada no tiene suficientes pavos o regalos disponibles. Actualiza Gestión e inténtalo de nuevo.';
    end if;
    insert into public.cuentas_gestion_ventas (venta_ref, cuenta_id, fecha_venta, aplicado_dia, pavos, ingreso_mxn)
      values (v_ref, v_cuenta_id, coalesce(new.created_at::date, current_date), current_date, v_pavos,
        round(v_ingreso_mxn * v_pavos / v_total_pavos, 2));
  end loop;
  return new;
end;
$$;

drop trigger if exists ventas_sync_cuentas_gestion on public.ventas;
create trigger ventas_sync_cuentas_gestion
  after insert or update of cuentas_regalo, ingreso, created_at or delete on public.ventas
  for each row execute function public.sync_cuentas_gestion_venta();

grant select, insert, update on public.cuentas_gestion to authenticated;
grant select, insert, update, delete on public.cuentas_gestion_ventas to authenticated;

-- Historial de ingresos de pavos: STW no genera costo y las recargas guardan su inversión.
create table if not exists public.cuentas_gestion_pavos (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references public.cuentas_gestion(id) on delete cascade,
  fecha date not null default current_date,
  origen text not null check (origen in ('stw','recarga')),
  pavos integer not null check (pavos > 0),
  costo_mxn numeric(12,2) not null default 0 check (costo_mxn >= 0),
  creado_en timestamptz not null default now(),
  check (origen <> 'stw' or costo_mxn = 0)
);
create index if not exists cuentas_gestion_pavos_cuenta_fecha_idx
  on public.cuentas_gestion_pavos (cuenta_id, fecha desc);
alter table public.cuentas_gestion_pavos enable row level security;
drop policy if exists "Panel autenticado puede leer entradas de pavos" on public.cuentas_gestion_pavos;
create policy "Panel autenticado puede leer entradas de pavos"
  on public.cuentas_gestion_pavos for select to authenticated
  using ((auth.jwt() ->> 'email') in ('codedenissa19@gmail.com', 'carlos.arteaga.milan.2008@gmail.com'));
grant select on public.cuentas_gestion_pavos to authenticated;

create or replace function public.registrar_movimiento_pavos(
  p_cuenta_id uuid,
  p_pavos integer,
  p_origen text,
  p_costo_mxn numeric default 0
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_periodo date := date_trunc('month', current_date)::date;
  v_costo numeric(12,2) := coalesce(p_costo_mxn, 0);
begin
  if coalesce(auth.jwt() ->> 'email', '') not in ('codedenissa19@gmail.com', 'carlos.arteaga.milan.2008@gmail.com') then
    raise exception 'No tienes permiso para modificar el inventario de pavos.';
  end if;
  if p_pavos is null or p_pavos <= 0 then
    raise exception 'La cantidad de pavos debe ser mayor que cero.';
  end if;
  if p_origen not in ('stw','recarga') then
    raise exception 'Selecciona STW o recarga como origen de los pavos.';
  end if;
  if v_costo < 0 or (p_origen = 'stw' and v_costo <> 0) then
    raise exception 'El costo debe ser cero para STW y no puede ser negativo.';
  end if;
  perform 1 from public.cuentas_gestion where id = p_cuenta_id for update;
  if not found then raise exception 'No se encontró la cuenta de Gestión seleccionada.'; end if;

  insert into public.cuentas_gestion_pavos (cuenta_id, fecha, origen, pavos, costo_mxn)
    values (p_cuenta_id, current_date, p_origen, p_pavos, v_costo);
  update public.cuentas_gestion
    set pavos_disponibles = pavos_disponibles + p_pavos,
        pavos_generados_mes = case
          when p_origen = 'stw' then (case when pavos_generados_periodo = v_periodo then pavos_generados_mes else 0 end) + p_pavos
          when pavos_generados_periodo = v_periodo then pavos_generados_mes else 0 end,
        pavos_generados_periodo = v_periodo,
        actualizado_en = now()
    where id = p_cuenta_id;
end;
$$;
revoke all on function public.registrar_movimiento_pavos(uuid, integer, text, numeric) from public;
grant execute on function public.registrar_movimiento_pavos(uuid, integer, text, numeric) to authenticated;

-- Activa la sincronización inmediata del panel si Supabase usa su publicación estándar.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime' and not puballtables) then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cuentas_gestion') then
      execute 'alter publication supabase_realtime add table public.cuentas_gestion';
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cuentas_gestion_ventas') then
      execute 'alter publication supabase_realtime add table public.cuentas_gestion_ventas';
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cuentas_gestion_pavos') then
      execute 'alter publication supabase_realtime add table public.cuentas_gestion_pavos';
    end if;
  end if;
end;
$$;

-- PostgREST may cache the exposed schema; refresh it after creating the tables.
notify pgrst, 'reload schema';
