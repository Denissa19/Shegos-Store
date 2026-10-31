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


const REPORT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    executiveSummary: { type: 'string' },
    strengths: { type: 'array', items: { type: 'object', additionalProperties: false, properties: { finding: { type: 'string' }, evidence: { type: 'string' }, action: { type: 'string' } }, required: ['finding', 'evidence', 'action'] } },
    weaknesses: { type: 'array', items: { type: 'object', additionalProperties: false, properties: { finding: { type: 'string' }, evidence: { type: 'string' }, risk: { type: 'string' } }, required: ['finding', 'evidence', 'risk'] } },
    opportunities: { type: 'array', items: { type: 'object', additionalProperties: false, properties: { idea: { type: 'string' }, basis: { type: 'string' }, test: { type: 'string' }, successMetric: { type: 'string' } }, required: ['idea', 'basis', 'test', 'successMetric'] } },
    risks: { type: 'array', items: { type: 'object', additionalProperties: false, properties: { risk: { type: 'string' }, evidence: { type: 'string' }, mitigation: { type: 'string' } }, required: ['risk', 'evidence', 'mitigation'] } },
    marketStrategies: { type: 'array', items: { type: 'object', additionalProperties: false, properties: { strategy: { type: 'string' }, target: { type: 'string' }, channel: { type: 'string' }, experiment: { type: 'string' }, kpi: { type: 'string' } }, required: ['strategy', 'target', 'channel', 'experiment', 'kpi'] } },
    actionPlan: { type: 'array', items: { type: 'object', additionalProperties: false, properties: { timeframe: { type: 'string', enum: ['0-30 días', '31-60 días', '61-90 días'] }, priority: { type: 'string', enum: ['Alta', 'Media', 'Baja'] }, action: { type: 'string' }, owner: { type: 'string' }, metric: { type: 'string' }, successCriteria: { type: 'string' } }, required: ['timeframe', 'priority', 'action', 'owner', 'metric', 'successCriteria'] } },
    watchNextPeriod: { type: 'array', items: { type: 'string' } },
    dataLimitations: { type: 'array', items: { type: 'string' } }
  },
  required: ['executiveSummary', 'strengths', 'weaknesses', 'opportunities', 'risks', 'marketStrategies', 'actionPlan', 'watchNextPeriod', 'dataLimitations']
};

function boundedText(value, max = 120) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}
function finiteNonNegative(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? Math.round(number * 100) / 100 : 0;
}
function sanitizeSalesSummary(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  const metric = (source, keys) => Object.fromEntries(keys.map(key => [key, finiteNonNegative(source?.[key])]));
  return {
    period: boundedText(input.period, 80),
    previousPeriod: boundedText(input.previousPeriod, 80),
    currency: boundedText(input.currency, 24),
    current: metric(input.current, ['sales', 'gross', 'averageTicket', 'net', 'fees', 'activeDays', 'periodDays']),
    previous: metric(input.previous, ['sales', 'gross', 'net']),
    products: Array.isArray(input.products) ? input.products.slice(0, 8).map(x => ({ name: boundedText(x?.name), sales: finiteNonNegative(x?.sales), gross: finiteNonNegative(x?.gross) })) : [],
    paymentMix: Array.isArray(input.paymentMix) ? input.paymentMix.slice(0, 8).map(x => ({ method: boundedText(x?.method), sales: finiteNonNegative(x?.sales), sharePercent: finiteNonNegative(x?.sharePercent) })) : [],
    weekdayPattern: Array.isArray(input.weekdayPattern) ? input.weekdayPattern.slice(0, 7).map(x => ({ day: boundedText(x?.day, 24), sales: finiteNonNegative(x?.sales), occurrences: finiteNonNegative(x?.occurrences), averageSales: finiteNonNegative(x?.averageSales) })) : [],
    repeatCustomers: finiteNonNegative(input.repeatCustomers)
  };
}

const generarInformeVentasIA = asyncHandler(async (req, res) => {
  if (!process.env.OPENAI_API_KEY) {
    return res.status(503).json({ error: 'El análisis con IA aún no está configurado en el servidor.' });
  }
  const summary = sanitizeSalesSummary(req.body);
  if (!summary || !summary.period || summary.current.periodDays <= 0) {
    return res.status(400).json({ error: 'El resumen del período no es válido.' });
  }

  const systemPrompt = [
    'Eres analista senior de comercio digital y estrategia de marketing para Shegos Store, una tienda gamer.',
    'Escribe siempre en español claro y genera recomendaciones concretas, priorizadas y adaptadas a las métricas suministradas.',
    'Usa exclusivamente los datos incluidos. No inventes hechos de mercado, márgenes, conversiones, causas ni datos ausentes.',
    'Separa hallazgos observados de hipótesis. Si hay pocos datos, dilo y propone experimentos pequeños y medibles.',
    'Relaciona cada punto fuerte, debilidad, oportunidad, riesgo y estrategia con una evidencia o explica explícitamente la limitación.',
    'El plan debe ser ejecutable en ventanas de 0-30, 31-60 y 61-90 días, con responsable sugerido, KPI y criterio de éxito.',
    'No incluyas datos personales. Limita cada lista a 3-5 elementos, con frases concisas y específicas.',
    'No recomiendes descuentos sin validar margen. Evita afirmaciones causales cuando los datos solo muestran correlación.'
  ].join(' ');

  let upstream;
  try {
    upstream = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: process.env.OPENAI_MODEL || 'gpt-6-astra',
        store: false,
        max_output_tokens: 3000,
        input: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: JSON.stringify(summary) }
        ],
        text: { format: { type: 'json_schema', name: 'shegos_sales_strategy_report', strict: true, schema: REPORT_SCHEMA } }
      }),
      signal: AbortSignal.timeout(45000)
    });
  } catch (error) {
    console.error('OpenAI sales report request failed:', error.message);
    return res.status(502).json({ error: 'No se pudo generar el análisis con IA. Inténtalo de nuevo.' });
  }

  const result = await upstream.json().catch(() => ({}));
  if (!upstream.ok) {
    console.error('OpenAI sales report response:', upstream.status, result?.error?.code || result?.error?.type || 'upstream_error');
    return res.status(upstream.status === 429 ? 429 : 502).json({ error: 'El proveedor de IA no pudo generar el informe. Inténtalo de nuevo.' });
  }
  const outputText = (result.output || []).flatMap(item => item.content || []).find(item => item.type === 'output_text')?.text;
  if (!outputText) return res.status(502).json({ error: 'La IA devolvió un informe vacío. Inténtalo de nuevo.' });
  let analysis;
  try { analysis = JSON.parse(outputText); }
  catch (error) { console.error('Invalid AI report JSON:', error.message); return res.status(502).json({ error: 'No se pudo interpretar el informe generado.' }); }
  res.json({ analysis, model: result.model || process.env.OPENAI_MODEL || 'gpt-6-astra' });
});

module.exports = { obtenerKPIs, obtenerSerieFinanciera, obtenerResumenOperativo, generarInformeVentasIA };
