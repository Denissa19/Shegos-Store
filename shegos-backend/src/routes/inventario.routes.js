const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/inventario.controller');

router.use(requireAuth); // todo el módulo requiere sesión de staff

router.get('/', requireRole('CEO', 'Admin'), ctrl.listarInventario);
router.get('/:id', requireRole('CEO', 'Admin'), ctrl.obtenerItem);
router.post('/', requireRole('CEO', 'Admin'), ctrl.crearItem);
router.patch('/:id', requireRole('CEO', 'Admin'), ctrl.actualizarItem);
router.delete('/:id', requireRole('CEO'), ctrl.eliminarItem); // eliminación: solo CEO
router.post('/bulk', requireRole('CEO', 'Admin'), ctrl.actualizacionMasiva);

module.exports = router;
