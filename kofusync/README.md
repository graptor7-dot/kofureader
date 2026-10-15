# KofuSync — instalación con Docker Compose

KofuSync es el pequeño servicio que sincroniza **listas, favoritos, modos de lectura y servidores**
entre tus dispositivos con KofuReader. El progreso de lectura no pasa por aquí: lo guarda Komga.

- Imagen muy ligera (un ejecutable, sin base de datos externa).
- Guarda todo en un fichero: `data/kofusync.json`.
- Recomendado: accesible **solo por Tailscale**, igual que tu Komga privado.

---

## 1. Copia la carpeta al servidor

Copia esta carpeta `kofusync` entera (con el fichero oculto `.env`) a la máquina donde tienes Docker,
por ejemplo junto a Komga. Cualquier forma vale:

- **Por SSH desde Windows** (PowerShell):
  ```bash
  scp -r "D:\Proyecto KofuReader\kofusync" usuario@100.71.106.123:~/kofusync
  ```
- **Por la red**: si el servidor es un NAS, arrástrala a una carpeta compartida (por ejemplo `docker/kofusync`).

> El fichero `.env` ya trae un token aleatorio generado para ti. Es la "contraseña" de KofuSync:
> no lo compartas. Si quieres otro, cambia el valor (mínimo 16 caracteres).

## 2. Arráncalo

Por SSH en el servidor:

```bash
cd ~/kofusync
docker compose up -d --build
```

La primera vez tarda un par de minutos porque compila el servidor. Comprueba que está vivo:

```bash
docker compose logs
```

Deberías ver `KofuSync escuchando en el puerto 8080`. Y desde el PC (con Tailscale activo):

```bash
curl http://100.71.106.123:49200/health
```

Debe responder `{"ok":true,"version":1}`.

### ¿Usas Portainer o la app Docker del NAS?

Crea un **Stack / Proyecto** nuevo apuntando a la carpeta `kofusync` (la que contiene `docker-compose.yml`)
y despliégalo. Es exactamente lo mismo que `docker compose up -d --build`.

## 3. Configura KofuReader

En la app: **Ajustes → Sincronización → Configurar**

- **URL:** `http://100.71.106.123:49200`
- **Token:** el valor de `KOFUSYNC_TOKEN` del fichero `.env`

Pulsa *Probar y guardar*. A partir de ahí sincroniza sola: al abrir la app, al volver a ella,
unos segundos después de cada cambio y cada 2 minutos.

**En un dispositivo nuevo** (iPad, móvil): en la pantalla de bienvenida pulsa
*"Ya uso KofuReader en otro dispositivo"* y configura KofuSync primero. Aparecerán tus servidores
Komga; solo tendrás que poner la API key de cada uno (las claves nunca se sincronizan).

## Puerto

El `docker-compose.yml` publica el puerto **49200**. Si ya lo usas, cambia el número de la izquierda
(`"49200:8080"` → `"49300:8080"`) y usa ese en la URL de la app.

**No abras este puerto en el router.** Con Tailscale ya llegas desde cualquier sitio.

## Actualizar

Cuando haya una versión nueva, sustituye los ficheros de la carpeta (sin tocar `data/` ni `.env`) y:

```bash
docker compose up -d --build
```

## Copia de seguridad

Todo está en `data/kofusync.json`. Copia ese fichero y listo. Además, cada dispositivo guarda su propia
copia local, así que si el servidor se pierde, al volver a configurarlo los dispositivos lo rellenan solos.
