import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const monthMap: Record<string, number> = {
  янв: 0, января: 0, фев: 1, февраля: 1, мар: 2, марта: 2,
  апр: 3, апреля: 3, май: 4, мая: 4, июн: 5, июня: 5,
  июл: 6, июля: 6, авг: 7, августа: 7, сен: 8, сентября: 8,
  окт: 9, октября: 9, ноя: 10, ноября: 10, дек: 11, декабря: 11,
};

function respond(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

function decodeHtml(value: string) {
  return value
    .replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([\da-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)));
}

function cleanText(html: string) {
  return decodeHtml(html.replace(/<script\b[\s\S]*?<\/script>/gi, " ").replace(/<style\b[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ").trim();
}

function attr(tag: string, name: string) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return tag.match(new RegExp(`\\b${escaped}\\s*=\\s*(["'])(.*?)\\1`, "i"))?.[2] || "";
}

function validSourcePage(value: string) {
  try {
    const u = new URL(value);
    return u.protocol === "https:" && u.hostname === "lzt.market" && /^\/epicgames\/?$/.test(u.pathname);
  } catch { return false; }
}

function parseCards(html: string, pageUrl: string) {
  const starts = [...html.matchAll(/<div\b[^>]*class=["'][^"']*\bmarketItemCard\b[^"']*["'][^>]*>/gi)].map(m => m.index ?? -1).filter(x => x >= 0);
  const cards = [] as Array<{ id: string; url: string; title: string; price: number; skins: number; text: string }>;
  for (let i = 0; i < starts.length; i++) {
    const block = html.slice(starts[i], starts[i + 1] ?? html.length);
    const linkMatch = block.match(/<a\b[^>]*href=["']([^"']+)["'][^>]*>[\s\S]*?class=["'][^"']*\bitemTitle\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
    if (!linkMatch) continue;
    let url: URL;
    try { url = new URL(decodeHtml(linkMatch[1]), pageUrl); } catch { continue; }
    if (url.hostname !== "lzt.market") continue;
    const id = url.pathname.match(/^\/(\d+)\/?$/)?.[1];
    if (!id) continue;
    const price = Number(block.match(/class=["'][^"']*\bValue\b[^"']*["'][^>]*data-value=["']([\d.]+)["']/i)?.[1]);
    if (!Number.isFinite(price) || price <= 0) continue;
    const text = cleanText(block);
    const skins = Number(text.match(/(?:\||\b)(\d{1,5})\s*(?:skins?|скинов|скина|скин)\b/i)?.[1]) || 0;
    cards.push({ id, url: `https://lzt.market/${id}/`, title: cleanText(linkMatch[2]).slice(0, 100) || `Cuenta Fortnite · ${skins} skins`, price, skins, text });
  }
  const unique = [...new Map(cards.map(card => [card.id, card])).values()];
  return { cards: unique, nextUrl: [...html.matchAll(/href=["']([^"']*\bafter=[^"']+)["']/gi)].map(m => { try { return new URL(decodeHtml(m[1]), pageUrl).href; } catch { return ""; } }).find(Boolean) || "" };
}

function parseFeaturedSkins(detailHtml: string) {
  const found: Array<{ name: string; url: string }> = [];
  const images = detailHtml.matchAll(/<img\b[^>]*>/gi);
  for (const match of images) {
    const tag = match[0];
    const src = decodeHtml(attr(tag, "src") || attr(tag, "data-src"));
    if (!src) continue;
    let u: URL;
    try { u = new URL(src); } catch { continue; }
    if (u.hostname !== "fortnite-api.com" || !u.pathname.includes("/images/cosmetics/br/")) continue;
    const name = cleanText(attr(tag, "alt")) || "Skin destacada";
    if (!found.some(item => item.url === u.href)) found.push({ name: name.slice(0, 70), url: u.href });
    if (found.length >= 6) break;
  }
  return found;
}

function getIdleDays(text: string) {
  const match = text.match(/Последний актив\s+(\d{1,2})\s+([\p{L}.]+)\s+(\d{4})/iu);
  if (!match) return 30;
  const monthKey = match[2].toLocaleLowerCase("ru").replace(/\.$/, "");
  const month = monthMap[monthKey] ?? monthMap[monthKey.slice(0, 3)];
  if (month === undefined) return 30;
  const lastActive = new Date(Number(match[3]), month, Number(match[1]));
  if (Number.isNaN(lastActive.getTime())) return 30;
  return Math.max(0, Math.floor((Date.now() - lastActive.getTime()) / 86400000));
}

function extensionFor(contentType: string | null, sourceUrl: string) {
  const type = (contentType || "").split(";")[0].toLowerCase();
  if (type === "image/webp") return "webp";
  if (type === "image/jpeg") return "jpg";
  if (type === "image/png") return "png";
  const ext = new URL(sourceUrl).pathname.split(".").pop()?.toLowerCase();
  return ["webp", "jpg", "jpeg", "png"].includes(ext || "") ? (ext === "jpeg" ? "jpg" : ext!) : "png";
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respond({ error: "Método no permitido." }, 405);

  try {
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!token) return respond({ error: "Inicia sesión para actualizar el catálogo." }, 401);
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return respond({ error: "Falta la configuración segura del catálogo." }, 500);
    const supabase = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) return respond({ error: "La sesión ya no es válida." }, 401);
    const { data: staff, error: staffError } = await supabase.from("usuarios_roles").select("rol,activo").eq("id", authData.user.id).maybeSingle();
    if (staffError || !staff?.activo || staff.rol !== "CEO") return respond({ error: "Solo el CEO puede actualizar el catálogo." }, 403);

    const body = await req.json().catch(() => ({}));
    const batchSize = Math.max(1, Math.min(12, Number(body.batch_size) || 8));
    const { data: configRows, error: configError } = await supabase.rpc("catalogo_lzt_import_state");
    if (configError) throw new Error("No se pudo leer la configuración privada del catálogo.");
    const config = Array.isArray(configRows) ? configRows[0] : configRows;
    if (!config?.search_url || !validSourcePage(config.search_url)) throw new Error("La configuración del catálogo requiere una URL pública de búsqueda válida.");
    if (body.reset === true) {
      const { error } = await supabase.rpc("catalogo_lzt_set_next_url", { p_next_url: "" });
      if (error) throw new Error("No se pudo reiniciar el recorrido de resultados.");
      return respond({ reset: true, message: "Recorrido reiniciado. La próxima importación empezará desde el primer resultado." });
    }
    if (config.next_url === "DONE") return respond({ imported: 0, images: 0, has_more: false, message: "Ya se recorrieron todos los resultados de esta búsqueda." });
    const cursorUrl = new URL(config.next_url || config.search_url);
    const offset = Math.max(0, Number(cursorUrl.searchParams.get("__catalog_offset")) || 0);
    cursorUrl.searchParams.delete("__catalog_offset");
    const pageUrl = cursorUrl.href;
    if (!validSourcePage(new URL(pageUrl).origin + new URL(pageUrl).pathname)) throw new Error("La siguiente página de resultados no es válida.");

    const sourcePage = await fetch(pageUrl, { headers: { "User-Agent": "Mozilla/5.0 (compatible; StoreCatalog/1.0)", "Accept": "text/html,application/xhtml+xml" } });
    const sourceHtml = await sourcePage.text();
    if (!sourcePage.ok || /enable javascript and cookies|captcha|security check/i.test(sourceHtml)) {
      return respond({ error: "El sitio no entregó la búsqueda a la importación automática. No se intentó eludir sus protecciones." }, 502);
    }
    const parsed = parseCards(sourceHtml, pageUrl);
    if (!parsed.cards.length) return respond({ error: "No se detectaron cuentas en esta página de resultados." }, 422);
    const batch = parsed.cards.slice(offset, offset + batchSize);
    if (!batch.length) return respond({ error: "No quedan cuentas en esta página. Reinicia el recorrido para comenzar de nuevo." }, 422);
    const results: Array<{ title: string; images: number }> = [];
    let totalImages = 0;

    for (const card of batch) {
      let detailHtml = "";
      try {
        const detailResponse = await fetch(card.url, { headers: { "User-Agent": "Mozilla/5.0 (compatible; StoreCatalog/1.0)", "Accept": "text/html,application/xhtml+xml" } });
        if (detailResponse.ok) detailHtml = await detailResponse.text();
      } catch { /* Account metadata from search card remains usable. */ }

      const featured = detailHtml ? parseFeaturedSkins(detailHtml) : [];
      const detailText = cleanText(detailHtml);
      const hasStw = /Deluxe\s+STW|Save the World|Salvar el mundo|Salvar el Mundo/i.test(detailText);
      const idleDays = getIdleDays(card.text);
      const imagePaths: string[] = [];
      const storedSkinNames: string[] = [];

      for (const skin of featured) {
        try {
          const imageResponse = await fetch(skin.url, { headers: { "User-Agent": "Mozilla/5.0 (compatible; StoreCatalog/1.0)", "Accept": "image/avif,image/webp,image/png,image/*" } });
          if (!imageResponse.ok) continue;
          const contentType = imageResponse.headers.get("content-type");
          if (!contentType?.startsWith("image/")) continue;
          const bytes = new Uint8Array(await imageResponse.arrayBuffer());
          if (!bytes.length || bytes.length > 2_000_000) continue;
          const path = `cosmetics/${await sha256(skin.url)}.${extensionFor(contentType, skin.url)}`;
          const { error: uploadError } = await supabase.storage.from("catalogo-skins").upload(path, bytes, { contentType, upsert: true, cacheControl: "31536000" });
          if (!uploadError) { imagePaths.push(path); storedSkinNames.push(skin.name); totalImages++; }
        } catch { /* Keep the account even if one cosmetic icon cannot be copied. */ }
      }

      const title = card.title.replace(/\s*\|\s*\d+\s*skins?\s*$/i, "").trim() || `Cuenta Fortnite · ${card.skins} skins`;
      const description = `${card.skins} skins · Inactividad aproximada: ${idleDays} días${hasStw ? " · Incluye Salvar el mundo" : ""}`;
      const { error: saveError } = await supabase.rpc("catalogo_lzt_upsert_account", {
        p_listing_id: card.id,
        p_source_url: card.url,
        p_ceo_id: authData.user.id,
        p_title: title,
        p_skin_count: card.skins,
        p_featured_skins: storedSkinNames,
        p_has_stw: hasStw,
        p_idle_days: idleDays,
        p_source_cost: card.price,
        p_image_paths: imagePaths,
        p_description: description,
      });
      if (saveError) throw new Error(`No se pudo guardar una cuenta del catálogo (${card.id}).`);
      results.push({ title, images: imagePaths.length });
      await new Promise(resolve => setTimeout(resolve, 250));
    }

    let nextCursor = "";
    if (offset + batch.length < parsed.cards.length) {
      const samePage = new URL(pageUrl);
      samePage.searchParams.set("__catalog_offset", String(offset + batch.length));
      nextCursor = samePage.href;
    } else if (parsed.nextUrl) {
      nextCursor = parsed.nextUrl;
    }
    const hasMore = !!nextCursor;
    const { error: cursorError } = await supabase.rpc("catalogo_lzt_set_next_url", { p_next_url: nextCursor || "DONE" });
    if (cursorError) throw new Error("Las cuentas se importaron, pero no se pudo guardar la posición para el siguiente lote.");
    return respond({ imported: results.length, images: totalImages, has_more: hasMore, accounts: results, message: hasMore ? "Lote importado. Puedes cargar el siguiente lote cuando lo necesites." : "Se importó el último lote disponible." });
  } catch (error) {
    return respond({ error: error instanceof Error ? error.message : "No se pudo actualizar el catálogo." }, 500);
  }
});

