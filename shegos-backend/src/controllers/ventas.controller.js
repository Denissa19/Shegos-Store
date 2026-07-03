const { supabaseAdmin } = require('../config/supabaseClient');
const asyncHandler = require('../utils/asyncHandler');

// GET /api/ventas  (SOLO CEO)
const listarVentas = asyncHandler(async (req, res) => {
  const { desde, hasta, page = 1, limit = 50 } = req.query;

  let query = supabaseAdmin.from('ventas_contabilidad').select('*', { count: 'exact' });
  if (desde) query = query.gte('fecha_exacta', desde);
  if (hasta) query = query.lt('fecha_exacta', hasta);

  const from = (Number(page) - 1) * Number(limit);
  const to = from + Number(limit) - 1;
  query = query.order('fecha_exacta', { ascending: false }).range(from, to);

  const { data, error, count } = await query;
  if (error) throw Object.assign(new Error(error.message), { status: 400 });

  res.json({ ventas: data, total: count, page: Number(page), limit: Number(limit) });
});

// POST /api/ventas/manual  (SOLO CEO) — ventas cerradas vía Discord/WhatsApp
const registrarVentaManual = asyncHandler(async (req, res) => {
  const { ingresos_usd, costos_usd, tasa_cambio, notas } = req.body;

  if (ingresos_usd === undefined || costos_usd === undefined) {
    return res.status(400).json({ error: 'ingresos_usd y costos_usd son obligatorios' });
  }

  const { data, error } = await supabaseAdmin.rpc('registrar_venta_manual', {
    p_ingresos_usd: ingresos_usd,
    p_costos_usd: costos_usd,
    p_tasa_cambio: tasa_cambio ?? null,
    p_notas: notas ?? null,
    p_usuario: req.user.id,
  });

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.status(201).json(data);
});

// DELETE /api/ventas/:id  (SOLO CEO) — corrección de registros contables erróneos
const eliminarVenta = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { error } = await supabaseAdmin.from('ventas_contabilidad').delete().eq('id_venta', id);
  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.status(204).send();
});

module.exports = { listarVentas, registrarVentaManual, eliminarVenta };
