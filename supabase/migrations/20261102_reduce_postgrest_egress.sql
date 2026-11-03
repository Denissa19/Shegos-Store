-- Reduce PostgREST responses for the admin orders list.
-- Attachments stay in Supabase and are fetched only when a staff member opens them.

create or replace function public.admin_pedidos_sin_adjuntos()
returns setof jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_columns text;
  v_receipt_expr text := 'false';
  v_photo_expr text := 'false';
  v_has_receipt boolean;
  v_has_receipt_url boolean;
  v_has_photo boolean;
begin
  if coalesce(auth.jwt() ->> 'email', '') not in (
    'codedenissa19@gmail.com',
    'carlos.arteaga.milan.2008@gmail.com'
  ) then
    raise exception 'No tienes permiso para consultar los pedidos del panel.' using errcode = '42501';
  end if;

  select
    string_agg(format('p.%I', c.column_name), ', ' order by c.ordinal_position),
    coalesce(bool_or(c.column_name = 'comprobante'), false),
    coalesce(bool_or(c.column_name = 'comprobante_url'), false),
    coalesce(bool_or(c.column_name = 'foto_producto'), false)
  into v_columns, v_has_receipt, v_has_receipt_url, v_has_photo
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'pedidos'
    and c.column_name not in (
      'comprobante', 'comprobante_url', 'foto_producto',
      '__shegos_has_receipt', '__shegos_has_photo'
    );

  if v_columns is null then
    raise exception 'No se encontró la tabla public.pedidos.' using errcode = '42P01';
  end if;

  if v_has_receipt and v_has_receipt_url then
    v_receipt_expr := 'coalesce(p.comprobante, p.comprobante_url) is not null';
  elsif v_has_receipt then
    v_receipt_expr := 'p.comprobante is not null';
  elsif v_has_receipt_url then
    v_receipt_expr := 'p.comprobante_url is not null';
  end if;
  if v_has_photo then
    v_photo_expr := 'p.foto_producto is not null';
  end if;

  return query execute format(
    'select (to_jsonb(q) - %L - %L) || jsonb_build_object(''tiene_comprobante'', q.__shegos_has_receipt, ''tiene_foto_producto'', q.__shegos_has_photo)
       from (select %s, %s as __shegos_has_receipt, %s as __shegos_has_photo from public.pedidos p) q',
    '__shegos_has_receipt', '__shegos_has_photo', v_columns, v_receipt_expr, v_photo_expr
  );
end;
$$;

create or replace function public.admin_pedido_adjunto(p_id text, p_tipo text)
returns text
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_receipt boolean;
  v_receipt_url boolean;
  v_photo boolean;
  v_has_order_id boolean;
  v_has_row_id boolean;
  v_value_expr text;
  v_id_expr text;
  v_sql text;
  v_result text;
begin
  if coalesce(auth.jwt() ->> 'email', '') not in (
    'codedenissa19@gmail.com',
    'carlos.arteaga.milan.2008@gmail.com'
  ) then
    raise exception 'No tienes permiso para abrir archivos de pedidos.' using errcode = '42501';
  end if;
  if p_tipo not in ('comprobante', 'foto_producto') then
    raise exception 'Tipo de archivo no válido.' using errcode = '22023';
  end if;

  select
    coalesce(bool_or(column_name = 'comprobante'), false),
    coalesce(bool_or(column_name = 'comprobante_url'), false),
    coalesce(bool_or(column_name = 'foto_producto'), false),
    coalesce(bool_or(column_name = 'id_pedido'), false),
    coalesce(bool_or(column_name = 'id'), false)
  into v_receipt, v_receipt_url, v_photo, v_has_order_id, v_has_row_id
  from information_schema.columns
  where table_schema = 'public' and table_name = 'pedidos';

  if p_tipo = 'foto_producto' then
    if not v_photo then return null; end if;
    v_value_expr := 'p.foto_producto';
  elsif v_receipt and v_receipt_url then
    v_value_expr := 'coalesce(p.comprobante, p.comprobante_url)';
  elsif v_receipt then
    v_value_expr := 'p.comprobante';
  elsif v_receipt_url then
    v_value_expr := 'p.comprobante_url';
  else
    return null;
  end if;

  v_id_expr := '';
  if v_has_order_id then v_id_expr := 'p.id_pedido::text = $1'; end if;
  if v_has_row_id then
    v_id_expr := case when v_id_expr = '' then 'p.id::text = $1' else v_id_expr || ' or p.id::text = $1' end;
  end if;
  if v_id_expr = '' then return null; end if;

  v_sql := format('select %s from public.pedidos p where (%s) limit 1', v_value_expr, v_id_expr);
  execute v_sql into v_result using p_id;
  return v_result;
end;
$$;

revoke all on function public.admin_pedidos_sin_adjuntos() from public, anon;
revoke all on function public.admin_pedido_adjunto(text, text) from public, anon;
grant execute on function public.admin_pedidos_sin_adjuntos() to authenticated;
grant execute on function public.admin_pedido_adjunto(text, text) to authenticated;

notify pgrst, 'reload schema';

