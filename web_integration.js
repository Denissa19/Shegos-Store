import { supabase } from './supabaseClient.js';

/**
 * Inserta un nuevo pedido en la tabla 'pedidos' de Supabase.
 */
export async function guardarPedidoEnNube(cliente, productos, total) {
    const { data, error } = await supabase
        .from('pedidos')
        .insert([
            {
                nombre_cliente: cliente,
                productos: productos,
                total_usd: total,
                fecha: new Date().toISOString(),
                estado: 'Pendiente'
            }
        ]);

    if (error) {
        console.error("Error al guardar pedido en Supabase:", error);
        return null;
    }
    return data;
}

/**
 * Obtiene todos los pedidos de la base de datos, ordenados por fecha descendente.
 */
export async function obtenerPedidosDeNube() {
    const { data, error } = await supabase
        .from('pedidos')
        .select('*')
        .order('fecha', { ascending: false });

    if (error) {
        console.error("Error al obtener pedidos de Supabase:", error);
        return [];
    }
    return data;
}
