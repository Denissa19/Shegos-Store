require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const errorHandler = require('./middleware/errorHandler');
const inventarioRoutes = require('./routes/inventario.routes');
const botsRoutes = require('./routes/bots.routes');
const pedidosRoutes = require('./routes/pedidos.routes');
const ventasRoutes = require('./routes/ventas.routes');
const analyticsRoutes = require('./routes/analytics.routes');

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.FRONTEND_ORIGIN || '*' }));
app.use(express.json({ limit: '2mb' })); // suficiente para comprobantes en base64 moderados
app.use(morgan('combined'));

// Rate limit general (protege contra abuso, especialmente en /pedidos que es público)
app.use(
  rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 300,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

app.get('/health', (req, res) => res.json({ status: 'ok', servicio: 'Shegos Store API' }));

app.use('/api/inventario', inventarioRoutes);
app.use('/api/bots', botsRoutes);
app.use('/api/pedidos', pedidosRoutes);
app.use('/api/ventas', ventasRoutes);
app.use('/api/analytics', analyticsRoutes);

app.use((req, res) => res.status(404).json({ error: 'Ruta no encontrada' }));
app.use(errorHandler);

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Shegos Store API escuchando en puerto ${PORT}`));
