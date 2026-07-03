import os
import logging
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes
from api import manager

logger = logging.getLogger(__name__)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "🤖 **Shegos Bots Control**\n"
        "Usa `/agregar <usuario>` para enviar solicitudes desde todos los bots."
    )

async def agregar(update: Update, context: ContextTypes.DEFAULT_TYPE):
    # Solo permitir a ciertos usuarios (opcional, configurar chat_id)
    username = " ".join(context.args)
    
    if not username:
        await update.message.reply_text("❌ Por favor, indica el nombre de usuario.\nEjemplo: `/agregar Ψ ᴀɴᴅʀᴜx Ψ`")
        return

    await update.message.reply_text(f"⏳ Procesando solicitud para: `{username}`...", parse_mode="Markdown")
    
    try:
        stats = await manager.send_friend_requests_to(username)
        sent = stats.get("requests_sent", 0)
        already = stats.get("already_added", 0)

        if sent > 0:
            await update.message.reply_text(
                f"✅ *¡Éxito!*\nSolicitud enviada desde *{sent}* bot(s) a `{username}`.",
                parse_mode="Markdown"
            )
        elif already > 0:
            await update.message.reply_text(
                f"ℹ️ `{username}` ya está agregado en *{already}* bot(s).",
                parse_mode="Markdown"
            )
        else:
            await update.message.reply_text(
                f"❌ No se pudo encontrar al usuario `{username}` en ninguna plataforma.",
                parse_mode="Markdown"
            )
    except Exception as e:
        logger.error(f"Error en bot de Telegram: {e}")
        await update.message.reply_text("❌ Error interno al procesar la solicitud.")

async def run_telegram_bot():
    token = os.getenv("TELEGRAM_TOKEN")
    if not token:
        logger.error("❌ TELEGRAM_TOKEN no configurado. Bot de Telegram desactivado.")
        return

    application = ApplicationBuilder().token(token).build()
    
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("agregar", agregar))
    
    logger.info("🚀 Bot de Telegram iniciado.")
    await application.initialize()
    await application.start()
    await application.updater.start_polling()