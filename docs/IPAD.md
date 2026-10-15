# Instalar KofuReader en el iPad (sin Mac y gratis)

Resumen: **GitHub compila la app en un Mac en la nube** y te da un fichero `.ipa`.
**SideStore** (o AltStore) la firma con tu Apple ID gratuito y la instala.

Con un Apple ID gratuito la firma dura **7 días**; SideStore la renueva desde el propio iPad
(AltStore necesita que el PC esté encendido en la misma wifi). Como mucho 3 apps así a la vez.

---

## Parte 1 — Compilar el .ipa en GitHub (una vez configurado, es pulsar un botón)

1. Crea una cuenta en <https://github.com> si no tienes.
2. Sube este proyecto a un repositorio nuevo (puede ser **privado**). Si quieres, lo hago yo:
   solo necesito que instales y conectes la herramienta `gh` (te digo cómo cuando toque).
3. En el repositorio: pestaña **Actions → iOS (sin firmar) → Run workflow**.
4. Tarda unos 10–15 min. Al acabar, abre la ejecución y descarga el artefacto **KofuReader-ipa**
   (es un .zip con `KofuReader.ipa` dentro).

> Minutos gratis: con repositorio **público** son ilimitados. Con **privado** tienes 2.000 min/mes,
> pero los Mac cuentan x10 → unas 10–15 compilaciones al mes, de sobra para uso personal.

Para mandar el `.ipa` al iPad: AirDrop no hay en Windows, así que súbelo a iCloud Drive / OneDrive /
Telegram "mensajes guardados" y ábrelo desde la app Archivos del iPad.

## Parte 2 — Instalar con SideStore (recomendado)

SideStore cambia de vez en cuando su método de instalación, así que sigue su guía oficial:
<https://docs.sidestore.io>

A grandes rasgos:

1. Instalas SideStore en el iPad una sola vez con ayuda del PC (su guía usa un programa para Windows
   y tu Apple ID). Recomendable usar un Apple ID secundario solo para esto.
2. Dentro de SideStore: **My Apps → +** y eliges `KofuReader.ipa` desde Archivos.
3. En el iPad: **Ajustes → General → VPN y gestión de dispositivos** → confía en tu Apple ID.
4. Cada pocos días abre SideStore y pulsa **Refresh All** (o deja que lo haga solo).

### Alternativa: AltStore

<https://faq.altstore.io> — usa **AltServer** en Windows (requiere iTunes e iCloud descargados de la
web de Apple, no de la Microsoft Store). Renueva la firma cuando el iPad y el PC están en la misma wifi.

## Parte 3 — Primer arranque en el iPad

1. Asegúrate de que **Tailscale** está conectado en el iPad.
2. En KofuReader pulsa **"Ya uso KofuReader en otro dispositivo"** y pon la URL y el token de KofuSync.
3. Aparecerán tus servidores: toca cada uno y añade su **API key**.

## Actualizar la app

Vuelve a lanzar el workflow en GitHub, descarga el nuevo `.ipa` y en SideStore instálalo encima.
Tus listas no se pierden (están en el iPad y en KofuSync).
