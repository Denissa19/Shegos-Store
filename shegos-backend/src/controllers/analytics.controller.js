const { supabaseAdmin } = require('../config/supabaseClient');
const asyncHandler = require('../utils/asyncHandler');

// Resuelve un rango de fechas a partir de parámetros flexibles:
// ?periodo=mes_actual | mes_anterior | anio_actual | personalizado&desde=&hasta=
function resolverRango({ periodo, desde, hasta }) {
  const ahora = new Date();

  if (periodo === 'personalizado' && desde && hasta) {
    return { fecha_inicio: new Date(desde), fecha_fin: new Date(hasta) };
  }

  if (periodo === 'mes_anterior') {
    const inicio = new Date(ahora.getFullYear(), ahora.getMonth() - 1, 1);
    const fin = new Date(ahora.getFullYear(), ahora.getMonth(), 1);
    return { fecha_inicio: inicio, fecha_fin: fin };
  }

  if (periodo === 'anio_actual') {
    return {
      fecha_inicio: new Date(ahora.getFullYear(), 0, 1),
      fecha_fin: new Date(ahora.getFullYear() + 1, 0, 1),
    };
  }

  // default: mes_actual
  return {
    fecha_inicio: new Date(ahora.getFullYear(), ahora.getMonth(), 1),
    fecha_fin: new Date(ahora.getFullYear(), ahora.getMonth() + 1, 1),
  };
}

// GET /api/analytics/kpis  (SOLO CEO)
// Query params: periodo=mes_actual|mes_anterior|anio_actual|personalizado, desde, hasta
const obtenerKPIs = asyncHandler(async (req, res) => {
  const { fecha_inicio, fecha_fin } = resolverRango(req.query);

  const { data, error } = await supabaseAdmin.rpc('kpis_financieros', {
    p_fecha_inicio: fecha_inicio.toISOString(),
    p_fecha_fin: fecha_fin.toISOString(),
  });

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.json(data?.[0] ?? { ingresos_brutos: 0, costos_totales: 0, ganancia_neta: 0, roi_porcentaje: 0 });
});

// GET /api/analytics/serie  (SOLO CEO)
// Devuelve arreglo listo para Chart.js: [{periodo, ingresos, costos, ganancias}]
const obtenerSerieFinanciera = asyncHandler(async (req, res) => {
  const { granularidad = 'diaria', anio } = req.query;

  if (granularidad === 'mensual') {
    const anioObjetivo = anio ? Number(anio) : new Date().getFullYear();
    const { data, error } = await supabaseAdmin.rpc('serie_financiera_mensual', { p_anio: anioObjetivo });
    if (error) throw Object.assign(new Error(error.message), { status: 400 });
    return res.json({ granularidad: 'mensual', anio: anioObjetivo, serie: data });
  }

  const { fecha_inicio, fecha_fin } = resolverRango(req.query);
  const { data, error } = await supabaseAdmin.rpc('serie_financiera_diaria', {
    p_fecha_inicio: fecha_inicio.toISOString(),
    p_fecha_fin: fecha_fin.toISOString(),
  });

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.json({ granularidad: 'diaria', serie: data });
});

// GET /api/analytics/resumen-operativo  (Admin y CEO)
// Sin costos ni ganancias — solo operativa del día/mes.
const obtenerResumenOperativo = asyncHandler(async (req, res) => {
  const { fecha_inicio, fecha_fin } = resolverRango(req.query);

  const { data, error } = await supabaseAdmin.rpc('resumen_operativo_admin', {
    p_fecha_inicio: fecha_inicio.toISOString(),
    p_fecha_fin: fecha_fin.toISOString(),
  });

  if (error) throw Object.assign(new Error(error.message), { status: 400 });
  res.json(data?.[0] ?? { pedidos_completados: 0, pedidos_pendientes: 0, unidades_vendidas: 0 });
});

module.exports = { obtenerKPIs, obtenerSerieFinanciera, obtenerResumenOperativo };
