import asyncio
import logging
import fortnitepy

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class EpicBot(fortnitepy.Client):
    def __init__(self, bot_name: str, device_auth: dict):
        self.bot_name = bot_name
        self._ready = False

        auth = fortnitepy.DeviceAuth(
            account_id=device_auth["account_id"],
            device_id=device_auth["device_id"],
            secret=device_auth["secret"],
            ios_token="MzQ0NmNkNzI2OTRjNGE0NDg1ZDgxYjc3YWRiYjIxNDE6OTIwOWQ0YTVlMjVhNDU3ZmI5YjA3NDg5ZDMxM2I0MWE=",
            fortnite_token="ZWM2ODRiOGM2ODdmNDc5ZmFkZWEzY2IyYWQ4M2Y1YzY6ZTFmMzFjMjExZjI4NDEzMTg2MjYyZDM3YTEzZmM4NGQ="
        )
        super().__init__(auth=auth)

    async def event_ready(self):
        self._ready = True
        logger.info(f"[{self.bot_name}] ✅ Conectado como: {self.user.display_name}")
        for request in list(self.incoming_pending_friends):
            try:
                await request.accept()
            except Exception as e:
                logger.error(f"[{self.bot_name}] Error aceptando solicitud: {e}")

    async def event_logout(self):
        self._ready = False
        logger.warning(f"[{self.bot_name}] ⚠️ Desconectado.")

    async def event_friend_request(self, request):
        try:
            await request.accept()
            logger.info(f"[{self.bot_name}] ✅ Solicitud aceptada de: {request.display_name}")
        except Exception as e:
            logger.error(f"[{self.bot_name}] Error al aceptar solicitud: {e}")

    def is_ready(self) -> bool:
        return self._ready

    async def send_friend_request_safe(self, username: str) -> bool:
        if not self._ready:
            return False
        try:
            await asyncio.sleep(1.5)
            user = await self.fetch_user(username)
            if user is None:
                return False
            await self.add_friend(user.id)
            logger.info(f"[{self.bot_name}] 📨 Solicitud enviada a {username}")
            return True
        except fortnitepy.errors.DuplicateFriendship:
            return True
        except fortnitepy.errors.FriendshipRequestAlreadySent:
            return True
        except Exception as e:
            logger.error(f"[{self.bot_name}] ❌ Error: {e}")
            return False
