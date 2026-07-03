import os
import asyncio
import logging
from playwright.async_api import async_playwright

logger = logging.getLogger(__name__)

class PlaywrightBot:
    def __init__(self, bot_name: str, email: str, password: str):
        """
        Inicializa el bot de Playwright para automatización web.
        """
        self.bot_name = bot_name
        self.email = email
        self.password = password
        self._ready = False
        self.session_path = f"sessions/{self.bot_name}.json"
        
        # Asegurar que la carpeta de sesiones existe para persistencia de cookies
        if not os.path.exists("sessions"):
            os.makedirs("sessions")

    async def login(self):
        """
        Inicia el navegador en modo headless y gestiona la autenticación.
        Si existe una sesión guardada, la carga para omitir el login manual.
        """
        try:
            logger.info(f"[{self.bot_name}] Iniciando Playwright (Chromium Headless)...")
            self.playwright = await async_playwright().start()
            self.browser = await self.playwright.chromium.launch(headless=True)
            
            if os.path.exists(self.session_path):
                logger.info(f"[{self.bot_name}] Cargando sesión existente desde {self.session_path}")
                self.context = await self.browser.new_context(storage_state=self.session_path)
            else:
                logger.info(f"[{self.bot_name}] No se encontró sesión previa. Realizando login manual...")
                self.context = await self.browser.new_context()
                page = await self.context.new_page()
                
                await page.goto("https://www.epicgames.com/id/login")
                
                # Completar credenciales en el formulario de Epic
                await page.fill('input[name="email"]', self.email)
                await page.fill('input[name="password"]', self.password)
                await page.click('button[type="submit"]')
                
                # Esperar a que la navegación confirme el éxito del login
                await page.wait_for_load_state("networkidle")
                
                # Guardar el estado de la sesión (cookies y local storage)
                await self.context.storage_state(path=self.session_path)
                logger.info(f"[{self.bot_name}] Sesión de login guardada correctamente.")
            
            self._ready = True
            logger.info(f"[{self.bot_name}] Bot Playwright listo para operar.")
            return True
            
        except Exception as e:
            logger.error(f"[{self.bot_name}] ❌ Error en el método login(): {e}")
            self._ready = False
            return False

    async def send_friend_request(self, username: str) -> bool:
        """
        Navega a la página de amigos y envía una solicitud al usuario indicado.
        """
        if not self._ready:
            logger.error(f"[{self.bot_name}] El bot no está listo. Debe llamar a login() primero.")
            return False
            
        try:
            logger.info(f"[{self.bot_name}] Intentando agregar a '{username}' mediante la web...")
            page = await self.context.new_page()
            await page.goto("https://www.epicgames.com/fortnite/es/friends")
            
            # Buscar el campo de entrada para agregar amigos
            # Nota: Los selectores se basan en atributos comunes, pueden variar si Epic cambia su web.
            search_input = page.locator('input[placeholder*="amigo"], input[placeholder*="friend"]')
            await search_input.wait_for(state="visible", timeout=15000)
            
            # Delay de 1.5s solicitado antes de la acción
            await asyncio.sleep(1.5)
            
            # Limpiar el campo por si acaso y asegurar el foco
            await search_input.click()
            await page.keyboard.press("Control+A")
            await page.keyboard.press("Backspace")
            await search_input.fill(username)
            await page.keyboard.press("Enter")
            
            # Espera breve para asegurar que la solicitud se procese en el DOM
            await asyncio.sleep(2)
            
            logger.info(f"[{self.bot_name}] ✅ Solicitud enviada a '{username}'.")
            await page.close()
            return True
            
        except Exception as e:
            logger.error(f"[{self.bot_name}] ❌ Error en send_friend_request(): {e}")
            return False

    async def accept_pending_requests(self):
        """
        Navega a la página de amigos y acepta todas las solicitudes pendientes.
        """
        if not self._ready:
            logger.error(f"[{self.bot_name}] El bot no está listo.")
            return
            
        try:
            logger.info(f"[{self.bot_name}] Buscando solicitudes pendientes para aceptar...")
            page = await self.context.new_page()
            await page.goto("https://www.epicgames.com/fortnite/es/friends")
            
            # Identificar botones de aceptar por su texto
            accept_buttons = page.locator('button:has-text("Aceptar"), button:has-text("Accept")')
            count = await accept_buttons.count()
            
            if count > 0:
                for i in range(count):
                    # Hacemos clic en el primero disponible sucesivamente
                    await accept_buttons.nth(0).click()
                    await asyncio.sleep(0.5)
                logger.info(f"[{self.bot_name}] ✅ Se aceptaron {count} solicitudes pendientes.")
            else:
                logger.info(f"[{self.bot_name}] No se encontraron solicitudes pendientes.")
                
            await page.close()
        except Exception as e:
            logger.error(f"[{self.bot_name}] ❌ Error en accept_pending_requests(): {e}")

    def is_ready(self) -> bool:
        """Retorna True si el bot está autenticado y listo."""
        return self._ready