"""
Generador de Device Auth para Epic Games — versión directa con aiohttp.
No depende del sistema de auth de fortnitepy (evita el error client_disabled).

Uso:
    py -3.11 generate_device_auth.py
"""
import asyncio
import base64
import json
import os
import sys

try:
    import aiohttp
except ImportError:
    print("[!] Ejecuta: py -3.11 -m pip install aiohttp")
    sys.exit(1)

# ─────────────────────────────────────────────────────────────
# Clientes de Epic Games (se prueban en orden)
# ─────────────────────────────────────────────────────────────
CLIENTS = [
    ("830865842828479e957579f189689531", "1799981881724683a48e788229e612f0"),  # Switch (Alt)
    ("5229dcd3ac3845208b496649092f251b", "e3bd2d3e-bf8c-4857-9e7d-f3d947d220c4"),  # Switch
    ("34a02cf8f4414e29b15921876da36f9a", "daafbccc737745039dffe53d94fc76cf"),  # PC
    ("3f69e56c7649492c8cc29f1af08a8a12", "b51ee9cb12234f50a69efa67ef53812e"),  # iOS
]

TOKEN_URL = "https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/token"

BOT_NAMES = [
    "Maidas-S",
    "Maidas-OS",
    "DENISSA_7u7",
    "Shegos么1",
    "Shegos么2",
]


def basic_auth(client_id: str, client_secret: str) -> str:
    raw = f"{client_id}:{client_secret}"
    return "Basic " + base64.b64encode(raw.encode()).decode()


async def exchange_code_for_token(session: aiohttp.ClientSession, code: str) -> dict | None:
    """Intenta obtener un access token probando cada cliente."""
    for client_id, client_secret in CLIENTS:
        headers = {
            "Authorization": basic_auth(client_id, client_secret),
            "Content-Type": "application/x-www-form-urlencoded",
        }
        data = {"grant_type": "authorization_code", "code": code}
        async with session.post(TOKEN_URL, headers=headers, data=data) as resp:
            result = await resp.json()
            if resp.status == 200:
                print(f"  ✅ Cliente funcionando: {client_id[:8]}...")
                return result
            else:
                error = result.get("errorCode", result.get("error", "desconocido"))
                print(f"  ⚠️  Cliente {client_id[:8]}... falló: {error}")
    return None


async def generate_device_auth_token(session, access_token, account_id):
    """Genera las credenciales de Device Auth."""
    url = f"https://account-public-service-prod03.ol.epicgames.com/account/api/public/account/{account_id}/deviceAuth"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    async with session.post(url, headers=headers, json={}) as resp:
        result = await resp.json()
        if resp.status == 200:
            return result
        print(f"  Error generando device auth: {result}")
        return None


async def process_account(session: aiohttp.ClientSession, name: str) -> dict | None:
    print(f"\n{'='*60}")
    print(f"  CONFIGURANDO CUENTA: {name}")
    print(f"{'='*60}")
    print("  1. Inicia sesion en Epic Games con esta cuenta en el navegador.")
    print("  2. Abre este link (Cópialo y pégalo en tu navegador):")
    print("     https://www.epicgames.com/id/api/redirect"
          "?clientId=5229dcd3ac3845208b496649092f251b&responseType=code")
    print("  3. Copia solo el valor de 'authorizationCode'.")

    code = input("\n[>] Pega el authorizationCode aqui: ").strip()
    if not code:
        print(f"  [!] Sin codigo — saltando '{name}'.")
        return None

    print("  [*] Obteniendo token...")
    token_data = await exchange_code_for_token(session, code)
    if not token_data:
        print(f"  [!] No se pudo obtener token para '{name}'.")
        return None

    display_name = token_data.get("displayName", "desconocido")
    access_token = token_data["access_token"]
    print(f"  ✅ Sesion iniciada como: {display_name}")

    print("  [*] Generando Device Auth...")
    device_data = await generate_device_auth_token(session, access_token, token_data["account_id"])
    if not device_data:
        print(f"  [!] No se pudo generar device auth para '{name}'.")
        return None

    print("  ✅ Device Auth generado correctamente.")
    return {
        "account_id": device_data["accountId"],
        "device_id":  device_data["deviceId"],
        "secret":     device_data["secret"],
    }


async def run_generator():
    output_file = "bots.json"
    all_auths: dict = {}

    if os.path.exists(output_file):
        try:
            with open(output_file, "r", encoding="utf-8") as f:
                all_auths = json.load(f)
            print(f"[*] {len(all_auths)} cuenta(s) ya en {output_file}.")
        except Exception:
            all_auths = {}

    print(f"\n{'*'*60}")
    print("   GENERADOR DE DEVICE AUTH — EPIC GAMES BOTS")
    print(f"{'*'*60}")

    async with aiohttp.ClientSession() as session:
        for name in BOT_NAMES:
            if name in all_auths:
                res = input(f"\n[?] '{name}' ya existe. Re-autenticar? (s/n): ").strip().lower()
                if res != "s":
                    print(f"    Saltando '{name}'.")
                    continue

            auth_data = await process_account(session, name)
            if auth_data:
                all_auths[name] = auth_data
                with open(output_file, "w", encoding="utf-8") as f:
                    json.dump(all_auths, f, indent=4)
                print(f"  [OK] '{name}' guardado en {output_file}.")

    print(f"\n{'='*60}")
    print("  PROCESO FINALIZADO")
    print(f"{'='*60}")
    print(f"Cuentas guardadas: {list(all_auths.keys())}")


if __name__ == "__main__":
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(run_generator())