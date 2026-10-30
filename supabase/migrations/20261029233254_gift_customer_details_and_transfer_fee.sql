alter table public.clientes
  add column if not exists epic_id text not null default '',
  add column if not exists discord_id text not null default '',
  add column if not exists compra_regalo boolean not null default false,
  add column if not exists compra_cosmeticos_regalo boolean not null default false;

alter table public.pedidos
  add column if not exists cuentas_agregadas text[] not null default '{}',
  add column if not exists monto_recibido numeric(12,2),
  add column if not exists comision numeric(12,2) not null default 0,
  add column if not exists notas text;

alter type public.metodo_pago_enum add value if not exists 'Binance';
alter type public.metodo_pago_enum add value if not exists 'Binance Giftcard';
alter type public.metodo_pago_enum add value if not exists 'Xbox Giftcard';
alter type public.metodo_pago_enum add value if not exists 'Remitly';
alter type public.metodo_pago_enum add value if not exists 'Bybit';
alter type public.metodo_pago_enum add value if not exists 'Airtm';
alter type public.metodo_pago_enum add value if not exists 'OXXO';
alter type public.metodo_pago_enum add value if not exists 'Transferencia MX';