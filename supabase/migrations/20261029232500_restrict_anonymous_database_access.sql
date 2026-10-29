revoke all on table public.clientes,public.cuentas_bots,public.inventario_cosmeticos,
  public.inventario_costo_bitacora,public.pedidos,public.retiros,public.usuarios_roles,
  public.ventas,public.ventas_contabilidad,public.catalogo_productos,public.catalogo_cuentas
from public,anon;
grant all on table public.clientes,public.cuentas_bots,public.inventario_cosmeticos,
  public.inventario_costo_bitacora,public.pedidos,public.retiros,public.usuarios_roles,
  public.ventas,public.ventas_contabilidad,public.catalogo_productos
to authenticated;
grant select on table public.catalogo_cuentas to authenticated;

revoke all on public.v_inventario_admin from public,anon;
grant select on public.v_inventario_admin to authenticated;

revoke all on function public.es_ceo() from public,anon;
grant execute on function public.es_ceo() to authenticated;
revoke all on function public.es_staff() from public,anon;
grant execute on function public.es_staff() to authenticated;
revoke all on function public.rol_actual() from public,anon;
grant execute on function public.rol_actual() to authenticated;
revoke all on function public.resumen_operativo_admin(timestamptz,timestamptz) from public,anon;
grant execute on function public.resumen_operativo_admin(timestamptz,timestamptz) to authenticated;
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
revoke all on function public.guardar_cuenta_catalogo(uuid,text,integer,text[],boolean,integer,numeric,text,text,text,numeric,text) from public,anon;
grant execute on function public.guardar_cuenta_catalogo(uuid,text,integer,text[],boolean,integer,numeric,text,text,text,numeric,text) to authenticated;
revoke all on function public.leer_detalle_catalogo_cuenta(uuid) from public,anon;
grant execute on function public.leer_detalle_catalogo_cuenta(uuid) to authenticated;
revoke all on function public.set_actualizado_en() from public,anon,authenticated;
revoke all on function public.log_cambio_costo() from public,anon,authenticated;

drop policy if exists solo_ceo_administra_usuarios on public.usuarios_roles;
drop policy if exists usuarios_ven_su_propio_registro on public.usuarios_roles;
create policy usuarios_select_self_or_ceo on public.usuarios_roles
for select to authenticated using (id=(select auth.uid()) or (select public.es_ceo()));
create policy usuarios_ceo_insert on public.usuarios_roles
for insert to authenticated with check ((select public.es_ceo()));
create policy usuarios_ceo_update on public.usuarios_roles
for update to authenticated using ((select public.es_ceo())) with check ((select public.es_ceo()));
create policy usuarios_ceo_delete on public.usuarios_roles
for delete to authenticated using ((select public.es_ceo()));
