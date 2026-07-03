# Agrega esto a tu backend FastAPI (shegos-bots-2 en Render)
# Requiere: pip install httpx beautifulsoup4  (agrégalos a requirements.txt)

import time
import httpx
from bs4 import BeautifulSoup
from fastapi import FastAPI

app = FastAPI()  # usa tu instancia "app" existente, no crees una nueva

EPIC_CREW_URL = "https://store.epicgames.com/p/fortnite--crew"

# Cache simple en memoria para no golpear a Epic en cada visita del sitio
_cache = {"image": None, "ts": 0}
CACHE_SECONDS = 3600  # 1 hora


@app.get("/api/fortnite-crew-cover")
async def fortnite_crew_cover():
    now = time.time()

    # Si el cache sigue vigente, lo devolvemos directo
    if _cache["image"] and (now - _cache["ts"] < CACHE_SECONDS):
        return {"image": _cache["image"]}

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                EPIC_CREW_URL,
                headers={"User-Agent": "Mozilla/5.0 (compatible; ShegosStoreBot/1.0)"}
            )
            resp.raise_for_status()

        soup = BeautifulSoup(resp.text, "html.parser")
        og_image = soup.find("meta", property="og:image")

        if og_image and og_image.get("content"):
            imagen = og_image["content"]
            _cache["image"] = imagen
            _cache["ts"] = now
            return {"image": imagen}

    except Exception:
        pass

    # Si algo falla, devolvemos lo último guardado en cache (si existe)
    if _cache["image"]:
        return {"image": _cache["image"]}

    # Si nunca se pudo obtener nada, devolvemos null y el frontend usa su imagen estática
    return {"image": None}
