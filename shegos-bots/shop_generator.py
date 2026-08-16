import asyncio
import logging
from playwright.async_api import async_playwright

logger = logging.getLogger(__name__)


class ShopGenerator:
    async def generate_shop_image(self, output_path: str = "shop.png"):
        """
        Captura la tienda de fortnite.gg completa.

        Fix respecto a la versión anterior:
        - fortnite.gg carga las imágenes de los cosméticos de forma "lazy"
          (solo cuando el elemento entra en el viewport). Antes solo se
          esperaba `networkidle` + 2s fijos SIN hacer scroll, así que
          cualquier ítem fuera de la pantalla inicial (2560x1440) nunca
          disparaba la carga de su imagen -> cosméticos/imágenes faltantes.
        - Ya no se fuerza `display:contents` / `grid-template-columns`
          sobre clases del sitio (.shop-section, .shop-row, .item-card).
          Si fortnite.gg les cambia el nombre a esas clases, el hack se
          rompe en silencio y corta ítems del layout. En vez de eso,
          dejamos el layout tal cual lo entrega el sitio y ajustamos el
          viewport al alto real del contenido antes de capturar.
        """
        async with async_playwright() as p:
            logger.info("Iniciando navegador para capturar la tienda...")
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context(viewport={'width': 2560, 'height': 1440})
            page = await context.new_page()

            await page.goto("https://fortnite.gg/shop", wait_until="networkidle", timeout=60000)

            shop_element = page.locator("#shop")
            if await shop_element.count() == 0:
                logger.error("❌ No se encontró el elemento #shop en fortnite.gg")
                await browser.close()
                return None

            # Ocultar solo elementos claramente ajenos al shop (header/footer/ads),
            # sin tocar la estructura interna de #shop para no romper el grid.
            await page.add_style_tag(content="""
                header, footer, .ads { display: none !important; }
                body { background-color: #0f172a !important; }
            """)

            # ── Forzar carga de todo el lazy-load ────────────────────────
            # Hacemos scroll incremental por TODA la altura de la página,
            # dando tiempo entre cada paso para que las imágenes que van
            # entrando al viewport disparen su carga.
            await self._scroll_full_page(page)

            # Esperar activamente a que las imágenes dentro de #shop
            # terminen de cargar (o se agote el timeout), reportando
            # cuántas quedaron rotas para poder diagnosticar.
            await self._wait_images_loaded(page)

            # Volver arriba del todo antes de capturar
            await page.evaluate("window.scrollTo(0, 0)")
            await asyncio.sleep(0.5)

            # Ajustar el viewport al alto real del contenido para que la
            # captura salga completa sin depender de hacks de CSS.
            content_height = await page.evaluate("document.documentElement.scrollHeight")
            await page.set_viewport_size({"width": 2560, "height": min(content_height, 20000)})
            await asyncio.sleep(0.3)

            await shop_element.screenshot(path=output_path)
            logger.info(f"✅ Imagen de la tienda generada en: {output_path}")
            await browser.close()
            return output_path

    async def _scroll_full_page(self, page, step: int = 1200, pause_ms: int = 350):
        """Baja por toda la página en pasos, esperando entre cada uno para
        darle tiempo al lazy-load de disparar la carga de imágenes."""
        total_height = await page.evaluate("document.documentElement.scrollHeight")
        current = 0
        # Límite de seguridad para no quedar en loop infinito si la página
        # sigue creciendo (contenido infinito / carga dinámica).
        max_iterations = 200
        iterations = 0

        while current < total_height and iterations < max_iterations:
            current += step
            await page.evaluate(f"window.scrollTo(0, {current})")
            await asyncio.sleep(pause_ms / 1000)
            # La altura puede crecer si el scroll dispara carga de más contenido
            total_height = await page.evaluate("document.documentElement.scrollHeight")
            iterations += 1

        logger.info(f"Scroll completo: {iterations} pasos, altura final {total_height}px.")

    async def _wait_images_loaded(self, page, timeout_ms: int = 15000, poll_ms: int = 300):
        """Espera a que todas las <img> dentro de #shop reporten `complete`
        y `naturalWidth > 0`. Loguea cuántas quedaron rotas al final."""
        waited = 0
        while waited < timeout_ms:
            pending = await page.evaluate("""
                () => {
                    const imgs = Array.from(document.querySelectorAll('#shop img'));
                    return imgs.filter(img => !img.complete || img.naturalWidth === 0).length;
                }
            """)
            if pending == 0:
                break
            await asyncio.sleep(poll_ms / 1000)
            waited += poll_ms

        broken = await page.evaluate("""
            () => {
                const imgs = Array.from(document.querySelectorAll('#shop img'));
                const total = imgs.length;
                const broken = imgs
                    .filter(img => !img.complete || img.naturalWidth === 0)
                    .map(img => img.src || img.getAttribute('data-src') || '(sin src)');
                return { total, broken };
            }
        """)

        total = broken.get("total", 0)
        rotas = broken.get("broken", [])
        if rotas:
            logger.warning(f"⚠️ {len(rotas)}/{total} imágenes no cargaron en la tienda:")
            for src in rotas[:20]:  # no inundar el log si son muchas
                logger.warning(f"    - {src}")
        else:
            logger.info(f"✅ Todas las imágenes cargaron correctamente ({total} en total).")
