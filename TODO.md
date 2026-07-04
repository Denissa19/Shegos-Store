# Plan de Integración PayPal Checkout

## Pasos a completar
- [x] 1. Agregar SDK de PayPal y estilos CSS en `<head>`
- [x] 2. Reemplazar contenedor estático de PayPal por botones dinámicos
- [x] 3. Agregar variables globales para guardar datos de transacción PayPal
- [x] 4. Implementar función `renderPayPalButtons()` con `createOrder`, `onApprove`, `onError`
- [x] 5. Actualizar `mostrarInfoPago()` para renderizar botones al seleccionar PayPal
- [x] 6. Actualizar `enviarPedidoFinal()` para incluir ID de transacción en mensaje de WhatsApp
- [x] 7. Eliminar sección Cuentas STW
- [x] 8. Integrar selector de divisa USD/MXN