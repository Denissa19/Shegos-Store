const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/analytics.controller');
const { rateLimit } = require('express-rate-limit');

router.use(requireAuth);

// Financieros completos: SOLO CEO
router.get('/kpis', requireRole('CEO'), ctrl.obtenerKPIs);
router.get('/serie', requireRole('CEO'), ctrl.obtenerSerieFinanciera);

// Operativo sin datos financieros: Admin y CEO
router.get('/resumen-operativo', requireRole('CEO', 'Admin'), ctrl.obtenerResumenOperativo);
router.post('/informe-ventas-ia', requireRole('CEO', 'Admin'), rateLimit({ windowMs: 15 * 60 * 1000, limit: 8, standardHeaders: 'draft-7', legacyHeaders: false }), ctrl.generarInformeVentasIA);

module.exports = router;
