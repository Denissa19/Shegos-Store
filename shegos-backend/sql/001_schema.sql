-- =====================================================================
-- SHEGOS STORE - ESQUEMA PRINCIPAL DE BASE DE DATOS (Supabase/Postgres)
-- =====================================================================
-- Ejecutar en orden: 001_schema.sql -> 002_rls_policies.sql
--                     -> 003_functions_triggers.sql -> 004_analytics_rpc.sql

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. USUARIOS_ROLES
-- ---------------------------------------------------------------------
-- Se apoya en auth.users de Supabase (uuid del usuario autenticado).
create type rol_usuario as enum ('CEO', 'Admin');

create table if not exists public.usuarios_roles (
    id              uuid primary key references auth.users(id) on delete cascade,
    nombre_completo text not null,
    rol             rol_usuario not null default 'Admin',
    activo          boolean not null default true,
    creado_en       timestamptz not null default now(),
    actualizado_en  timestamptz not null default now()
);

create index if not exists idx_usuarios_roles_rol on public.usuarios_roles(rol);

-- ---------------------------------------------------------------------
-- 2. INVENTARIO_COSMETICOS
-- ---------------------------------------------------------------------
create type rareza_item as enum (
    'Comun', 'Poco Comun', 'Raro', 'Epico', 'Legendario',
    'Mitico', 'Exotico', 'Serie de Ídolos', 'Serie Oscura',
    'Serie Marvel', 'Serie DC', 'Serie Gaming Legends', 'Serie Icon'
);

create type tipo_item as enum (
    'Skin', 'Mochila', 'Pico', 'Gesto', 'Ala Delta', 'Estela',
    'Envoltura', 'Pancarta', 'Musica Lobby', 'Bundle', 'Pavos', 'Clave Digital'
);

create table if not exists public.inventario_cosmeticos (
    id_item             uuid primary key default gen_random_uuid(),
    nombre              text not null,
    rareza              rareza_item not null,
    tipo_item           tipo_item not null,
    precio_vbucks       integer check (precio_vbucks >= 0),
    precio_venta_usd    numeric(10,2) not null check (precio_venta_usd >= 0),
    precio_costo_usd    numeric(10,2) not null check (precio_costo_usd >= 0), -- BLINDADO: solo CEO
    stock_disponible    integer not null default 0 check (stock_disponible >= 0),
    imagen_url          text,
    activo              boolean not null default true,
    creado_por          uuid references public.usuarios_roles(id),
    creado_en           timestamptz not null default now(),
    actualizado_en      timestamptz not null default now()
);

create index if not exists idx_inventario_nombre on public.inventario_cosmeticos using gin (to_tsvector('spanish', nombre));
create index if not exists idx_inventario_rareza on public.inventario_cosmeticos(rareza);
create index if not exists idx_inventario_tipo on public.inventario_cosmeticos(tipo_item);
create index if not exists idx_inventario_activo on public.inventario_cosmeticos(activo);

-- Bitácora de cambios sobre el costo de adquisición (auditoría obligatoria)
create table if not exists public.inventario_costo_bitacora (
    id              uuid primary key default gen_random_uuid(),
    id_item         uuid not null references public.inventario_cosmeticos(id_item) on delete cascade,
    costo_anterior  numeric(10,2),
    costo_nuevo     numeric(10,2) not null,
    modificado_por  uuid references public.usuarios_roles(id),
    modificado_en   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. CUENTAS_BOTS
-- ---------------------------------------------------------------------
create type estado_agregacion as enum ('Pendiente', 'Agregado', 'Regalo Enviado', 'Bloqueado', 'Inactivo');

create table if not exists public.cuentas_bots (
    id_bot              uuid primary key default gen_random_uuid(),
    epic_id             text not null unique,
    alias               text,
    estado_agregacion   estado_agregacion not null default 'Pendiente',
    pavos_disponibles    integer not null default 0 check (pavos_disponibles >= 0),
    saldo_interno_usd   numeric(10,2) not null default 0 check (saldo_interno_usd >= 0),
    notas               text,
    activo              boolean not null default true,
    creado_en           timestamptz not null default now(),
    actualizado_en      timestamptz not null default now()
);

create index if not exists idx_bots_estado on public.cuentas_bots(estado_agregacion);
create index if not exists idx_bots_activo on public.cuentas_bots(activo);

-- ---------------------------------------------------------------------
-- 4. PEDIDOS
-- ---------------------------------------------------------------------
create type estado_pedido as enum ('Pendiente', 'En Proceso', 'Completado', 'Cancelado');
create type metodo_pago_enum as enum ('PayPal', 'Mercado Pago', 'SPEI', 'Cripto', 'Otro');

create table if not exists public.pedidos (
    id_pedido           uuid primary key default gen_random_uuid(),
    nombre_cliente      text not null,
    telefono            text,
    epic_id_cliente     text not null,
    productos           jsonb not null, -- [{id_item, nombre, cantidad, precio_unitario}]
    total_usd           numeric(10,2) not null check (total_usd >= 0),
    metodo_pago         metodo_pago_enum not null,
    comprobante_url     text,
    estado              estado_pedido not null default 'Pendiente',
    id_bot_asignado     uuid references public.cuentas_bots(id_bot),
    creado_en           timestamptz not null default now(),
    actualizado_en      timestamptz not null default now(),
    completado_en       timestamptz
);

create index if not exists idx_pedidos_estado on public.pedidos(estado);
create index if not exists idx_pedidos_epic_id on public.pedidos(epic_id_cliente);
create index if not exists idx_pedidos_creado_en on public.pedidos(creado_en desc);
create index if not exists idx_pedidos_productos_gin on public.pedidos using gin (productos);

-- ---------------------------------------------------------------------
-- 5. VENTAS_CONTABILIDAD (histórico inmutable)
-- ---------------------------------------------------------------------
create table if not exists public.ventas_contabilidad (
    id_venta            uuid primary key default gen_random_uuid(),
    id_pedido           uuid references public.pedidos(id_pedido),
    fecha_exacta         timestamptz not null default now(),
    ingresos_totales_usd numeric(10,2) not null check (ingresos_totales_usd >= 0),
    ingresos_moneda_local numeric(12,2),
    costos_totales_usd  numeric(10,2) not null check (costos_totales_usd >= 0),
    ganancias_netas_usd numeric(10,2) generated always as (ingresos_totales_usd - costos_totales_usd) stored,
    tasa_cambio_aplicada numeric(10,4),
    registrado_por       uuid references public.usuarios_roles(id),
    notas                text,
    -- Inmutabilidad: no se permiten updates, solo lectura y eliminación exclusiva de CEO (ver políticas RLS)
    creado_en            timestamptz not null default now()
);

create index if not exists idx_ventas_fecha on public.ventas_contabilidad(fecha_exacta desc);
create index if not exists idx_ventas_pedido on public.ventas_contabilidad(id_pedido);

comment on table public.ventas_contabilidad is 'Tabla inmutable de auditoría financiera. No editar registros, solo insertar. Eliminación restringida a CEO.';
