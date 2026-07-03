#!/bin/bash
# Script para aplicar los 2 patches a index.html
# Uso: ./apply_patches.sh index.html

FILE="${1:-index.html}"

if [ ! -f "$FILE" ]; then
    echo "ERROR: No se encontró el archivo: $FILE"
    exit 1
fi

echo "Aplicando patches a: $FILE"

# PATCH 1: Cambiar imagen de fondo
OLD_BG="url('https://4kwallpapers.com/images/walls/thumbs_2t/10414.jpg')"
NEW_BG="url('https://cms-assets.unrealengine.com/cm6l5gfpm05kr07my04cqgy2x/output=format:webp/cmmkz77321abf06ojpf07ic9o')"

# Use Python for reliable multi-line replacement
python3 - "$FILE" << 'PYEOF'
import sys, re

filepath = sys.argv[1]
with open(filepath, 'r', encoding='utf-8') as f:
    html = f.read()

# Patch 1
old1 = "url('https://4kwallpapers.com/images/walls/thumbs_2t/10414.jpg')"
new1 = "url('https://cms-assets.unrealengine.com/cm6l5gfpm05kr07my04cqgy2x/output=format:webp/cmmkz77321abf06ojpf07ic9o')"
if old1 in html:
    html = html.replace(old1, new1, 1)
    print("✅ Patch 1 aplicado: nuevo fondo")
else:
    print("⚠️  Patch 1: texto no encontrado (puede ya estar aplicado)")

# Patch 2: Replace pushState routing with hash routing
old2_marker = "// Mapa de pestaña → path URL limpio"
new2_marker = "// Mapa de pestaña → hash URL"

if old2_marker in html:
    # Find the full block to replace
    start = html.index(old2_marker)
    
    # Find the end: the IIFE closing })(); after the init function
    # We look for the pattern: })();\n after the popstate listener
    # The block ends after the IIFE that reads location.pathname
    init_iife_end = html.find("        })();", start + 100)
    if init_iife_end != -1:
        end = init_iife_end + len("        })();")
        
        new_routing = """        // Mapa de pestaña → hash URL (compatible con GitHub Pages / servidores estáticos)
        const PESTANA_HASHES = {
            'inicio-landing': '',
            'tienda':         'shop',
            'ids-regalos':    'accounts',
            'recargas':       'services',
            'checkout':       'checkout',
            'rastreo-pedidos':'orders',
            'resenas':        'reviews'
        };
        const HASH_TO_PESTANA = Object.fromEntries(Object.entries(PESTANA_HASHES).map(([k,v]) => [v, k]));

        function abrirPestana(id) {
            document.querySelectorAll('.pestana').forEach(p => p.classList.add('oculto'));
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('activo'));
            document.getElementById(id).classList.remove('oculto');

            // Cerrar sidebar si está abierto (en móvil)
            if (document.getElementById('sidebar').classList.contains('abierto') && window.innerWidth <= 768) {
                toggleSidebar();
            }

            // Ocultar botones flotantes en checkout
            toggleFloatingButtons(id !== 'checkout');

            const btns = Array.from(document.querySelectorAll('.tab-btn')).filter(b => b.getAttribute('onclick') && b.getAttribute('onclick').includes(id));
            btns.forEach(b => b.classList.add('activo'));

            const tabActiva = document.getElementById(id);
            tabActiva.style.animation = 'none'; tabActiva.offsetHeight; tabActiva.style.animation = null;
            window.scrollTo({ top: 0, behavior: 'smooth' });

            // Actualizar hash (no recarga la pagina al refrescar)
            const hash = PESTANA_HASHES[id] || '';
            history.replaceState(null, '', hash ? '#' + hash : location.pathname.split('#')[0]);

            // Asegurar que al entrar a Servicios se vea el menu principal
            if (id === 'recargas') mostrarSubServicio('menu');

            // Si es la pestana de checkout, renderizar el resumen
            if (id === 'checkout') {
                renderCheckoutSummary();
                cambiarPasoCheckout(1);
            }
        }

        // Manejar navegacion con boton Atras/Adelante (hashchange)
        window.addEventListener('hashchange', function() {
            const hash = location.hash.replace('#', '');
            const tab = HASH_TO_PESTANA[hash] || 'inicio-landing';
            document.querySelectorAll('.pestana').forEach(p => p.classList.add('oculto'));
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('activo'));
            const el = document.getElementById(tab);
            if (el) el.classList.remove('oculto');
            Array.from(document.querySelectorAll('.tab-btn'))
                .filter(b => b.getAttribute('onclick')?.includes(tab))
                .forEach(b => b.classList.add('activo'));
            toggleFloatingButtons(tab !== 'checkout');
            if (tab === 'recargas') mostrarSubServicio('menu');
            if (tab === 'checkout') { renderCheckoutSummary(); cambiarPasoCheckout(1); }
        });

        // Al cargar la pagina, detectar el hash y abrir la pestana correcta
        (function() {
            const hash = location.hash.replace('#', '');
            const tab = HASH_TO_PESTANA[hash] || 'inicio-landing';
            if (tab !== 'inicio-landing') {
                setTimeout(() => abrirPestana(tab), 0);
            }
        })();"""
        
        html = html[:start] + new_routing + html[end:]
        print("✅ Patch 2 aplicado: hash-based routing")
    else:
        print("⚠️  Patch 2: no se encontró el fin del bloque")
elif new2_marker in html:
    print("ℹ️  Patch 2: ya está aplicado (hash routing ya presente)")
else:
    print("⚠️  Patch 2: marcador no encontrado")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(html)

print(f"\n✅ Archivo guardado: {filepath}")
print("   Las URLs ahora usan # (ej: shegostore.com/#shop)")
print("   Esto evita el error 404 al refrescar en GitHub Pages.")
PYEOF

