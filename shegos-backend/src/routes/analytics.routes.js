const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/analytics.controller');

router.use(requireAuth);

// Financieros completos: SOLO CEO
router.get('/kpis', requireRole('CEO'), ctrl.obtenerKPIs);
router.get('/serie', requireRole('CEO'), ctrl.obtenerSerieFinanciera);

// Operativo sin datos financieros: Admin y CEO
router.get('/resumen-operativo', requireRole('CEO', 'Admin'), ctrl.obtenerResumenOperativo);

module.exports = router;
