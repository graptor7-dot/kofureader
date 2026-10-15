# KofuReader — Documento de diseño

Lector minimalista para Komga, para uso personal. Plataformas: **iPad (principal)**, Android y Windows.

## 1. Decisiones tomadas

| Tema | Decisión |
|---|---|
| Framework | Flutter (un solo código para las 3 plataformas) |
| Servidores | Varios Komga; sus bibliotecas se muestran juntas |
| Progreso de lectura | El nativo de Komga (cada libro en su servidor) |
| Listas, favoritos, ajustes | Base de datos local + sincronización con un mini servicio propio en Docker (**KofuSync**) |
| Modo de lectura | Por biblioteca, con excepción opcional por serie |
| iPad | Compilación en GitHub Actions (macOS) + instalación con SideStore (Apple ID gratuito) |
| Offline | Fase posterior |

## 2. Contenido actual

| Servidor | Biblioteca | Organización | Modo por defecto |
|---|---|---|---|
| Público | Manga | Carpeta por serie | Páginas, derecha → izquierda |
| Público | Manhwa | Carpeta por serie | Scroll vertical |
| Privado (Tailscale) | Manga +18 | Carpeta por **autor** (doujins/oneshots) | Páginas, derecha → izquierda |
| Privado (Tailscale) | Manhwa +18 | Carpeta por serie | Scroll vertical |

En la biblioteca por autores, Komga trata a cada autor como una "serie". La app no necesita nada especial: un autor se comporta como una serie y cada doujin como un libro.
Por eso **las listas y favoritos admiten tanto series como libros sueltos** (para poder guardar un doujin concreto).

## 3. Pantallas

1. **Inicio / Bibliotecas** — las 4 bibliotecas (con indicador del servidor) + tus listas + Favoritos.
2. **Biblioteca** — rejilla de series con filtros y búsqueda.
3. **Serie** — rejilla de libros (capítulos/tomos/doujins), progreso, ❤, añadir a lista, ajuste de modo de lectura.
4. **Lista / Favoritos** — rejilla mixta de series y libros.
5. **Lector** — modo páginas (RTL/LTR) o vertical continuo; marca progreso en Komga.
6. **Ajustes** — servidores, sincronización, modo por defecto de cada biblioteca.

### Comportamiento común en las rejillas

- **Mantener pulsado** → modo selección; tocar para marcar/desmarcar.
- **🎲 Aleatorio** → elige entre lo seleccionado; si no hay selección, entre todo lo visible con los filtros activos.
  - En una página de series (biblioteca, lista) → abre una serie al azar.
  - Dentro de una serie → abre un libro al azar.
  - En una lista con libros sueltos → si sale un libro, lo abre directamente.
- **❤** en cualquier serie o libro → añade/quita de Favoritos con un toque.
- Si un servidor no está accesible (p. ej. Tailscale apagado), su contenido aparece como "sin conexión" y el resto sigue funcionando.

## 4. Modelo de datos (local, sincronizado)

```
Source       id (uuid), name, baseUrl            ← credenciales NO se sincronizan (solo en cada dispositivo)
List         id, name, isFavorites, createdAt
ListItem     id, listId, sourceId, kind (series|book), komgaId, addedAt
SeriesPref   sourceId, seriesId, readingMode
LibraryPref  sourceId, libraryId, readingMode
```

Cada registro lleva `updatedAt` y `deleted` (borrado lógico) para poder sincronizar.

## 5. KofuSync (mini servicio Docker)

- Escrito en Dart, imagen pequeña, guarda todo en un fichero SQLite en un volumen.
- Autenticación con un token fijo definido en una variable de entorno.
- API:
  - `GET  /sync?since=<cursor>` → registros cambiados desde ese cursor + cursor nuevo.
  - `POST /sync` → sube cambios locales.
- Conflictos: gana el cambio más reciente, registro a registro.
- **Exposición recomendada: solo por Tailscale.** El iPad ya necesita Tailscale para el Komga privado, y así el servicio no queda expuesto a internet.
- La app funciona sin conexión al servicio; sincroniza cuando puede.

## 6. Fases

1. ✅ **Base** — añadir servidores, bibliotecas combinadas, series, libros, lector básico (páginas + vertical), progreso en Komga.
2. ✅ **Lo tuyo** — listas, favoritos, selección múltiple, aleatorio, filtros, modo de lectura por biblioteca/serie.
3. ✅ **Sincronización** — KofuSync en Docker (`kofusync/README.md`) + sincronización en la app. Los servidores
   también se sincronizan (sin credenciales); si el mismo Komga se da de alta en dos dispositivos, se fusionan.
4. ✅ **iPad** — workflow en `.github/workflows/ios.yml`, proyecto en GitHub. Guía: `docs/IPAD.md`.
5. ✅ **Offline** — descargar libros/series (botón ⬇ en la serie), pantalla Descargas, lector desde disco y
   progreso guardado sin conexión que se envía a Komga al volver.
