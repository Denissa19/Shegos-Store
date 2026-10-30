drop policy if exists solo_ceo_administra_usuarios on public.usuarios_roles;
create policy solo_ceo_administra_usuarios on public.usuarios_roles
for all to authenticated using ((select public.es_ceo())) with check ((select public.es_ceo()));
drop policy if exists usuarios_ven_su_propio_registro on public.usuarios_roles;
create policy usuarios_ven_su_propio_registro on public.usuarios_roles
for select to authenticated using (id=(select auth.uid()) or (select public.es_ceo()));

drop policy if exists "Permitir todo a usuarios autenticados" on public.ventas;
create policy ventas_solo_staff on public.ventas
for all to authenticated using ((select public.es_staff())) with check ((select public.es_staff()));

drop policy if exists clientes_solo_panel on public.clientes;
create policy clientes_solo_staff on public.clientes
for all to authenticated using ((select public.es_staff())) with check ((select public.es_staff()));

drop policy if exists retiros_solo_ceo on public.retiros;
create policy retiros_solo_ceo on public.retiros
for all to authenticated using ((select public.es_ceo())) with check ((select public.es_ceo()));
