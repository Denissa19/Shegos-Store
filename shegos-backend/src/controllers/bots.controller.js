const { supabaseAdmin } = require('../config/supabaseClient');
const asyncHandler = require('../utils/asyncHandler');

const listarBots = asyncHandler(async (req, res) => {
  const { estado_agregacion, activo } = req.query;
  let query = supabaseAdmin.from('cuentas_bots').select('*').order('creado_en', { ascending: false });

  if (estado_agregacion) query = query.eq('estado_agregacion', estado_agregacion);
  if (activo !== undefined) query = query.eq('activo', activo === 'true');

  const { data, error } = await query;
  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.json(data);
});

const crearBot = asyncHandler(async (req, res) => {
  const { epic_id, alias, pavos_disponibles, saldo_interno_usd, notas } = req.body;
  if (!epic_id) return res.status(400).json({ error: 'epic_id es obligatorio' });

  const { data, error } = await supabaseAdmin
    .from('cuentas_bots')
    .insert({ epic_id, alias, pavos_disponibles: pavos_disponibles ?? 0, saldo_interno_usd: saldo_interno_usd ?? 0, notas })
    .select()
    .single();

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.status(201).json(data);
});

const actualizarBot = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { data, error } = await supabaseAdmin
    .from('cuentas_bots')
    .update(req.body)
    .eq('id_bot', id)
    .select()
    .single();

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.json(data);
});

const eliminarBot = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { error } = await supabaseAdmin.from('cuentas_bots').delete().eq('id_bot', id);
  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.status(204).send();
});

module.exports = { listarBots, crearBot, actualizarBot, eliminarBot };
