const { supabaseAdmin, supabaseAuthClient } = require('../config/supabaseClient');

/**
 * Extrae y valida el JWT del header Authorization: Bearer <token>,
 * carga el rol del usuario desde 'usuarios_roles' y lo adjunta a req.user.
 */
async function requireAuth(req, res, next) {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (!token) {
      return res.status(401).json({ error: 'Token de autenticación no proporcionado' });
    }

    const { data: userData, error: userError } = await supabaseAuthClient.auth.getUser(token);
    if (userError || !userData?.user) {
      return res.status(401).json({ error: 'Token inválido o expirado' });
    }

    const { data: perfil, error: perfilError } = await supabaseAdmin
      .from('usuarios_roles')
      .select('id, nombre_completo, rol, activo')
      .eq('id', userData.user.id)
      .single();

    if (perfilError || !perfil) {
      return res.status(403).json({ error: 'Usuario sin perfil de roles asignado' });
    }

    if (!perfil.activo) {
      return res.status(403).json({ error: 'Usuario desactivado' });
    }

    req.user = {
      id: perfil.id,
      nombre: perfil.nombre_completo,
      rol: perfil.rol, // 'CEO' | 'Admin'
    };

    next();
  } catch (err) {
    next(err);
  }
}

/**
 * Middleware de fábrica: requireRole('CEO') o requireRole('CEO', 'Admin')
 */
function requireRole(...rolesPermitidos) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'No autenticado' });
    }
    if (!rolesPermitidos.includes(req.user.rol)) {
      return res.status(403).json({
        error: `Acceso denegado. Rol requerido: ${rolesPermitidos.join(' o ')}`,
      });
    }
    next();
  };
}

module.exports = { requireAuth, requireRole };
