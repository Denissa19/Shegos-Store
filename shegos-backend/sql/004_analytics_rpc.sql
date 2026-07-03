-- =====================================================================
-- SHEGOS STORE - FUNCIONES ANALÍTICAS (Dashboard financiero)
-- =====================================================================
-- Todas security definer para poder leer ventas_contabilidad; el
-- control de "quién puede llamarlas" (solo CEO) se hace en el
-- middleware de la API antes de invocar el RPC.

-- ---------------------------------------------------------------------
-- kpis_financieros(fecha_inicio, fecha_fin)
-- Devuelve los 4 KPIs clave para el rango dado.
-- ---------------------------------------------------------------------
create or replace function public.kpis_financieros(
    p_fecha_inicio  timestamptz,
    p_fecha_fin     timestamptz
)
returns table (
    ingresos_brutos     numeric,
    costos_totales      numeric,
    ganancia_neta       numeric,
    roi_porcentaje       numeric
)
language sql
security definer
stable
as $$
    select
        coalesce(sum(ingresos_totales_usd), 0)                         as ingresos_brutos,
        coalesce(sum(costos_totales_usd), 0)                           as costos_totales,
        coalesce(sum(ganancias_netas_usd), 0)                          as ganancia_neta,
        case when coalesce(sum(costos_totales_usd), 0) = 0 then 0
             else round((sum(ganancias_netas_usd) / sum(costos_totales_usd)) * 100, 2)
        end as roi_porcentaje
    from public.ventas_contabilidad
    where fecha_exacta >= p_fecha_inicio and fecha_exacta < p_fecha_fin;
$$;

-- ---------------------------------------------------------------------
-- serie_financiera_diaria(fecha_inicio, fecha_fin)
-- Devuelve [{fecha, ingresos, costos, ganancias}] agrupado por día,
-- listo para Chart.js / ApexCharts.
-- ---------------------------------------------------------------------
create or replace function public.serie_financiera_diaria(
    p_fecha_inicio  timestamptz,
    p_fecha_fin     timestamptz
)
returns table (
    periodo     date,
    ingresos    numeric,
    costos      numeric,
    ganancias   numeric
)
language sql
security definer
stable
as $$
    select
        date_trunc('day', fecha_exacta)::date as periodo,
        sum(ingresos_totales_usd)  as ingresos,
        sum(costos_totales_usd)    as costos,
        sum(ganancias_netas_usd)   as ganancias
    from public.ventas_contabilidad
    where fecha_exacta >= p_fecha_inicio and fecha_exacta < p_fecha_fin
    group by 1
    order by 1;
$$;

-- ---------------------------------------------------------------------
-- serie_financiera_mensual(anio)
-- Devuelve [{mes, ingresos, costos, ganancias}] agrupado por mes de un año fiscal.
-- ---------------------------------------------------------------------
create or replace function public.serie_financiera_mensual(p_anio integer)
returns table (
    periodo     date,
    ingresos    numeric,
    costos      numeric,
    ganancias   numeric
)
language sql
security definer
stable
as $$
    select
        date_trunc('month', fecha_exacta)::date as periodo,
        sum(ingresos_totales_usd)  as ingresos,
        sum(costos_totales_usd)    as costos,
        sum(ganancias_netas_usd)   as ganancias
    from public.ventas_contabilidad
    where extract(year from fecha_exacta) = p_anio
    group by 1
    order by 1;
$$;

-- ---------------------------------------------------------------------
-- resumen_operativo_admin(fecha_inicio, fecha_fin)
-- Versión SIN datos de costos/ganancia para el rol Admin: solo
-- número de pedidos procesados y unidades vendidas. Nunca expone
-- precio_costo_usd ni ganancias.
-- ---------------------------------------------------------------------
create or replace function public.resumen_operativo_admin(
    p_fecha_inicio  timestamptz,
    p_fecha_fin     timestamptz
)
returns table (
    pedidos_completados integer,
    pedidos_pendientes  integer,
    unidades_vendidas   integer
)
language sql
security invoker -- corre con los permisos del staff que la invoca; solo lee 'pedidos'
stable
as $$
    select
        (select count(*)::integer from public.pedidos
            where estado = 'Completado' and completado_en >= p_fecha_inicio and completado_en < p_fecha_fin),
        (select count(*)::integer from public.pedidos
            where estado = 'Pendiente'),
        (select coalesce(sum((prod->>'cantidad')::integer), 0)::integer
            from public.pedidos, jsonb_array_elements(productos) as prod
            where estado = 'Completado' and completado_en >= p_fecha_inicio and completado_en < p_fecha_fin);
$$;
