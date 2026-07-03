const { supabaseAdmin } = require('../config/supabaseClient');
const asyncHandler = require('../utils/asyncHandler');

// Campos que Admin NUNCA debe ver en las respuestas
const CAMPO_BLINDADO = 'precio_costo_usd';

function ocultarCostoSiAdmin(rol, item) {
  if (rol === 'CEO') return item;
  const { [CAMPO_BLINDADO]: _omit, ...resto } = item;
  return resto;
}

// GET /api/inventario  (staff)
const listarInventario = asyncHandler(async (req, res) => {
  const { rareza, tipo_item, activo, q, page = 1, limit = 50 } = req.query;

  let query = supabaseAdmin.from('inventario_cosmeticos').select('*', { count: 'exact' });

  if (rareza) query = query.eq('rareza', rareza);
  if (tipo_item) query = query.eq('tipo_item', tipo_item);
  if (activo !== undefined) query = query.eq('activo', activo === 'true');
  if (q) query = query.ilike('nombre', `%${q}%`);

  const from = (Number(page) - 1) * Number(limit);
  const to = from + Number(limit) - 1;
  query = query.order('creado_en', { ascending: false }).range(from, to);

  const { data, error, count } = await query;
  if (error) throw Object.assign(new Error(error.message), { status: 400 });

  const items = data.map((item) => ocultarCostoSiAdmin(req.user.rol, item));
  res.json({ items, total: count, page: Number(page), limit: Number(limit) });
});

// GET /api/inventario/:id
const obtenerItem = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { data, error } = await supabaseAdmin
    .from('inventario_cosmeticos')
    .select('*')
    .eq('id_item', id)
    .single();

  if (error) throw Object.assign(new Error('Ítem no encontrado'), { status: 404 });
  res.json(ocultarCostoSiAdmin(req.user.rol, data));
});

// POST /api/inventario  (CEO o Admin — costo blindado: solo CEO puede fijarlo != 0 en creación)
const crearItem = asyncHandler(async (req, res) => {
  const {
    nombre, rareza, tipo_item, precio_vbucks,
    precio_venta_usd, precio_costo_usd, stock_disponible, imagen_url,
  } = req.body;

  if (!nombre || !rareza || !tipo_item || precio_venta_usd === undefined) {
    return res.status(400).json({ error: 'Campos obligatorios: nombre, rareza, tipo_item, precio_venta_usd' });
  }

  if (req.user.rol !== 'CEO' && precio_costo_usd !== undefined) {
    return res.status(403).json({ error: 'Solo el CEO puede establecer el precio de costo de inversión' });
  }

  const payload = {
    nombre,
    rareza,
    tipo_item,
    precio_vbucks: precio_vbucks ?? null,
    precio_venta_usd,
    precio_costo_usd: req.user.rol === 'CEO' ? (precio_costo_usd ?? 0) : 0,
    stock_disponible: stock_disponible ?? 0,
    imagen_url: imagen_url ?? null,
    creado_por: req.user.id,
  };

  const { data, error } = await supabaseAdmin
    .from('inventario_cosmeticos')
    .insert(payload)
    .select()
    .single();

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.status(201).json(ocultarCostoSiAdmin(req.user.rol, data));
});

// PATCH /api/inventario/:id  (Admin puede editar todo excepto precio_costo_usd)
const actualizarItem = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const cambios = { ...req.body };

  if (req.user.rol !== 'CEO' && 'precio_costo_usd' in cambios) {
    delete cambios.precio_costo_usd; // blindado: Admin no puede tocarlo, se ignora silenciosamente
  }

  delete cambios.id_item; // inmutable

  const { data, error } = await supabaseAdmin
    .from('inventario_cosmeticos')
    .update(cambios)
    .eq('id_item', id)
    .select()
    .single();

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.json(ocultarCostoSiAdmin(req.user.rol, data));
});

// DELETE /api/inventario/:id  (SOLO CEO)
const eliminarItem = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { error } = await supabaseAdmin.from('inventario_cosmeticos').delete().eq('id_item', id);
  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.status(204).send();
});

// POST /api/inventario/bulk  (actualización masiva de precios/stock vía JSON)
// Body esperado: { items: [{ id_item, precio_venta_usd?, precio_costo_usd?, stock_disponible? }] }
const actualizacionMasiva = asyncHandler(async (req, res) => {
  const { items } = req.body;
  if (!Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: "Se espera un array 'items' no vacío" });
  }

  const resultados = [];
  for (const item of items) {
    const { id_item, ...cambios } = item;
    if (!id_item) continue;

    if (req.user.rol !== 'CEO') delete cambios.precio_costo_usd;

    const { data, error } = await supabaseAdmin
      .from('inventario_cosmeticos')
      .update(cambios)
      .eq('id_item', id_item)
      .select()
      .single();

    resultados.push(error ? { id_item, error: error.message } : ocultarCostoSiAdmin(req.user.rol, data));
  }

  res.json({ resultados });
});

module.exports = {
  listarInventario,
  obtenerItem,
  crearItem,
  actualizarItem,
  eliminarItem,
  actualizacionMasiva,
};
