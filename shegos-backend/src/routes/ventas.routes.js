const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/ventas.controller');

router.use(requireAuth, requireRole('CEO')); // TODO el módulo contable: solo CEO

router.get('/', ctrl.listarVentas);
router.post('/manual', ctrl.registrarVentaManual);
router.delete('/:id', ctrl.eliminarVenta);

module.exports = router;
