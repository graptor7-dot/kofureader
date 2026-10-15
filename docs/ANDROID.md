# Instalar KofuReader en Android

Android es mucho más sencillo que el iPad: se instala el `.apk` directamente, sin caducidad.
GitHub lo compila gratis (no hace falta instalar nada de Android en el PC).

## Una sola vez: la clave de firma

La app se firma siempre con **la misma clave** para que cada actualización se instale encima
(sin desinstalar ni perder descargas). La clave está en la carpeta `android-firma/` del proyecto,
que **no se sube a GitHub**.

> ⚠️ Haz copia de seguridad de `android-firma/` (por ejemplo en tu NAS). Si se pierde, para
> actualizar habría que desinstalar la app y volver a instalarla.

Añade estos dos secretos al repositorio en GitHub:
**Settings → Secrets and variables → Actions → New repository secret**

| Nombre | Valor |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | todo el contenido de `android-firma/KEYSTORE_BASE64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | el contenido de `android-firma/KEYSTORE_PASSWORD.txt` |

## Compilar

**Actions → Android → Run workflow**. Tarda unos 5–8 minutos. Descarga el artefacto
**KofuReader-apk** (un .zip con `KofuReader.apk` dentro).

## Instalar en el móvil

1. Pasa `KofuReader.apk` al móvil (Telegram, Drive, cable…) y ábrelo.
2. Android pedirá permiso para **instalar apps de origen desconocido** desde esa app: acéptalo.
3. Para actualizar, repite con el APK nuevo: se instala encima.

## Primer arranque

1. Tailscale conectado en el móvil (para el Komga privado y KofuSync).
2. **"Ya uso KofuReader en otro dispositivo"** → URL y token de KofuSync.
3. Añade la API key de cada servidor.
