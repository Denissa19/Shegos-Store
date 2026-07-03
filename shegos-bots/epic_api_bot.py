import asyncio
import urllib.parse
import os
import logging
import base64
import time
import aiohttp

logger = logging.getLogger(__name__)

TOKEN_URL   = "https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/token"
FRIENDS_URL = "https://friends-public-service-prod06.ol.epicgames.com/friends/api/v1"
ACCOUNT_URL = "https://account-public-service-prod03.ol.epicgames.com/account/api/public/account"

DISCORD_WEBHOOK = os.getenv("DISCORD_WEBHOOK_URL", "")

CLIENTS_B64 = [
    "Basic ODMwODY1ODQyODI4NDc5ZTk1NzU3OWYxODk2ODk1MzE6MTc5OTk4MTg4MTcyNDY4M2E0OGU3ODgyMjllNjEyZjA=",
    "Basic MzRhMDJjZjhmNDQxNGUyOWIxNTkyMTg3NmRhMzZmOWE6ZGFhZmJjY2M3Mzc3NDUwMzlkZmZlNTNkOTRmYzc2Y2Y=",
    "Basic M2Y2OWU1NmM3NjQ5NDkyYzhjYzI5ZjFhZjA4YThhMTI6YjUxZWU5Y2IxMjIzNGY1MGE2OWVmYTY3ZWY1MzgxMmU=",
]


class EpicApiBot:
    def __init__(self, bot_name: str, device_auth: dict):
        self.bot_name      = bot_name
        self.device_auth   = device_auth
        self._ready        = False
        self._access_token = None
        self._account_id   = None
        self._token_expires = 0
        self._session      = None

    async def start(self):
        self._session = aiohttp.ClientSession()
        if await self._authenticate():
            self._ready = True
            logger.info(f"[{self.bot_name}] ✅ Listo.")
            await self.accept_pending_requests()
            asyncio.create_task(self._reauth_loop())
        else:
            logger.error(f"[{self.bot_name}] ❌ No se pudo autenticar.")

    async def _authenticate(self) -> bool:
        data = {
            "grant_type": "device_auth",
            "account_id": self.device_auth["account_id"],
            "device_id":  self.device_auth["device_id"],
            "secret":     self.device_auth["secret"],
        }
        for client_token in CLIENTS_B64:
            headers = {
                "Authorization": client_token,
                "Content-Type": "application/x-www-form-urlencoded",
            }
            try:
                async with self._session.post(TOKEN_URL, headers=headers, data=data) as resp:
                    result = await resp.json()
                    if resp.status == 200:
                        self._access_token  = result["access_token"]
                        self._account_id    = result["account_id"]
                        self._token_expires = time.time() + result.get("expires_in", 28800)
                        logger.info(f"[{self.bot_name}] 🔑 Token obtenido.")
                        return True
                    else:
                        err = result.get("errorCode", "desconocido")
                        logger.warning(f"[{self.bot_name}] Cliente falló: {err}")
            except Exception as e:
                logger.error(f"[{self.bot_name}] Error autenticando: {e}")
        return False

    async def _reauth_loop(self):
        while True:
            await asyncio.sleep(6 * 3600)
            logger.info(f"[{self.bot_name}] 🔄 Renovando token...")
            if not await self._authenticate():
                self._ready = False

    async def _ensure_token_valid(self) -> bool:
        if time.time() >= self._token_expires - 300:
            logger.warning(f"[{self.bot_name}] Token próximo a expirar, renovando...")
            success = await self._authenticate()
            if not success:
                self._ready = False
            return success
        return True

    def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self._access_token}"}

    async def _notify_discord(self, username: str, status: str = "enviada"):
        if not DISCORD_WEBHOOK:
            return
        color_map = {
            "enviada":   3066993,
            "duplicada": 15105570,
            "fallida":   16711680,
        }
        payload = {
            "embeds": [{
                "title": f"Solicitud {status}",
                "description": f"Bot **{self.bot_name}** - Usuario: **{username}**",
                "color": color_map.get(status, 9807270)
            }]
        }
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(DISCORD_WEBHOOK, json=payload, timeout=aiohttp.ClientTimeout(total=5)) as resp:
                    if resp.status not in (200, 204):
                        logger.error(f"[{self.bot_name}] Error enviando a Discord: {resp.status}")
        except Exception as e:
            logger.error(f"[{self.bot_name}] Excepción Discord: {e}")

    async def get_account_by_username(self, username: str, platform: str = "epic") -> str | None:
        """
        Busca la cuenta usando el nombre EXACTO sin ninguna normalización.
        Soporta caracteres especiales, emojis, símbolos, letras estilizadas, chino, etc.
        """
        original_username = username.strip()

        # Si parece un account_id (UUID de 32 hex), úsalo directo
        clean = original_username.replace("-", "")
        if len(clean) == 32 and all(c in "0123456789abcdefABCDEF" for c in clean):
            logger.info(f"[{self.bot_name}] 🔍 UUID detectado: {original_username}")
            return clean

        # Buscar con el nombre exacto — sin modificar ni normalizar
        endpoints = [
            ("Epic", f"{ACCOUNT_URL}/displayName/{urllib.parse.quote(original_username, safe='')}"),
            ("PSN",  f"{ACCOUNT_URL}?externalAuthType=psn&externalAuthId={urllib.parse.quote(original_username, safe='')}"),
            ("Xbox", f"{ACCOUNT_URL}?externalAuthType=xbl&externalAuthId={urllib.parse.quote(original_username, safe='')}"),
        ]

        for platform_name, url in endpoints:
            try:
                logger.debug(f"[{self.bot_name}] 🔍 Buscando en {platform_name}: {repr(original_username)}")
                async with self._session.get(url, headers=self._headers(), timeout=aiohttp.ClientTimeout(total=10)) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        if isinstance(data, list):
                            account_id = data[0].get("id") if data else None
                        else:
                            account_id = data.get("id") or data.get("accountId")
                        if account_id:
                            logger.info(f"[{self.bot_name}] ✅ ENCONTRADO en {platform_name}: {repr(original_username)} → {account_id}")
                            return account_id
                    elif resp.status == 404:
                        logger.debug(f"[{self.bot_name}] No encontrado en {platform_name}")
                    elif resp.status == 401:
                        logger.warning(f"[{self.bot_name}] Token inválido, reautenticando...")
                        await self._authenticate()
                    else:
                        logger.debug(f"[{self.bot_name}] Status {resp.status} en {platform_name}")
            except asyncio.TimeoutError:
                logger.warning(f"[{self.bot_name}] ⏱️ Timeout en {platform_name}")
            except Exception as e:
                logger.debug(f"[{self.bot_name}] Error en {platform_name}: {type(e).__name__}: {e}")

        logger.error(f"[{self.bot_name}] ❌ NO ENCONTRADO: {repr(original_username)}")
        return None

    async def get_friendship_at(self, target_id: str) -> str | None:
        if not self._session or not self._account_id:
            return None
        url = f"{FRIENDS_URL}/{self._account_id}/friends/{target_id}"
        try:
            async with self._session.get(url, headers=self._headers()) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    return data.get("created")
        except Exception:
            pass
        return None

    async def send_friend_request_safe(self, username: str, account_id: str = None, platform: str = "epic") -> dict:
        if not self._ready:
            logger.error(f"[{self.bot_name}] ❌ Bot no está listo")
            return {"status": "failed"}
        if not await self._ensure_token_valid():
            logger.error(f"[{self.bot_name}] ❌ Token inválido")
            return {"status": "failed"}
        try:
            await asyncio.sleep(1.5)

            target_id = account_id or await self.get_account_by_username(username, platform)
            if not target_id:
                logger.error(f"[{self.bot_name}] ❌ No se pudo obtener ID para: {repr(username)}")
                await self._notify_discord(username, "fallida")
                return {"status": "failed"}

            logger.info(f"[{self.bot_name}] 📤 Enviando solicitud a {repr(username)} ({target_id})...")
            url = f"{FRIENDS_URL}/{self._account_id}/friends/{target_id}"
            async with self._session.post(url, headers=self._headers(), timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status in (200, 204):
                    logger.info(f"[{self.bot_name}] ✅ SOLICITUD ENVIADA a {repr(username)}")
                    await self._notify_discord(username, "enviada")
                    return {"status": "sent"}

                result = await resp.json()
                err = result.get("errorCode", "")

                if "duplicate" in err.lower() or "already" in err.lower():
                    logger.warning(f"[{self.bot_name}] ℹ️ {repr(username)} ya era amigo")
                    created_at = await self.get_friendship_at(target_id)
                    await self._notify_discord(username, "duplicada")
                    return {"status": "already", "created_at": created_at}

                logger.error(f"[{self.bot_name}] ❌ Error: Status {resp.status}, Detalle: {err}")
                await self._notify_discord(username, "fallida")
                return {"status": "failed"}

        except Exception as e:
            logger.error(f"[{self.bot_name}] ❌ Excepción: {e}")
            return {"status": "failed"}

    async def accept_pending_requests(self):
        if not self._account_id or not self._session:
            return
        try:
            url = f"{FRIENDS_URL}/{self._account_id}/incoming"
            async with self._session.get(url, headers=self._headers()) as resp:
                if resp.status != 200:
                    return
                pending = await resp.json()
            for req in pending:
                requester_id = req.get("accountId")
                if requester_id:
                    accept_url = f"{FRIENDS_URL}/{self._account_id}/friends/{requester_id}"
                    async with self._session.post(accept_url, headers=self._headers()) as r:
                        if r.status in (200, 204):
                            logger.info(f"[{self.bot_name}] ✅ Aceptada solicitud de: {requester_id}")
        except Exception as e:
            logger.error(f"[{self.bot_name}] Error aceptando: {e}")

    def is_ready(self) -> bool:
        return self._ready