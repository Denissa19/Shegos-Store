import asyncio
import logging
from playwright.async_api import async_playwright

logger = logging.getLogger(__name__)

class ShopGenerator:
    async def generate_shop_image(self, output_path: str = "shop.png"):
        """
        Captura la tienda de fortnite.gg configurando un layout de 16 columnas.
        """
        async with async_playwright() as p:
            logger.info("Iniciando navegador para capturar la tienda...")
            browser = await p.chromium.launch(headless=True)
            # Usamos un viewport ancho para acomodar 16 columnas
            context = await browser.new_context(viewport={'width': 2560, 'height': 1440})
            page = await context.new_page()
            
            await page.goto("https://fortnite.gg/shop", wait_until="networkidle")
            
            # Inyectamos CSS para forzar las 16 columnas y quitar elementos innecesarios
            # Aplanamos las secciones para que todos los items compartan la misma rejilla
            await page.add_style_tag(content="""
                #shop { 
                    display: grid !important; 
                    grid-template-columns: repeat(16, 1fr) !important; 
                    gap: 10px !important;
                    padding: 20px !important;
                }
                .shop-section, .shop-row { 
                    display: contents !important; 
                }
                .shop-section-title, header, footer, .ads, .shop-sidebar { 
                    display: none !important; 
                }
                body { background-color: #0f172a !important; }
                .item-card { width: 100% !important; }
            """)
            
            # Esperar un momento para que los estilos se apliquen y las imágenes carguen
            await asyncio.sleep(2)
            
            shop_element = page.locator("#shop")
            if await shop_element.count() > 0:
                await shop_element.screenshot(path=output_path)
                logger.info(f"✅ Imagen de la tienda generada en: {output_path}")
                await browser.close()
                return output_path
            else:
                logger.error("❌ No se encontró el elemento #shop en fortnite.gg")
                await browser.close()
                return None