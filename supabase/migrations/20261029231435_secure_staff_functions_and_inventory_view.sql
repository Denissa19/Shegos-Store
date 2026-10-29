alter view public.v_inventario_admin set (security_invoker=true);

drop policy if exists catalogo_cuentas_detalle_no_client_access on private.catalogo_cuentas_detalle;
create policy catalogo_cuentas_detalle_no_client_access on private.catalogo_cuentas_detalle
for all to public using(false) with check(false);

create or replace function public.es_ceo()
returns boolean language sql stable security definer set search_path=pg_catalog
as $$ select coalesce((select rol='CEO'::public.rol_usuario and activo=true from public.usuarios_roles where id=auth.uid()),false); $$;
create or replace function public.es_staff()
returns boolean language sql stable security definer set search_path=pg_catalog
as $$ select exists(select 1 from public.usuarios_roles where id=auth.uid() and activo=true); $$;
create or replace function public.rol_actual()
returns public.rol_usuario language sql stable security definer set search_path=pg_catalog
as $$ select rol from public.usuarios_roles where id=auth.uid() and activo=true; $$;

alter function public.resumen_operativo_admin(timestamptz,timestamptz) set search_path=pg_catalog;
alter function public.set_actualizado_en() set search_path=pg_catalog;
alter function public.log_cambio_costo() set search_path=pg_catalog;

create or replace function public.kpis_financieros(p_fecha_inicio timestamptz,p_fecha_fin timestamptz)
returns table(ingresos_brutos numeric,costos_totales numeric,ganancia_neta numeric,roi_porcentaje numeric)
language sql stable security definer set search_path=pg_catalog as $$
select coalesce(sum(ingresos_totales_usd),0),coalesce(sum(costos_totales_usd),0),
coalesce(sum(ganancias_netas_usd),0),
case when coalesce(sum(costos_totales_usd),0)=0 then 0 else round((sum(ganancias_netas_usd)/sum(costos_totales_usd))*100,2) end
from public.ventas_contabilidad
where fecha_exacta>=p_fecha_inicio and fecha_exacta<p_fecha_fin and public.es_ceo();
$$;

create or replace function public.serie_financiera_diaria(p_fecha_inicio timestamptz,p_fecha_fin timestamptz)
returns table(periodo date,ingresos numeric,costos numeric,ganancias numeric)
language sql stable security definer set search_path=pg_catalog as $$
select date_trunc('day',fecha_exacta)::date,sum(ingresos_totales_usd),sum(costos_totales_usd),sum(ganancias_netas_usd)
from public.ventas_contabilidad where fecha_exacta>=p_fecha_inicio and fecha_exacta<p_fecha_fin and public.es_ceo()
group by 1 order by 1;
$$;

create or replace function public.serie_financiera_mensual(p_anio integer)
returns table(periodo date,ingresos numeric,costos numeric,ganancias numeric)
language sql stable security definer set search_path=pg_catalog as $$
select date_trunc('month',fecha_exacta)::date,sum(ingresos_totales_usd),sum(costos_totales_usd),sum(ganancias_netas_usd)
from public.ventas_contabilidad where extract(year from fecha_exacta)=p_anio and public.es_ceo()
group by 1 order by 1;
$$;

create or replace function public.completar_pedido(p_id_pedido uuid,p_id_bot uuid,p_tasa_cambio numeric default null,p_usuario uuid default auth.uid())
returns public.ventas_contabilidad language plpgsql security definer set search_path=pg_catalog as $$
declare v_pedido public.pedidos%rowtype; v_producto jsonb; v_id_item uuid; v_cantidad integer;
v_costo_item numeric(10,2); v_costo_total numeric(10,2):=0; v_venta public.ventas_contabilidad%rowtype;
begin
if auth.uid() is null or not public.es_staff() or p_usuario is distinct from auth.uid() then raise exception 'No autorizado' using errcode='42501'; end if;
select * into v_pedido from public.pedidos where id_pedido=p_id_pedido for update;
if not found then raise exception 'Pedido % no encontrado',p_id_pedido; end if;
if v_pedido.estado='Completado' then raise exception 'El pedido ya fue completado previamente'; end if;
for v_producto in select * from jsonb_array_elements(v_pedido.productos) loop
  v_id_item:=(v_producto->>'id_item')::uuid; v_cantidad:=(v_producto->>'cantidad')::integer;
  select precio_costo_usd,stock_disponible into v_costo_item,v_cantidad from public.inventario_cosmeticos where id_item=v_id_item for update;
  if not found then raise exception 'Ítem % no encontrado en inventario',v_id_item; end if;
  if v_cantidad<(v_producto->>'cantidad')::integer then raise exception 'Stock insuficiente para el ítem %',v_id_item; end if;
  v_costo_total:=v_costo_total+v_costo_item*(v_producto->>'cantidad')::integer;
  update public.inventario_cosmeticos set stock_disponible=stock_disponible-(v_producto->>'cantidad')::integer where id_item=v_id_item;
end loop;
if p_id_bot is not null then update public.cuentas_bots set estado_agregacion='Regalo Enviado' where id_bot=p_id_bot; end if;
update public.pedidos set estado='Completado',id_bot_asignado=p_id_bot,completado_en=now() where id_pedido=p_id_pedido;
insert into public.ventas_contabilidad(id_pedido,ingresos_totales_usd,ingresos_moneda_local,costos_totales_usd,tasa_cambio_aplicada,registrado_por)
values(p_id_pedido,v_pedido.total_usd,case when p_tasa_cambio is not null then v_pedido.total_usd*p_tasa_cambio else null end,v_costo_total,p_tasa_cambio,p_usuario)
returning * into v_venta;
return v_venta;
end;
$$;

create or replace function public.registrar_venta_manual(p_ingresos_usd numeric,p_costos_usd numeric,p_tasa_cambio numeric default null,p_notas text default null,p_usuario uuid default auth.uid())
returns public.ventas_contabilidad language plpgsql security definer set search_path=pg_catalog as $$
declare v_venta public.ventas_contabilidad%rowtype;
begin
if auth.uid() is null or not public.es_staff() or p_usuario is distinct from auth.uid() then raise exception 'No autorizado' using errcode='42501'; end if;
insert into public.ventas_contabilidad(ingresos_totales_usd,ingresos_moneda_local,costos_totales_usd,tasa_cambio_aplicada,registrado_por,notas)
values(p_ingresos_usd,case when p_tasa_cambio is not null then p_ingresos_usd*p_tasa_cambio else null end,p_costos_usd,p_tasa_cambio,p_usuario,p_notas)
returning * into v_venta;
return v_venta;
end;
$$;

revoke all on function public.completar_pedido(uuid,uuid,numeric,uuid) from public,anon;
grant execute on function public.completar_pedido(uuid,uuid,numeric,uuid) to authenticated;
revoke all on function public.registrar_venta_manual(numeric,numeric,numeric,text,uuid) from public,anon;
grant execute on function public.registrar_venta_manual(numeric,numeric,numeric,text,uuid) to authenticated;
revoke all on function public.kpis_financieros(timestamptz,timestamptz) from public,anon;
grant execute on function public.kpis_financieros(timestamptz,timestamptz) to authenticated;
revoke all on function public.serie_financiera_diaria(timestamptz,timestamptz) from public,anon;
grant execute on function public.serie_financiera_diaria(timestamptz,timestamptz) to authenticated;
revoke all on function public.serie_financiera_mensual(integer) from public,anon;
grant execute on function public.serie_financiera_mensual(integer) to authenticated;

create index if not exists idx_catalogo_cuentas_creado_por on public.catalogo_cuentas(creado_por);
create index if not exists idx_inventario_cosmeticos_creado_por on public.inventario_cosmeticos(creado_por);
create index if not exists idx_inventario_costo_bitacora_id_item on public.inventario_costo_bitacora(id_item);
create index if not exists idx_inventario_costo_bitacora_modificado_por on public.inventario_costo_bitacora(modificado_por);
create index if not exists idx_pedidos_id_bot_asignado on public.pedidos(id_bot_asignado);
create index if not exists idx_ventas_contabilidad_registrado_por on public.ventas_contabilidad(registrado_por);
