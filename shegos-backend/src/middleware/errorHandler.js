function errorHandler(err, req, res, next) { // eslint-disable-line no-unused-vars
  console.error('[ERROR]', err.message, err.stack ? `\n${err.stack}` : '');

  const status = err.status || 500;
  const message =
    status === 500 ? 'Error interno del servidor' : err.message || 'Error en la solicitud';

  res.status(status).json({
    error: message,
    ...(process.env.NODE_ENV !== 'production' && { detalle: err.message }),
  });
}

module.exports = errorHandler;
