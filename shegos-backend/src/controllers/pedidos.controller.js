const { supabaseAdmin } = require('../config/supabaseClient');
const asyncHandler = require('../utils/asyncHandler');

// GET /api/pedidos  (staff) - filtros por estado, epic_id, rango de fechas
const listarPedidos = asyncHandler(async (req, res) => {
  const { estado, epic_id_cliente, desde, hasta, page = 1, limit = 30 } = req.query;

  let query = supabaseAdmin.from('pedidos').select('*', { count: 'exact' });

  if (estado) query = query.eq('estado', estado);
  if (epic_id_cliente) query = query.eq('epic_id_cliente', epic_id_cliente);
  if (desde) query = query.gte('creado_en', desde);
  if (hasta) query = query.lt('creado_en', hasta);

  const from = (Number(page) - 1) * Number(limit);
  const to = from + Number(limit) - 1;
  query = query.order('creado_en', { ascending: false }).range(from, to);

  const { data, error, count } = await query;
  if (error) throw Object.assign(new Error(error.message), { status: 400 });

  res.json({ pedidos: data, total: count, page: Number(page), limit: Number(limit) });
});

// GET /api/pedidos/:id
const obtenerPedido = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { data, error } = await supabaseAdmin.from('pedidos').select('*').eq('id_pedido', id).single();
  if (error) throw Object.assign(new Error('Pedido no encontrado'), { status: 404 });
  res.json(data);
});

// POST /api/pedidos  (público desde el frontend de la tienda — sin auth de staff)
const crearPedido = asyncHandler(async (req, res) => {
  const { nombre_cliente, telefono, epic_id_cliente, productos, total_usd, metodo_pago, comprobante_url } = req.body;

  if (!nombre_cliente || !epic_id_cliente || !Array.isArray(productos) || productos.length === 0 || !total_usd || !metodo_pago) {
    return res.status(400).json({ error: 'Faltan campos obligatorios del pedido' });
  }

  const { data, error } = await supabaseAdmin
    .from('pedidos')
    .insert({
      nombre_cliente, telefono, epic_id_cliente, productos,
      total_usd, metodo_pago, comprobante_url, estado: 'Pendiente',
    })
    .select()
    .single();

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.status(201).json(data);
});

// PATCH /api/pedidos/:id/estado  (staff) — cambios simples de estado (Pendiente <-> En Proceso <-> Cancelado)
const actualizarEstadoPedido = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { estado } = req.body;

  const estadosValidos = ['Pendiente', 'En Proceso', 'Cancelado'];
  if (!estadosValidos.includes(estado)) {
    return res.status(400).json({ error: `Estado inválido. Use este endpoint solo para: ${estadosValidos.join(', ')}. Para completar use /completar` });
  }

  const { data, error } = await supabaseAdmin
    .from('pedidos')
    .update({ estado })
    .eq('id_pedido', id)
    .select()
    .single();

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.json(data);
});

// POST /api/pedidos/:id/completar  (staff)
// Dispara la función RPC transaccional: descuenta stock, asigna bot,
// y mueve los datos financieros a ventas_contabilidad.
const completarPedido = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { id_bot, tasa_cambio } = req.body;

  const { data, error } = await supabaseAdmin.rpc('completar_pedido', {
    p_id_pedido: id,
    p_id_bot: id_bot ?? null,
    p_tasa_cambio: tasa_cambio ?? null,
    p_usuario: req.user.id,
  });

  if (error) throw Object.assign(new Error(error.message), { status: 400 });

  // El Admin no debe ver el detalle financiero de la venta resultante
  if (req.user.rol !== 'CEO' && data) {
    const { costos_totales_usd, ganancias_netas_usd, ...seguro } = data;
    return res.json({ mensaje: 'Pedido completado exitosamente', venta: seguro });
  }

  res.json({ mensaje: 'Pedido completado exitosamente', venta: data });
});

module.exports = {
  listarPedidos,
  obtenerPedido,
  crearPedido,
  actualizarEstadoPedido,
  completarPedido,
};
