-- =====================================================================
-- SHEGOS STORE - TRIGGERS Y FUNCIONES DE NEGOCIO
-- =====================================================================

-- ---------------------------------------------------------------------
-- Trigger genérico: actualizar 'actualizado_en'
-- ---------------------------------------------------------------------
create or replace function public.set_actualizado_en()
returns trigger language plpgsql as $$
begin
    new.actualizado_en = now();
    return new;
end;
$$;

create trigger trg_usuarios_roles_updated
    before update on public.usuarios_roles
    for each row execute function public.set_actualizado_en();

create trigger trg_inventario_updated
    before update on public.inventario_cosmeticos
    for each row execute function public.set_actualizado_en();

create trigger trg_bots_updated
    before update on public.cuentas_bots
    for each row execute function public.set_actualizado_en();

create trigger trg_pedidos_updated
    before update on public.pedidos
    for each row execute function public.set_actualizado_en();

-- ---------------------------------------------------------------------
-- Trigger: registrar en bitácora cualquier cambio de precio_costo_usd
-- ---------------------------------------------------------------------
create or replace function public.log_cambio_costo()
returns trigger language plpgsql as $$
begin
    if (tg_op = 'UPDATE' and old.precio_costo_usd is distinct from new.precio_costo_usd)
       or (tg_op = 'INSERT') then
        insert into public.inventario_costo_bitacora (id_item, costo_anterior, costo_nuevo, modificado_por)
        values (
            new.id_item,
            case when tg_op = 'UPDATE' then old.precio_costo_usd else null end,
            new.precio_costo_usd,
            auth.uid()
        );
    end if;
    return new;
end;
$$;

create trigger trg_log_costo
    after insert or update on public.inventario_cosmeticos
    for each row execute function public.log_cambio_costo();

-- ---------------------------------------------------------------------
-- FUNCIÓN CLAVE: completar_pedido(id_pedido, id_bot, tasa_cambio)
-- Ejecuta atómicamente:
--   1. Verifica stock suficiente para cada producto del pedido.
--   2. Descuenta stock de inventario_cosmeticos.
--   3. Asigna la cuenta de bot que realizó el regalo.
--   4. Marca el pedido como 'Completado'.
--   5. Inserta el registro correspondiente en ventas_contabilidad
--      calculando ganancia neta = ingreso - costo de adquisición.
-- Es SECURITY DEFINER para poder insertar en ventas_contabilidad,
-- que no tiene policy de insert directa. El RBAC real (quién puede
-- llamar a esta función) se aplica en el middleware de la API.
-- ---------------------------------------------------------------------
create or replace function public.completar_pedido(
    p_id_pedido     uuid,
    p_id_bot        uuid,
    p_tasa_cambio   numeric default null,
    p_usuario       uuid default auth.uid()
)
returns public.ventas_contabilidad
language plpgsql
security definer
as $$
declare
    v_pedido        public.pedidos%rowtype;
    v_producto      jsonb;
    v_id_item       uuid;
    v_cantidad      integer;
    v_costo_item    numeric(10,2);
    v_costo_total   numeric(10,2) := 0;
    v_venta         public.ventas_contabilidad%rowtype;
begin
    select * into v_pedido from public.pedidos where id_pedido = p_id_pedido for update;

    if not found then
        raise exception 'Pedido % no encontrado', p_id_pedido;
    end if;

    if v_pedido.estado = 'Completado' then
        raise exception 'El pedido ya fue completado previamente';
    end if;

    -- Verificar stock y acumular costo total ANTES de mutar nada
    for v_producto in select * from jsonb_array_elements(v_pedido.productos)
    loop
        v_id_item  := (v_producto->>'id_item')::uuid;
        v_cantidad := (v_producto->>'cantidad')::integer;

        select precio_costo_usd, stock_disponible into v_costo_item, v_cantidad
        from public.inventario_cosmeticos
        where id_item = v_id_item
        for update;

        if not found then
            raise exception 'Ítem % no encontrado en inventario', v_id_item;
        end if;

        if v_cantidad < (v_producto->>'cantidad')::integer then
            raise exception 'Stock insuficiente para el ítem %', v_id_item;
        end if;

        v_costo_total := v_costo_total + (v_costo_item * (v_producto->>'cantidad')::integer);

        update public.inventario_cosmeticos
        set stock_disponible = stock_disponible - (v_producto->>'cantidad')::integer
        where id_item = v_id_item;
    end loop;

    -- Marcar cuenta bot como usada para el regalo
    if p_id_bot is not null then
        update public.cuentas_bots
        set estado_agregacion = 'Regalo Enviado'
        where id_bot = p_id_bot;
    end if;

    update public.pedidos
    set estado = 'Completado',
        id_bot_asignado = p_id_bot,
        completado_en = now()
    where id_pedido = p_id_pedido;

    insert into public.ventas_contabilidad (
        id_pedido, ingresos_totales_usd,
        ingresos_moneda_local, costos_totales_usd,
        tasa_cambio_aplicada, registrado_por
    ) values (
        p_id_pedido, v_pedido.total_usd,
        case when p_tasa_cambio is not null then v_pedido.total_usd * p_tasa_cambio else null end,
        v_costo_total, p_tasa_cambio, p_usuario
    )
    returning * into v_venta;

    return v_venta;
end;
$$;

-- ---------------------------------------------------------------------
-- FUNCIÓN: registrar_venta_manual (para ventas cerradas por Discord/WhatsApp,
-- sin pasar por el flujo de 'pedidos')
-- ---------------------------------------------------------------------
create or replace function public.registrar_venta_manual(
    p_ingresos_usd  numeric,
    p_costos_usd    numeric,
    p_tasa_cambio   numeric default null,
    p_notas         text default null,
    p_usuario       uuid default auth.uid()
)
returns public.ventas_contabilidad
language plpgsql
security definer
as $$
declare
    v_venta public.ventas_contabilidad%rowtype;
begin
    insert into public.ventas_contabilidad (
        ingresos_totales_usd, ingresos_moneda_local, costos_totales_usd,
        tasa_cambio_aplicada, registrado_por, notas
    ) values (
        p_ingresos_usd,
        case when p_tasa_cambio is not null then p_ingresos_usd * p_tasa_cambio else null end,
        p_costos_usd, p_tasa_cambio, p_usuario, p_notas
    )
    returning * into v_venta;

    return v_venta;
end;
$$;
