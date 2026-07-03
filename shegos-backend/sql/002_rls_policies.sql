-- =====================================================================
-- SHEGOS STORE - ROW LEVEL SECURITY (RLS)
-- =====================================================================
-- Nota: la API también aplica RBAC en el middleware (defensa en profundidad).
-- Estas políticas son la última línea de defensa a nivel de base de datos.

alter table public.usuarios_roles      enable row level security;
alter table public.inventario_cosmeticos enable row level security;
alter table public.inventario_costo_bitacora enable row level security;
alter table public.cuentas_bots        enable row level security;
alter table public.pedidos             enable row level security;
alter table public.ventas_contabilidad enable row level security;

-- Función helper: obtiene el rol del usuario autenticado actual
create or replace function public.rol_actual()
returns rol_usuario
language sql
security definer
stable
as $$
    select rol from public.usuarios_roles where id = auth.uid();
$$;

create or replace function public.es_ceo()
returns boolean
language sql
security definer
stable
as $$
    select coalesce((select rol = 'CEO' from public.usuarios_roles where id = auth.uid()), false);
$$;

create or replace function public.es_staff()
returns boolean
language sql
security definer
stable
as $$
    select exists (
        select 1 from public.usuarios_roles
        where id = auth.uid() and activo = true
    );
$$;

-- ---------------------------------------------------------------------
-- usuarios_roles: solo el propio CEO gestiona roles; cada usuario ve su fila
-- ---------------------------------------------------------------------
create policy "usuarios_ven_su_propio_registro"
    on public.usuarios_roles for select
    using (id = auth.uid() or public.es_ceo());

create policy "solo_ceo_administra_usuarios"
    on public.usuarios_roles for all
    using (public.es_ceo())
    with check (public.es_ceo());

-- ---------------------------------------------------------------------
-- inventario_cosmeticos: staff lee todo, pero precio_costo_usd se
-- oculta a nivel de API (ver vista pública abajo); solo CEO/Admin
-- autenticados pueden insertar/editar.
-- ---------------------------------------------------------------------
create policy "staff_lee_inventario"
    on public.inventario_cosmeticos for select
    using (public.es_staff());

create policy "staff_inserta_inventario"
    on public.inventario_cosmeticos for insert
    with check (public.es_staff());

create policy "staff_actualiza_inventario"
    on public.inventario_cosmeticos for update
    using (public.es_staff())
    with check (public.es_staff());

create policy "solo_ceo_elimina_inventario"
    on public.inventario_cosmeticos for delete
    using (public.es_ceo());

-- Vista segura para Admin: NO expone precio_costo_usd
create or replace view public.v_inventario_admin as
    select
        id_item, nombre, rareza, tipo_item, precio_vbucks,
        precio_venta_usd, stock_disponible, imagen_url, activo,
        creado_en, actualizado_en
    from public.inventario_cosmeticos;

-- ---------------------------------------------------------------------
-- inventario_costo_bitacora: solo CEO
-- ---------------------------------------------------------------------
create policy "solo_ceo_ve_bitacora_costos"
    on public.inventario_costo_bitacora for select
    using (public.es_ceo());

create policy "sistema_inserta_bitacora"
    on public.inventario_costo_bitacora for insert
    with check (public.es_staff());

-- ---------------------------------------------------------------------
-- cuentas_bots: staff completo
-- ---------------------------------------------------------------------
create policy "staff_gestiona_bots"
    on public.cuentas_bots for all
    using (public.es_staff())
    with check (public.es_staff());

-- ---------------------------------------------------------------------
-- pedidos: staff completo (Admin procesa, CEO todo)
-- ---------------------------------------------------------------------
create policy "staff_gestiona_pedidos"
    on public.pedidos for all
    using (public.es_staff())
    with check (public.es_staff());

-- ---------------------------------------------------------------------
-- ventas_contabilidad: SOLO CEO. Admin no tiene acceso alguno (ni lectura).
-- Insert se hace vía función RPC security definer, no directo.
-- ---------------------------------------------------------------------
create policy "solo_ceo_lee_contabilidad"
    on public.ventas_contabilidad for select
    using (public.es_ceo());

create policy "solo_ceo_elimina_contabilidad"
    on public.ventas_contabilidad for delete
    using (public.es_ceo());

-- No se define policy de UPDATE a propósito: tabla inmutable (nadie puede editar).
-- INSERT se restringe a la función RPC 'completar_pedido' (security definer),
-- por lo que no se otorga policy de insert directa a los clientes de la API.
