const router = require('express').Router();
const { requireAuth, requireRole } = require('../middleware/auth');
const ctrl = require('../controllers/bots.controller');

router.use(requireAuth);

router.get('/', requireRole('CEO', 'Admin'), ctrl.listarBots);
router.post('/', requireRole('CEO', 'Admin'), ctrl.crearBot);
router.patch('/:id', requireRole('CEO', 'Admin'), ctrl.actualizarBot);
router.delete('/:id', requireRole('CEO'), ctrl.eliminarBot);

module.exports = router;
