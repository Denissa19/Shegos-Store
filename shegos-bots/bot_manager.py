import os
import json
import asyncio
import logging
import aiohttp
from datetime import datetime
from epic_api_bot import EpicApiBot

logger = logging.getLogger(__name__)


class BotManager:
    def __init__(self):
        self.bots: list[EpicApiBot] = []
        self.credentials: dict = self._load_credentials()
        self.request_timestamps: dict = {}  # Guarda timestamps de aceptación

    def _load_credentials(self) -> dict:
        bots_json_env = os.getenv("BOTS_JSON")
        if bots_json_env:
            try:
                logger.info("Credenciales cargadas desde BOTS_JSON.")
                return json.loads(bots_json_env)
            except json.JSONDecodeError as e:
                logger.error(f"❌ Error al decodificar BOTS_JSON: {e}")
                return {}

        if os.path.exists("bots.json"):
            with open("bots.json", "r", encoding="utf-8") as f:
                logger.info("Credenciales cargadas desde bots.json.")
                return json.load(f)

        logger.error("❌ No se encontraron credenciales.")
        return {}

    async def _start_single_bot(self, name: str, auth_data: dict):
        bot = EpicApiBot(bot_name=name, device_auth=auth_data)
        self.bots = [b for b in self.bots if b.bot_name != name]
        self.bots.append(bot)
        try:
            await bot.start()
        except Exception as e:
            logger.error(f"[{name}] ❌ Error iniciando bot: {e}")

    async def start_bots(self):
        if not self.credentials:
            logger.error("Sin credenciales — no se inicia ningún bot.")
            return
        logger.info(f"🚀 Iniciando {len(self.credentials)} bots...")
        tasks = [
            self._start_single_bot(name, auth_data)
            for name, auth_data in self.credentials.items()
        ]
        await asyncio.gather(*tasks, return_exceptions=True)

    async def watch_and_accept(self):
        """Acepta solicitudes pendientes cada 5 minutos."""
        while True:
            try:
                await asyncio.sleep(300)
                for bot in self.bots:
                    if bot.is_ready():
                        try:
                            await bot.accept_pending_requests()
                        except Exception as e:
                            logger.error(f"[{bot.bot_name}] Error aceptando solicitudes: {e}")
            except Exception as e:
                logger.error(f"watch_and_accept: error inesperado: {e}")
                await asyncio.sleep(30)  # Espera breve y reintenta

    async def watch_bots(self):
        """Reinicia bots caídos cada 60 segundos."""
        while True:
            try:
                await asyncio.sleep(60)
                for bot in list(self.bots):
                    if not bot.is_ready() and bot.bot_name in self.credentials:
                        logger.warning(f"[{bot.bot_name}] ⚠️ OFFLINE — reiniciando...")
                        asyncio.create_task(
                            self._start_single_bot(bot.bot_name, self.credentials[bot.bot_name])
                        )
            except Exception as e:
                logger.error(f"watch_bots: error inesperado: {e}")
                await asyncio.sleep(30)

    async def send_friend_requests_to(self, username: str, account_id: str = None, platform: str = "epic") -> dict:
        ready_bots = [bot for bot in self.bots if bot.is_ready()]
        if not ready_bots:
            logger.warning("No hay bots listos.")
            return {"requests_sent": 0, "already_added": 0, "failed": 0, "message": "No hay bots disponibles."}
            
        tasks = [bot.send_friend_request_safe(username, account_id=account_id, platform=platform) for bot in ready_bots]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        stats = {"requests_sent": 0, "already_added": 0, "failed": 0, "created_at": None}
        for r in results:
            if isinstance(r, dict):
                status = r.get("status")
                if status == "sent": stats["requests_sent"] += 1
                elif status == "already": 
                    stats["already_added"] += 1
                    if not stats["created_at"]: stats["created_at"] = r.get("created_at")
            else: stats["failed"] += 1
            
        # Generar mensaje unificado para la respuesta
        if stats["requests_sent"] > 0:
            stats["message"] = f"Solicitud procesada: {stats['requests_sent']} enviada(s), {stats['already_added']} ya existentes."
        elif stats["already_added"] > 0:
            stats["message"] = "Ya eres amigo en todos nuestros bots."
        else:
            stats["message"] = "No se pudo encontrar al usuario o enviar la solicitud."

        logger.info(f"Resultado para '{username}': {stats}")
        
        # Guardar timestamp si la solicitud fue aceptada
        if stats["already_added"] > 0:
            self.request_timestamps[username] = datetime.utcnow().isoformat()
        
        # Enviar alerta Webhook si está configurado
        asyncio.create_task(self.send_webhook_alert(username, stats))
        
        return stats

    async def send_webhook_alert(self, username: str, stats: dict):
        """Envía una notificación a Discord sobre la actividad de los bots."""
        webhook_url = os.getenv("DISCORD_WEBHOOK_URL")
        if not webhook_url:
            logger.warning("⚠️ DISCORD_WEBHOOK_URL no configurado. Saltando alerta.")
            return

        payload = {
            "username": "Shegos Bots Alerta",
            "embeds": [{
                "title": "🔔 Nueva Solicitud Procesada",
                "color": 3066993 if stats["sent"] > 0 else 15105570,
                "fields": [
                    {"name": "Usuario", "value": f"`{username}`", "inline": True},
                    {"name": "Estado", "value": "✅ Enviada" if stats["sent"] > 0 else "⚠️ Ya era amigo", "inline": True},
                    {"name": "Detalles", "value": f"🚀 Enviadas: {stats['sent']}\n🤝 Ya agregados: {stats['already']}\n❌ Fallidos: {stats['failed']}"}
                ],
                "footer": {"text": "Shegos Bots System"}
            }]
        }

        max_retries = 3
        timeout = aiohttp.ClientTimeout(total=10)
        async with aiohttp.ClientSession() as session:
            for attempt in range(max_retries):
                try:
                    logger.info(f"📤 Enviando webhook a Discord (Intento {attempt + 1}/{max_retries}) para {username}...")
                    async with session.post(webhook_url, json=payload, timeout=timeout) as resp:
                        response_text = await resp.text()
                        if resp.status in (200, 204):
                            logger.info(f"✅ Webhook enviado con éxito a Discord para {username}")
                            return
                        else:
                            logger.error(f"❌ Discord rechazó el webhook. Status: {resp.status}, Body: {response_text}")
                except asyncio.TimeoutError:
                    logger.error(f"⏱️ Timeout enviando webhook para {username} (Intento {attempt + 1})")
                except Exception as e:
                    logger.error(f"❌ Error de conexión al enviar webhook (Intento {attempt + 1}): {e}")

                if attempt < max_retries - 1:
                    await asyncio.sleep((attempt + 1) * 2)

    def get_status(self) -> dict:
        online  = [b.bot_name for b in self.bots if b.is_ready()]
        offline = [b.bot_name for b in self.bots if not b.is_ready()]
        return {
            "total_bots":    len(self.bots),
            "online_count":  len(online),
            "offline_count": len(offline),
            "online_bots":   online,
            "offline_bots":  offline,
        }
