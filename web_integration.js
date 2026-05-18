// ─────────────────────────────────────────────────────────────
//  Shegos Bots — Integración Web
//  Reemplaza BOT_API_URL con tu URL real de Railway.
// ─────────────────────────────────────────────────────────────

const BOT_API_URL = "https://shegos-bots-production.up.railway.app";

const BOTS_LIST = [
    "Denissa_7u7",
];

// ─────────────────────────────────────────────────────────────
//  Enviar solicitud de amistad
// ─────────────────────────────────────────────────────────────

async function solicitarAgregarme() {
    const input = document.getElementById("epic-username");
    const username = input ? input.value.trim() : "";

    if (!username) {
        alert("Escribe tu nombre de usuario de Epic Games.");
        return;
    }

    const btn = document.getElementById("btn-agregar");
    if (btn) btn.disabled = true;

    try {
        const response = await fetch(`${BOT_API_URL}/friend-request`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ epic_username: username }),
        });

        const data = await response.json();

        if (response.ok) {
            alert(
                `¡Solicitudes enviadas!\n` +
                `Bots que te agregaron: ${data.requests_sent} / ${BOTS_LIST.length}`
            );
        } else {
            alert(`Error del servidor: ${data.detail || "No se pudo procesar la solicitud."}`);
        }
    } catch (e) {
        console.error("Error al conectar con el servidor de bots:", e);
        alert("No se pudo conectar con el servidor. Verifica que esté activo.");
    } finally {
        if (btn) btn.disabled = false;
    }
}

// ─────────────────────────────────────────────────────────────
//  Mostrar estado de los bots en la página
// ─────────────────────────────────────────────────────────────

function renderBotStatus() {
    BOTS_LIST.forEach((botName) => {
        const elementId = `bot-tag-${botName.replace(/\s/g, "_")}`;
        const el = document.getElementById(elementId);
        if (!el) return;

        el.textContent = "ONLINE";
        el.className   = "status-online";
        el.style.color = "#00ff00";
    });
}

// ─────────────────────────────────────────────────────────────
//  Inicialización
// ─────────────────────────────────────────────────────────────

document.addEventListener("DOMContentLoaded", () => {
    // Cargar estado al iniciar
    renderBotStatus();

    // Refrescar cada 60 segundos
    setInterval(renderBotStatus, 60_000);

    // Botón de agregar
    const btn = document.getElementById("btn-agregar");
    if (btn) btn.addEventListener("click", solicitarAgregarme);
});
