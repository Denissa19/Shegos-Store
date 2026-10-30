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
    return u.protocol === "https:" && u.hostname === "lzt.market" && /^\/epicgames(?:\/fortnite)?\/?$/.test(u.pathname);
  } catch { return false; }
}

function parseCards(html: string, pageUrl: string) {
  const starts = [...html.matchAll(/<div\b[^>]*class=["'][^"']*\b(?:marketItemCard|marketItem--\d+)\b[^"']*["'][^>]*>/gi)].map(m => m.index ?? -1).filter(x => x >= 0);
  const cards = [] as Array<{ id: string; url: string; title: string; price: number; skins: number; text: string }>;
  for (let i = 0; i < starts.length; i++) {
    const block = html.slice(starts[i], starts[i + 1] ?? html.length);
    const titledLink = block.match(/<a\b[^>]*href=["']([^"']+)["'][^>]*>[\s\S]*?class=["'][^"']*\bitemTitle\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
    const listingLink = titledLink || [...block.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)].find(m => /https?:\/\/lzt\.market\/\d+|href=["']\/?\d+\//i.test(m[0]));
    if (!listingLink) continue;
    let url: URL;
    try { url = new URL(decodeHtml(listingLink[1]), pageUrl); } catch { continue; }
    if (url.hostname !== "lzt.market") continue;
    const id = url.pathname.match(/^\/(\d+)\/?$/)?.[1];
    if (!id) continue;
    const price = Number(block.match(/class=["'][^"']*\bValue\b[^"']*["'][^>]*data-value=["']([\d.]+)["']/i)?.[1]);
    if (!Number.isFinite(price) || price <= 0) continue;
    const text = cleanText(block);
    const skins = Number(text.match(/(?:\||\b)(\d{1,5})\s*(?:skins?|скинов|скина|скин)\b/i)?.[1]) || 0;
    cards.push({ id, url: `https://lzt.market/${id}/`, title: cleanText(listingLink[2]).slice(0, 100) || `Cuenta Fortnite · ${skins} skins`, price, skins, text });
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
    if (found.length >= 24) break;
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

function field(record: Record<string, unknown>, names: string[]) {
  const entries = Object.entries(record);
  for (const name of names) {
    const found = entries.find(([key, value]) => key.toLocaleLowerCase().replace(/[^a-z0-9]/g, "") === name.toLocaleLowerCase().replace(/[^a-z0-9]/g, "") && value !== undefined && value !== null && value !== "");
    if (found) return found[1];
  }
  return undefined;
}

function listImageValues(value: unknown, out: string[] = []): string[] {
  if (out.length >= 6 || value == null) return out;
  if (typeof value === "string") {
    const candidate = value.trim();
    if ((candidate.startsWith("https://") || candidate.startsWith("data:image/")) && !out.includes(candidate)) out.push(candidate);
    return out;
  }
  if (Array.isArray(value)) {
    for (const entry of value) listImageValues(entry, out);
    return out;
  }
  if (typeof value === "object") {
    const image = value as Record<string, unknown>;
    for (const key of ["url", "src", "image_url", "image", "original", "href"]) {
      if (image[key]) listImageValues(image[key], out);
    }
  }
  return out;
}

async function storeAgentyImage(supabase: ReturnType<typeof createClient>, rawSource: string) {
  let bytes: Uint8Array;
  let contentType: string;
  let stableKey: string;
  const dataMatch = rawSource.match(/^data:image\/(png|jpeg|jpg|webp);base64,([\s\S]+)$/i);
  if (dataMatch) {
    contentType = `image/${dataMatch[1].toLowerCase() === "jpg" ? "jpeg" : dataMatch[1].toLowerCase()}`;
    bytes = Uint8Array.from(atob(dataMatch[2]), c => c.charCodeAt(0));
    stableKey = rawSource.slice(0, 500);
  } else {
    const source = new URL(rawSource);
    const host = source.hostname.toLocaleLowerCase();
    const allowed = host === "lzt.market" || host.endsWith(".lzt.market") || host === "fortnite-api.com" || host.endsWith(".fortnite-api.com");
    if (source.protocol !== "https:" || !allowed || source.username || source.password) throw new Error("Agenty incluyó una imagen de un dominio no permitido.");
    const response = await fetch(source.href, { headers: { "User-Agent": "Mozilla/5.0 (compatible; StoreCatalog/1.0)", "Accept": "image/avif,image/webp,image/png,image/jpeg,image/*" } });
    if (!response.ok) throw new Error(`No se pudo descargar una imagen (${response.status}).`);
    contentType = (response.headers.get("content-type") || "").split(";")[0].toLowerCase();
    if (!/^image\/(png|jpeg|webp)$/.test(contentType)) throw new Error("La imagen debe ser JPG, PNG o WEBP.");
    bytes = new Uint8Array(await response.arrayBuffer());
    stableKey = source.href;
  }
  if (!bytes.length || bytes.length > 2_000_000) throw new Error("Cada imagen debe pesar menos de 2 MB.");
  const ext = contentType === "image/jpeg" ? "jpg" : contentType.split("/")[1];
  const path = `agenty/${await sha256(stableKey)}.${ext}`;
  const { error } = await supabase.storage.from("catalogo-skins").upload(path, bytes, { contentType, upsert: true, cacheControl: "31536000" });
  if (error) throw new Error("No se pudo guardar una imagen en el catálogo privado.");
  return path;
}

async function importAgentyRows(supabase: ReturnType<typeof createClient>, rows: unknown[], ceoId: string) {
  if (!Array.isArray(rows) || rows.length < 1 || rows.length > 12) throw new Error("Envía entre 1 y 12 publicaciones por lote.");
  let images = 0;
  const imported: string[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (!row || typeof row !== "object" || Array.isArray(row)) throw new Error(`La fila ${i + 1} no tiene formato de publicación.`);
    const record = row as Record<string, unknown>;
    const rawUrl = field(record, ["listing_url", "publication_url", "source_url", "url", "link", "enlace"]);
    let listingId = String(field(record, ["listing_id", "account_id", "item_id", "listingid", "id_anuncio", "id"]) ?? "").match(/\d+/)?.[0] || "";
    let sourceUrl = "";
    if (rawUrl) {
      try {
        const parsedUrl = new URL(String(rawUrl));
        const match = parsedUrl.pathname.match(/^\/(\d+)\/?$/);
        if (parsedUrl.protocol !== "https:" || parsedUrl.hostname !== "lzt.market" || !match) throw new Error("enlace del anuncio inválido");
        listingId = listingId || match[1];
        sourceUrl = `https://lzt.market/${listingId}/`;
      } catch (error) {
        throw new Error(`Fila ${i + 1}: ${error instanceof Error ? error.message : "enlace del anuncio inválido"}.`);
      }
    }
    if (!/^\d{5,}$/.test(listingId)) throw new Error(`Fila ${i + 1}: falta el ID numérico de la publicación.`);
    sourceUrl ||= `https://lzt.market/${listingId}/`;

    const rawPrice = field(record, ["price_usd", "original_price_usd", "original_price", "price", "precio_usd", "precio_original", "precio", "cost"]);
    const priceText = String(rawPrice ?? "").replace(/[^\d.,-]/g, "");
    const priceValue = Number(priceText.includes(".") ? priceText.replace(/,/g, "") : priceText.replace(/,/g, "."));
    if (!Number.isFinite(priceValue) || priceValue <= 0) throw new Error(`Fila ${i + 1}: falta un precio original válido en USD.`);

    const skinsRaw = field(record, ["skin_names", "featured_skins", "skins_destacadas", "skins"]);
    const skinNames = Array.isArray(skinsRaw)
      ? skinsRaw.map(item => typeof item === "string" ? item : (item && typeof item === "object" ? String((item as Record<string, unknown>).name || "") : "")).filter(Boolean).slice(0, 12)
      : typeof skinsRaw === "string" ? skinsRaw.split(/[,;|]/).map(item => item.trim()).filter(Boolean).slice(0, 12) : [];
    const rawTitle = field(record, ["title", "name", "nombre", "publication_title", "listing_title", "titulo"]);
    const rawCount = field(record, ["skin_count", "skins_count", "cantidad_skins", "skins_total", "number_of_skins"]);
    const countFromTitle = Number(String(rawTitle ?? "").match(/(\d{1,5})\s*skins?\b/i)?.[1]) || 0;
    const countValue = Number(String(rawCount ?? "").match(/\d+/)?.[0]) || countFromTitle || skinNames.length;
    const rawDescription = field(record, ["description", "details", "descripcion", "detalles", "published_details"]);
    const description = String(rawDescription ?? "").replace(/https?:\/\/(?:www\.)?lzt\.market\/\S*/gi, "").replace(/\s+/g, " ").trim().slice(0, 1200);
    const rawStw = field(record, ["has_stw", "tiene_stw", "stw", "save_the_world"]);
    const hasStw = typeof rawStw === "boolean" ? rawStw : /^(true|yes|sí|si|con stw|1)$/i.test(String(rawStw ?? ""));
    const rawIdle = field(record, ["idle_days", "days_inactive", "dias_inactividad", "inactivity_days"]);
    const idleValue = Number(String(rawIdle ?? "").match(/\d+/)?.[0]);
    const idleDays = Number.isFinite(idleValue) ? Math.max(0, Math.min(3650, idleValue)) : 90;
    const title = String(rawTitle ?? `Cuenta Fortnite · ${countValue} skins`).replace(/\s+/g, " ").trim().slice(0, 120);
    const rawImage = field(record, ["account_image_url", "generated_image_url", "cover_image_url", "account_photo_url", "imagen_cuenta", "foto_cuenta", "image_url", "image"]);
    const imageSource = listImageValues(rawImage)[0];
    const imagePaths: string[] = [];
    if (imageSource) {
      imagePaths.push(await storeAgentyImage(supabase, imageSource));
      images++;
    }
    const { error } = await supabase.rpc("catalogo_lzt_upsert_account", {
      p_listing_id: listingId,
      p_source_url: sourceUrl,
      p_ceo_id: ceoId,
      p_title: title,
      p_skin_count: countValue,
      p_featured_skins: skinNames,
      p_has_stw: hasStw,
      p_idle_days: idleDays,
      p_source_cost: priceValue,
      p_image_paths: imagePaths,
      p_description: description,
    });
    if (error) throw new Error(`Fila ${i + 1}: no se pudo guardar la publicación ${listingId}.`);
    imported.push(title);
  }
  return { imported: imported.length, images, titles: imported };
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
    if (body?.mode === "agenty") {
      const result = await importAgentyRows(supabase, body.records, authData.user.id);
      return respond({ ...result, message: "Lote de Agenty importado. Los precios de venta se calcularon en Supabase." });
    }
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
      const paidSkins = Number(detailText.match(/(\d{1,4})\s+paid\b/i)?.[1]) || 0;
      const vbuckAmount = detailText.match(/(?:≈|~)?\s*([\d,]+)\s*V[-\s]?Bucks?/i)?.[1]?.replace(/,/g, "") || "";
      const idleDays = getIdleDays(card.text);
      const imagePaths: string[] = [];
      const storedSkinNames: string[] = [];

      for (let start = 0; start < featured.length; start += 4) {
        const uploaded = await Promise.all(featured.slice(start, start + 4).map(async skin => {
          try {
            const imageResponse = await fetch(skin.url, { headers: { "User-Agent": "Mozilla/5.0 (compatible; StoreCatalog/1.0)", "Accept": "image/avif,image/webp,image/png,image/*" } });
            if (!imageResponse.ok) return null;
            const contentType = imageResponse.headers.get("content-type");
            if (!contentType?.startsWith("image/")) return null;
            const bytes = new Uint8Array(await imageResponse.arrayBuffer());
            if (!bytes.length || bytes.length > 2_000_000) return null;
            const path = `cosmetics/${await sha256(skin.url)}.${extensionFor(contentType, skin.url)}`;
            const { error: uploadError } = await supabase.storage.from("catalogo-skins").upload(path, bytes, { contentType, upsert: true, cacheControl: "31536000" });
            return uploadError ? null : { path, name: skin.name };
          } catch { return null; }
        }));
        uploaded.filter(Boolean).forEach(item => { imagePaths.push(item!.path); storedSkinNames.push(item!.name); totalImages++; });
      }

      const title = card.title.replace(/\s*\|\s*\d+\s*skins?\s*$/i, "").trim() || `Cuenta Fortnite · ${card.skins} skins`;
      const description = `${card.skins} skins${paidSkins ? ` · ${paidSkins} paid` : ""}${vbuckAmount ? ` · ${vbuckAmount} V-Bucks` : ""} · Inactividad aproximada: ${idleDays} días${hasStw ? " · Incluye Salvar el mundo" : ""}`;
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

