-- Orígenes de pavos detallados y cantidades en bloques de 50.
-- Mantiene el historial antiguo ('stw') sin cambiarlo; los registros nuevos
-- usan Diarias, Alertas, Pase o Recarga de pavos.

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
  if p_pavos is null or p_pavos < 50 or p_pavos % 50 <> 0 then
    raise exception 'La cantidad de pavos debe ser un múltiplo de 50, con mínimo de 50.';
  end if;
  if p_origen not in ('diarias', 'alertas', 'pase', 'recarga') then
    raise exception 'Selecciona Diarias, Alertas, Pase o Recarga de pavos como origen.';
  end if;
  if v_costo < 0 or (p_origen <> 'recarga' and v_costo <> 0) or (p_origen = 'recarga' and v_costo <= 0) then
    raise exception 'Registra un costo mayor que cero solo para una recarga.';
  end if;
  perform 1 from public.cuentas_gestion where id = p_cuenta_id for update;
  if not found then raise exception 'No se encontró la cuenta de Gestión seleccionada.'; end if;

  insert into public.cuentas_gestion_pavos (cuenta_id, fecha, origen, pavos, costo_mxn)
    values (p_cuenta_id, current_date, p_origen, p_pavos, v_costo);
  update public.cuentas_gestion
    set pavos_disponibles = pavos_disponibles + p_pavos,
        pavos_generados_mes = case
          when p_origen in ('diarias', 'alertas', 'pase') then (case when pavos_generados_periodo = v_periodo then pavos_generados_mes else 0 end) + p_pavos
          when pavos_generados_periodo = v_periodo then pavos_generados_mes else 0 end,
        pavos_generados_periodo = v_periodo,
        actualizado_en = now()
    where id = p_cuenta_id;
end;
$$;
revoke all on function public.registrar_movimiento_pavos(uuid, integer, text, numeric) from public;
grant execute on function public.registrar_movimiento_pavos(uuid, integer, text, numeric) to authenticated;

notify pgrst, 'reload schema';

