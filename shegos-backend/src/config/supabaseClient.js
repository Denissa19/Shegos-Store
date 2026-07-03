const { createClient } = require('@supabase/supabase-js');

if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Faltan variables de entorno SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY');
}

// Cliente administrativo: usa la service_role key. Se usa SOLO en el backend.
// El RBAC real se aplica en middleware/auth.js antes de tocar la BD;
// las policies RLS de Postgres son la segunda capa de defensa.
const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { autoRefreshToken: false, persistSession: false } }
);

// Cliente "anon" usado únicamente para validar el JWT del usuario que llama.
const supabaseAuthClient = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

module.exports = { supabaseAdmin, supabaseAuthClient };
