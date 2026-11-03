-- Permite registrar en una sola operación pavos de varios orígenes y las
-- cuatro categorías actuales de cupones, conservando categorías históricas.

alter table public.cuentas_gestion_pavos
  drop constraint if exists cuentas_gestion_pavos_origen_check;
alter table public.cuentas_gestion_pavos
  add constraint cuentas_gestion_pavos_origen_check
  check (origen in ('stw', 'diarias', 'alertas', 'pase', 'recarga'));

alter table public.cuentas_gestion_pavos
  drop constraint if exists cuentas_gestion_pavos_pavos_multiple_50_check;
alter table public.cuentas_gestion_pavos
  add constraint cuentas_gestion_pavos_pavos_multiple_50_check
  check (pavos >= 50 and pavos % 50 = 0) not valid;

alter table public.cuentas_gestion
  drop constraint if exists cuentas_gestion_pavos_disponibles_multiple_50_check;
alter table public.cuentas_gestion
  add constraint cuentas_gestion_pavos_disponibles_multiple_50_check
  check (pavos_disponibles >= 0 and pavos_disponibles % 50 = 0) not valid;

alter table public.cuentas_gestion_ventas
  drop constraint if exists cuentas_gestion_ventas_pavos_multiple_50_check;
alter table public.cuentas_gestion_ventas
  add constraint cuentas_gestion_ventas_pavos_multiple_50_check
  check (pavos >= 50 and pavos % 50 = 0) not valid;

create or replace function public.registrar_movimientos_pavos_lote(
  p_cuenta_id uuid,
  p_movimientos jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_periodo date := date_trunc('month', current_date)::date;
  v_item jsonb;
  v_origen text;
  v_pavos_text text;
  v_pavos integer;
  v_costo numeric(12,2);
  v_total integer := 0;
  v_generados integer := 0;
  v_count integer;
begin
  if lower(coalesce(auth.jwt() ->> 'email', '')) not in ('codedenissa19@gmail.com', 'carlos.arteaga.milan.2008@gmail.com') then
    raise exception 'No tienes permiso para modificar el inventario de pavos.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_movimientos) <> 'array' or jsonb_array_length(p_movimientos) < 1 or jsonb_array_length(p_movimientos) > 4 then
    raise exception 'Selecciona entre uno y cuatro orígenes de pavos.' using errcode = '22023';
  end if;
  if (select count(distinct item->>'origen') from jsonb_array_elements(p_movimientos) as item) <> jsonb_array_length(p_movimientos) then
    raise exception 'Cada origen puede aparecer una sola vez.' using errcode = '22023';
  end if;
  perform 1 from public.cuentas_gestion where id = p_cuenta_id for update;
  if not found then raise exception 'No se encontró la cuenta de Gestión seleccionada.' using errcode = 'P0002'; end if;

  for v_item in select value from jsonb_array_elements(p_movimientos)
  loop
    v_origen := v_item->>'origen';
    v_pavos_text := v_item->>'pavos';
    if v_origen not in ('diarias', 'alertas', 'pase', 'recarga') then
      raise exception 'Origen de pavos no válido.' using errcode = '22023';
    end if;
    if coalesce(v_pavos_text, '') !~ '^[0-9]+$' then
      raise exception 'La cantidad de cada origen debe ser un número entero.' using errcode = '22023';
    end if;
    v_pavos := v_pavos_text::integer;
    if v_pavos < 50 or v_pavos % 50 <> 0 then
      raise exception 'Cada cantidad debe ser múltiplo de 50 y tener un mínimo de 50.' using errcode = '22023';
    end if;
    begin
      v_costo := coalesce(nullif(v_item->>'costo_mxn', '')::numeric, 0);
    exception when invalid_text_representation then
      raise exception 'El costo de recarga debe ser un monto numérico válido.' using errcode = '22023';
    end;
    if v_costo < 0 or (v_origen = 'recarga' and v_costo <= 0) or (v_origen <> 'recarga' and v_costo <> 0) then
      raise exception 'Solo la recarga necesita un costo mayor que cero.' using errcode = '22023';
    end if;
    insert into public.cuentas_gestion_pavos (cuenta_id, fecha, origen, pavos, costo_mxn)
    values (p_cuenta_id, current_date, v_origen, v_pavos, v_costo);
    v_total := v_total + v_pavos;
    if v_origen in ('diarias', 'alertas', 'pase') then v_generados := v_generados + v_pavos; end if;
  end loop;

  update public.cuentas_gestion
  set pavos_disponibles = pavos_disponibles + v_total,
      pavos_generados_mes = case
        when v_generados > 0 then (case when pavos_generados_periodo = v_periodo then pavos_generados_mes else 0 end) + v_generados
        when pavos_generados_periodo = v_periodo then pavos_generados_mes else 0 end,
      pavos_generados_periodo = case when v_generados > 0 then v_periodo else pavos_generados_periodo end,
      actualizado_en = now()
  where id = p_cuenta_id;
end;
$$;

revoke all on function public.registrar_movimientos_pavos_lote(uuid, jsonb) from public, anon;
grant execute on function public.registrar_movimientos_pavos_lote(uuid, jsonb) to authenticated;

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
begin
  perform public.registrar_movimientos_pavos_lote(
    p_cuenta_id,
    jsonb_build_array(jsonb_build_object('origen', p_origen, 'pavos', p_pavos, 'costo_mxn', coalesce(p_costo_mxn, 0)))
  );
end;
$$;
revoke all on function public.registrar_movimiento_pavos(uuid, integer, text, numeric) from public, anon;
grant execute on function public.registrar_movimiento_pavos(uuid, integer, text, numeric) to authenticated;

alter table public.cupones_descuento
  drop constraint if exists cupones_descuento_categoria_check;
alter table public.cupones_descuento
  add constraint cupones_descuento_categoria_check
  check (categoria in ('satisfaccion', 'promocion', 'referidos', 'lealtad', 'volumen', 'fidelidad', 'otro'));

create or replace function public.crear_cupon_descuento(
  p_codigo text,
  p_categoria text,
  p_porcentaje numeric,
  p_compra_minima_mxn numeric default 600,
  p_compra_minima_usd numeric default 30,
  p_cliente text default null,
  p_motivo text default null
) returns public.cupones_descuento
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
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
  if coalesce(p_codigo, '') !~ '^[A-Z0-9-]{6,24}$' then
    raise exception 'El código no tiene un formato válido.' using errcode = '22023';
  end if;
  if p_categoria not in ('satisfaccion', 'promocion', 'referidos', 'lealtad') then
    raise exception 'Selecciona una categoría válida.' using errcode = '22023';
  end if;
  if p_porcentaje < 5 or p_porcentaje > 10 then
    raise exception 'El descuento debe estar entre 5%% y 10%%.' using errcode = '22023';
  end if;
  if p_compra_minima_mxn < 600 or p_compra_minima_usd < 30 then
    raise exception 'La compra mínima debe ser de al menos MX$600 o US$30.' using errcode = '22023';
  end if;
  insert into public.cupones_descuento
    (codigo, categoria, porcentaje, compra_minima_mxn, compra_minima_usd, creador_email, creador_rol, plantilla, cliente, motivo)
  values
    (upper(p_codigo), p_categoria, p_porcentaje, p_compra_minima_mxn, p_compra_minima_usd, v_email, v_rol, v_plantilla,
     nullif(trim(coalesce(p_cliente, '')), ''), nullif(trim(coalesce(p_motivo, '')), ''))
  returning * into v_row;
  return v_row;
end;
$$;
revoke all on function public.crear_cupon_descuento(text, text, numeric, numeric, numeric, text, text) from public, anon;
grant execute on function public.crear_cupon_descuento(text, text, numeric, numeric, numeric, text, text) to authenticated;

notify pgrst, 'reload schema';

