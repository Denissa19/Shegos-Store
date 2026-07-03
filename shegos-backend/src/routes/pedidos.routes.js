const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/pedidos.controller');

// Público: el checkout del frontend crea el pedido sin sesión de staff.
router.post('/', ctrl.crearPedido);

// A partir de aquí, todo requiere sesión de staff.
router.get('/', requireAuth, requireRole('CEO', 'Admin'), ctrl.listarPedidos);
router.get('/:id', requireAuth, requireRole('CEO', 'Admin'), ctrl.obtenerPedido);
router.patch('/:id/estado', requireAuth, requireRole('CEO', 'Admin'), ctrl.actualizarEstadoPedido);
router.post('/:id/completar', requireAuth, requireRole('CEO', 'Admin'), ctrl.completarPedido);

module.exports = router;
