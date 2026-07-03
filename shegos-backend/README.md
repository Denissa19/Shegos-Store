# Shegos Store — Backend API

API REST en Node.js/Express + Supabase (Postgres) para el sistema de gifting
de cosméticos de Fortnite, gestión de inventario, bots de regalo, pedidos y
contabilidad con control de acceso por rol (CEO / Admin).

## 1. Instalación

```bash
cd shegos-backend
npm install
cp .env.example .env   # completar con tus credenciales de Supabase
npm run dev             # o npm start en producción
```

## 2. Base de datos

Ejecuta los scripts SQL **en orden** desde el SQL Editor de Supabase:

1. `sql/001_schema.sql` — tablas, tipos ENUM, índices, checks.
2. `sql/002_rls_policies.sql` — Row Level Security por rol.
3. `sql/003_functions_triggers.sql` — triggers de auditoría y la función
   transaccional `completar_pedido`.
4. `sql/004_analytics_rpc.sql` — funciones RPC para el dashboard.

Después crea manualmente en `auth.users` (Supabase Auth) a tus usuarios
CEO/Admin, y una fila correspondiente en `usuarios_roles` con su `rol`.

## 3. Autenticación

Todas las rutas de staff esperan el header:

```
Authorization: Bearer <supabase_access_token>
```

El middleware `requireAuth` valida el JWT contra Supabase Auth y carga el rol
desde `usuarios_roles`. `requireRole('CEO')` o `requireRole('CEO','Admin')`
protege cada endpoint según el nivel de acceso.

## 4. Endpoints principales

| Método | Ruta | Rol | Descripción |
|---|---|---|---|
| GET | `/api/inventario` | CEO, Admin | Lista con filtros (rareza, tipo, búsqueda) |
| POST | `/api/inventario` | CEO, Admin | Crea ítem (costo solo lo fija CEO) |
| PATCH | `/api/inventario/:id` | CEO, Admin | Edita ítem (Admin no puede tocar costo) |
| DELETE | `/api/inventario/:id` | **CEO** | Elimina ítem |
| POST | `/api/inventario/bulk` | CEO, Admin | Actualización masiva de precio/stock |
| GET/POST/PATCH/DELETE | `/api/bots` | CEO, Admin (delete: CEO) | Cuentas bot de regalo |
| POST | `/api/pedidos` | Público | Checkout del frontend crea el pedido |
| GET | `/api/pedidos` | CEO, Admin | Lista pedidos con filtros |
| PATCH | `/api/pedidos/:id/estado` | CEO, Admin | Cambia a En Proceso / Cancelado |
| POST | `/api/pedidos/:id/completar` | CEO, Admin | Ejecuta la transacción completa (stock, bot, contabilidad) |
| GET/POST/DELETE | `/api/ventas` | **CEO** | Contabilidad histórica |
| GET | `/api/analytics/kpis` | **CEO** | Ingresos, costos, ganancia neta, ROI |
| GET | `/api/analytics/serie` | **CEO** | Serie diaria/mensual para gráficos |
| GET | `/api/analytics/resumen-operativo` | CEO, Admin | Pedidos/unidades sin datos financieros |

## 5. Filtros temporales (analytics)

Query params comunes: `?periodo=mes_actual|mes_anterior|anio_actual|personalizado&desde=...&hasta=...`

Ejemplo:
```
GET /api/analytics/kpis?periodo=personalizado&desde=2026-01-01&hasta=2026-07-01
GET /api/analytics/serie?granularidad=mensual&anio=2026
```

## 6. Estructura de respuesta para gráficos

`GET /api/analytics/serie` responde:

```json
{
  "granularidad": "diaria",
  "serie": [
    { "periodo": "2026-06-01", "ingresos": 320.50, "costos": 180.00, "ganancias": 140.50 },
    { "periodo": "2026-06-02", "ingresos": 210.00, "costos": 95.00,  "ganancias": 115.00 }
  ]
}
```

Lista directamente mapeable a Chart.js/ApexCharts:
```js
labels: serie.map(d => d.periodo),
datasets: [
  { label: 'Ingresos',  data: serie.map(d => d.ingresos) },
  { label: 'Costos',    data: serie.map(d => d.costos) },
  { label: 'Ganancias', data: serie.map(d => d.ganancias) },
]
```

`GET /api/analytics/kpis` responde:
```json
{ "ingresos_brutos": 4200.75, "costos_totales": 2100.00, "ganancia_neta": 2100.75, "roi_porcentaje": 100.04 }
```

## 7. Seguridad por capas

1. **Middleware RBAC** (`requireAuth` + `requireRole`) — primera barrera en la API.
2. **RLS de Postgres** — segunda barrera a nivel de fila, activa aunque alguien
   golpee la base directamente con la anon key.
3. **Blindaje de campo**: `precio_costo_usd` se elimina de las respuestas JSON
   antes de enviarlas a un Admin, y el endpoint bulk/patch ignora ese campo
   si quien llama no es CEO.
4. **Bitácora automática** (`inventario_costo_bitacora`): cualquier cambio de
   costo queda registrado con `modificado_por` vía trigger.
5. **Tabla contable inmutable**: `ventas_contabilidad` no tiene policy de
   UPDATE; solo se inserta vía función `security definer` y solo CEO puede
   eliminar registros erróneos.

## 8. Estructura del proyecto

```
shegos-backend/
├── sql/
│   ├── 001_schema.sql
│   ├── 002_rls_policies.sql
│   ├── 003_functions_triggers.sql
│   └── 004_analytics_rpc.sql
├── src/
│   ├── config/supabaseClient.js
│   ├── middleware/{auth.js, errorHandler.js}
│   ├── controllers/{inventario,bots,pedidos,ventas,analytics}.controller.js
│   ├── routes/{inventario,bots,pedidos,ventas,analytics}.routes.js
│   ├── utils/asyncHandler.js
│   └── server.js
├── package.json
└── .env.example
```

## 9. Nota sobre el frontend adjunto

Los archivos `index.html` y `admin.html` que enviaste se usaron como
referencia de los flujos de datos (catálogo por rareza, carrito, métodos de
pago, sincronización con Epic ID). Este backend expone los endpoints
necesarios para que ese frontend deje de depender de datos estáticos y
consuma la API real; si quieres, puedo ayudarte también a cablear las
llamadas `fetch` desde esos HTML hacia estos endpoints.
