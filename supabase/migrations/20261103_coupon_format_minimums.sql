-- Nuevos cupones usan SHG- seguido por seis dígitos; el mínimo de compra
-- se actualiza a MXN 385 o USD 20. Se preservan códigos existentes.

alter table public.cupones_descuento
  alter column compra_minima_mxn set default 385,
  alter column compra_minima_usd set default 20;

alter table public.cupones_descuento
  drop constraint if exists cupones_descuento_compra_minima_mxn_check,
  drop constraint if exists cupones_descuento_compra_minima_usd_check;

alter table public.cupones_descuento
  add constraint cupones_descuento_compra_minima_mxn_check
    check (compra_minima_mxn >= 385),
  add constraint cupones_descuento_compra_minima_usd_check
    check (compra_minima_usd >= 20);

create or replace function public.crear_cupon_descuento(
  p_codigo text,
  p_categoria text,
  p_porcentaje numeric,
  p_compra_minima_mxn numeric default 385,
  p_compra_minima_usd numeric default 20,
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
  if coalesce(p_codigo, '') !~ '^SHG-[0-9]{6}$' then
    raise exception 'El código debe tener el formato SHG- seguido por seis dígitos.' using errcode = '22023';
  end if;
  if p_categoria not in ('satisfaccion', 'promocion', 'referidos', 'lealtad') then
    raise exception 'Selecciona una categoría válida.' using errcode = '22023';
  end if;
  if p_porcentaje < 5 or p_porcentaje > 10 then
    raise exception 'El descuento debe estar entre 5%% y 10%%.' using errcode = '22023';
  end if;
  if p_compra_minima_mxn < 385 or p_compra_minima_usd < 20 then
    raise exception 'La compra mínima debe ser de al menos MX$385 o US$20.' using errcode = '22023';
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

