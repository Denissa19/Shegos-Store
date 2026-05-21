const BOT_API_URL = "https://shegos-bots-2.onrender.com";

const BOTS_LIST = [
    "Maidas-S",
    "Maidas-OS",
    "Shegos么1",
    "Denissa_7u7",
    "SHAGOS STW",
    "SHEGOS STW",
];

// ─── Contador 48h ───────────────────────────────────────────
function initCountdown(endTime, requestsSent) {
    const msg = document.getElementById("bot-status-msg");
    if (!msg) return;

    if (window.countdownIntervalId) clearInterval(window.countdownIntervalId);

    const updateTimer = () => {
        const diff = endTime - Date.now();
        const sentMsg = requestsSent
            ? `<div style="color:#aaa;font-size:0.85em;margin-top:5px;">Solicitud enviada desde ${requestsSent} cuenta(s)</div>`
            : "";

        if (diff <= 0) {
            msg.innerHTML = `<span style="color:#28feb6;">✅ ¡Ya te tenemos agregado!</span>
                <div style="color:#ffd700;font-weight:bold;margin-top:5px;">¡Ya puedes recibir regalos! 🎁</div>${sentMsg}`;
            clearInterval(window.countdownIntervalId);
            localStorage.removeItem('friendRequestEndTime');
            localStorage.removeItem('friendRequestSentCount');
        } else {
            const h = Math.floor(diff / 3600000);
            const m = Math.floor((diff % 3600000) / 60000);
            const s = Math.floor((diff % 60000) / 1000);
            msg.innerHTML = `<span style="color:#28feb6;">✅ ¡Ya te tenemos agregado!</span>
                <div style="color:#ffd700;font-weight:bold;margin-top:5px;">Faltan: ${h}h ${m}m ${s}s</div>${sentMsg}`;
        }
    };

    updateTimer();
    window.countdownIntervalId = setInterval(updateTimer, 1000);
}

// ─── Enviar solicitud ────────────────────────────────────────
async function enviarSolicitudBot() {
    const input = document.getElementById("epic-username");
    const msg   = document.getElementById("bot-status-msg");
    const username  = input ? input.value.trim() : "";
    const plataforma = (typeof plataformaSeleccionada !== 'undefined') ? plataformaSeleccionada : 'epic';

    if (!username) {
        if (msg) msg.innerHTML = '<span style="color:#ff4d4d;">⚠️ Escribe tu nombre de usuario.</span>';
        return;
    }

    const btn = document.getElementById("btn-agregar");
    if (btn) { btn.disabled = true; btn.innerText = "VERIFICANDO..."; }
    if (msg) msg.innerHTML = '<span style="color:#888;">Conectando con el servidor...</span>';

    try {
        const response = await fetch(`${BOT_API_URL}/friend-request`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ epic_username: username, platform: plataforma }),
        });

        const data = await response.json();

        if (response.status === 404) {
            if (msg) msg.innerHTML = '<span style="color:#ff4d4d;">❌ ID no encontrado. Asegúrate de escribirlo correctamente.</span>';

        } else if (response.status === 503) {
            if (msg) msg.innerHTML = '<span style="color:#ff4d4d;">❌ Bots fuera de línea. Agrega las cuentas manualmente.</span>';

        } else if (response.ok) {
            const endTime   = Date.now() + (48 * 60 * 60 * 1000);
            const sentCount = data.requests_sent || 0;
            localStorage.setItem('friendRequestEndTime',   endTime);
            localStorage.setItem('friendRequestSentCount', sentCount);
            initCountdown(endTime, sentCount);
            if (input) input.value = "";

        } else {
            if (msg) msg.innerHTML = `<span style="color:#ff4d4d;">❌ ${data.detail || "Error desconocido. Agrega las cuentas manualmente."}</span>`;
        }

    } catch (e) {
        console.error("Error al conectar:", e);
        if (msg) msg.innerHTML = '<span style="color:#ff4d4d;">❌ Error de conexión. Intenta de nuevo.</span>';
    } finally {
        if (btn) { btn.disabled = false; btn.innerText = "+ SOLICITAR AGREGARME"; }
    }
}

// ─── Estado de bots ──────────────────────────────────────────
function renderBotStatus() {
    BOTS_LIST.forEach((botName) => {
        const el = document.getElementById(`bot-tag-${botName.replace(/\s/g, "_")}`);
        if (!el) return;
        el.textContent = "ONLINE";
        el.className   = "status-online";
        el.style.color = "#00ff00";
    });
}

// ─── Inicialización ──────────────────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
    renderBotStatus();
    setInterval(renderBotStatus, 60_000);

    // Recuperar contador si quedó pendiente
    const storedEndTime = localStorage.getItem('friendRequestEndTime');
    const storedCount   = localStorage.getItem('friendRequestSentCount');
    if (storedEndTime) {
        initCountdown(parseInt(storedEndTime), storedCount);
    }

    const btn = document.getElementById("btn-agregar");
    if (btn) btn.addEventListener("click", enviarSolicitudBot);
});
