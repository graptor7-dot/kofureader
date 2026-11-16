# Lector: separar los capítulos extra sin confundirlos con partes de un capítulo

> Documento para darle a Claude Code en el proyecto del lector. Las reglas salen de analizar la biblioteca real
> (41.148 capítulos de manga y manhwa, noviembre de 2026). Los números entre paréntesis son cuántos casos hay.

## Lo que quiero

1. La lista de capítulos sigue **en orden por número**, como ahora.
2. Los **extras** (omakes, ilustraciones, avisos, extras de tomo, capítulos especiales…) salen en un **apartado
   aparte, «Extras»**, dentro de la misma serie. No se mueve ningún fichero: es el lector quien los clasifica.
3. Las **partes** de un capítulo (X.1, X.2, «Part 2», «Segunda parte»…) **no son extras**: son historia y van
   en la lista normal, en su sitio.
4. Un capítulo que llega **tarde** (su número es menor que lo que ya he leído) **nunca** sale como «siguiente»
   ni interrumpe la lectura: el extra del 20 no me puede saltar al terminar el 100.
5. Si el lector se equivoca, puedo **corregirlo a mano** («es un extra» / «es historia») y se recuerda.

## Paso 1: leer el nombre

Los ficheros vienen de Suwayomi y de varias fuentes, así que el nombre trae ruido. Antes de clasificar:

- **Quitar el prefijo del grupo de scan**: todo lo anterior a `_` cuando detrás viene `Chapter`, `Ch.`, `Cap` o `ex`.
  `Violet Scans_Chapter 40.5.cbz` → `Chapter 40.5`. Ojo: el nombre del grupo puede contener palabras de extra
  («**Extra Innings** Scanlation_Chapter 3_ Manager») y **no** cuentan.
- **MANGA Plus**: `MANGA Plus_#139 - Mission_ 139` → número 139. `MANGA Plus_ex - Illustration` → sin número y **ex**.
- **Número**: detrás de `Chapter`, `Ch.`, `Cap.`, `Capítulo`, `Episode`, `Ep.` o `#`; si no hay, el número
  con el que **acaba** el nombre (`Official_Mischief 100`). Con decimales: `12.5`, `140.2`.
- **Título**: lo que va detrás del número (`Chapter 28.5_ Extras del Volumen 3` → «Extras del Volumen 3»).
  Quitar las etiquetas de grupo entre paréntesis (`(1r0n)`, `(Official)`), que no son título.
- Si el CBZ trae `ComicInfo.xml`, usar también su `<Title>` y `<Number>`.

## Paso 2: clasificar (en este orden; la primera regla que encaje gana)

### A. Extra seguro (≈ 270 en la biblioteca)

1. **Sin número** y empieza por `ex` o por una palabra de extra (MANGA Plus `ex - ILLUSTRATION`, `ex - Bonus Chapter`,
   `ex - Capítulo especial 3`, `One-shot`). (13)
2. El **título empieza** por una etiqueta de extra (253):
   `Extra`, `Extras`, `Bonus`, `Omake`, `Illustration(s)`, `Twitter extra`, `Side story`, `After story`, `Afterword`,
   `Notice`, `Aviso`, `Anuncio`, `Announcement`, `Hiatus`, `Gallery`, `Character profile/design`,
   `Volume N Extras`, `Vol. N extra`, `Extras del Volumen N`, `Tomo N extra`,
   `Special chapter`, `Extra chapter`, `Bonus chapter`, `Extra edition`, `Capítulo especial`, `One-shot`.
3. El título **contiene** una de estas expresiones en cualquier sitio: `Twitter extra`, `Volume N Extras`,
   `Bonus chapter`, `Extra chapter`, `Extra Edition`, `Omake`.

**Cuidado con los falsos positivos**: la palabra suelta **no** basta si forma parte de un título normal.
Son capítulos normales: «Chapter 32_ **Special** Time», «Chapter 28_ **Special** Dinner Table»,
«Chapter 6_ The **Extra** Head», «Chapter 136_ Entrega **especial**», «Chapter 100_ A **Special** Time».
Por eso la regla 2 exige que la etiqueta vaya **al principio** del título, y la 3 solo acepta expresiones completas.

### B. Parte de un capítulo, es historia (≈ 115)

Solo para números con decimal:

1. El título lo dice: `Part 2`, `Part II`, `Part Two`, `(part 2)`, `Pt. 2`, `(2)`, `Segunda parte`,
   `(Primera parte)`, `(Segunda parte)`, `Tercera parte`. (9)
   Ej.: «Chapter 73.1_ Mother, Daughter, and Slave — **Part II**», «Chapter 56.1_ **(2)** The Limit»,
   «Chapter 19.5_ Piedra Mágica (**Segunda parte**)».
2. Tiene **el mismo título** que el capítulo entero X (quitando las marcas de parte). (105)
   Ej.: «Chapter 22_ Case.22 The Magic Doctor (Part One)» y «Chapter 22.5_ Case.22 The Magic Doctor (Part Two)».
3. Es una **serie seguida** `.1, .2, .3…` y **no existe el entero X** (el capítulo se subió solo en partes).

### C. Decimal sin pistas en el nombre (≈ 820: el caso difícil)

Son ficheros como «Chapter 12.5.cbz» a secas. **El número de páginas ayuda, pero no decide solo**:
en la biblioteca hay decimales largos que son historia (*A Sign of Affection* 7.3–7.9 «Official», 36–41 págs) y
.5 cortos que también lo son. Regla prudente:

- `.5` o mayor (`.6`, `.7`…) **y** muy corto: **≤ 8 páginas o menos del 35 % de la mediana de páginas de la serie**
  → **extra probable** (ilustraciones, avisos, mini-omakes). (≈ 270 caen aquí)
- `.1` a `.4` → **parte** (historia), aunque sea corto.
- Todo lo demás → **historia, en la lista normal**. Ante la duda, mejor que se vea en su sitio que esconderlo.
- Marcar los «probables» con un indicador discreto para poder corregirlos con un toque.

### D. Capítulo normal

Número entero (o sin decimal) y sin etiqueta de extra → lista normal.
`Chapter 0` con título de prólogo es historia; con etiqueta de extra («Chapter 0_ Volume 2 extras») es extra.

## Paso 3: dónde se muestra cada cosa

- **Lista principal**: capítulos normales + partes, ordenados por número (las partes tras su entero: 22, 22.5, 23).
- **Apartado «Extras»**: los extras (seguros y probables), ordenados por número; cada uno indica a qué altura va
  («tras el capítulo 20») según la parte entera de su número.
- **Llegadas tardías**: al detectar capítulos nuevos, si el número es **menor** que el último capítulo leído, no es
  «siguiente»: va a «Extras» si es extra, y si es historia sale con un aviso «nuevo, anterior a donde vas» en su sitio,
  sin saltar al terminar el capítulo actual.
- **«Siguiente capítulo»** al terminar uno = el siguiente **por número** en la lista principal, nunca un extra ni una
  llegada tardía.

## Paso 4: corrección manual

Mantener por serie una lista de excepciones (`ruta del fichero → extra | historia`) que gane a las reglas.
Guardarla aparte (no renombrar ni tocar los ficheros: renombrar rompe el seguimiento de Komga y Suwayomi).

## Casos de prueba (de la biblioteca real)

| Fichero | Esperado |
|---|---|
| `Chapter 13.5_ Extras.cbz` | extra |
| `Chapter 28.5_ Extras del Volumen 3.cbz` | extra |
| `Chapter 32.5_ Aviso.cbz` | extra |
| `Senko-san's Abode_Chapter 5.5_ Volume 1 Extras.cbz` | extra |
| `Chapter 28.5_ Twitter extra - Merry Christmas.cbz` | extra |
| `MANGA Plus_ex - ILLUSTRATION.cbz` | extra |
| `MANGA Plus_ex - Capítulo especial 1.cbz` | extra |
| `Chapter 21.6_ Case. 21.6 TENGA①.cbz` (4 págs) | extra probable (corto) |
| `Chapter 19.5_ Piedra Mágica (Segunda parte).cbz` | historia (parte) |
| `Chapter 73.1_ Mother, Daughter, and Slave — Part II.cbz` | historia (parte) |
| `Chapter 56.1_ (2) The Limit.cbz` | historia (parte) |
| `Seven Seas Entertainment_Chapter 10.1_ (1r0n).cbz` (sin entero 10) | historia (parte) |
| `Chapter 7.5_ Official.cbz` (38 págs) | historia |
| `Chapter 32_ Special Time.cbz` | historia (falso positivo a evitar) |
| `Extra Innings Scanlation_Chapter 3_ Manager.cbz` | historia (la palabra está en el grupo) |
| `Chapter 136_ Entrega especial.cbz` | historia |
| `Official_Mischief 100.cbz` | historia, número 100 |
