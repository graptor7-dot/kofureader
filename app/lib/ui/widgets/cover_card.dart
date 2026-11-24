import 'package:flutter/material.dart';

import '../../data/cover_cache.dart';
import '../../theme.dart';
import '../desktop.dart';

/// Imagen (de Komga o de un fichero descargado) con aparición suave.
class KomgaImage extends StatelessWidget {
  final ImageProvider image;
  final BoxFit fit;
  final Alignment alignment;
  final bool fade; // aparición suave (en el lector se desactiva: ya va precargada)

  /// Portada de Komga con cabeceras de autenticación, guardada en disco ([CoverCache]).
  KomgaImage({
    super.key,
    required String url,
    required Map<String, String> headers,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fade = true,
  }) : image = CachedCoverImage(url, headers: headers);

  const KomgaImage.provider(
    this.image, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fade = true,
  });

  @override
  Widget build(BuildContext context) {
    return Image(
      image: image,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSync) {
        if (wasSync || !fade) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Kofu.surfaceHigh,
        child: Center(child: Icon(Icons.image_not_supported_outlined, color: Kofu.muted)),
      ),
    );
  }
}

/// Portada con título para las rejillas de series y libros.
class CoverCard extends StatelessWidget {
  final String imageUrl;
  final Map<String, String> headers;
  final String title;
  final String? subtitle;
  final String? badge;
  final String? tag; // etiqueta de tipo arriba a la izquierda (p. ej. Novela web)
  final Color? tagColor;
  final double progress; // 0..1
  final bool read;
  final bool favorite;
  final bool complete; // edición completa
  final Widget? placeholder; // en vez de imagen (p. ej. obra sin portada)
  final bool selected;
  final bool selectionActive;
  final Color? sourceColor;
  final IconData? kindIcon;
  final ImageProvider? image; // sustituye a imageUrl (p. ej. portada descargada)
  final bool downloaded;
  final bool reviewed; // revisado en el modo gestión (solo PC)
  final bool gone; // borrado del servidor: se muestra apagado y tachado
  final List<Widget> pills; // pastillas arriba a la izquierda (nº de capítulo, idioma…)
  final Widget? actions; // entre la portada y el título (botones del modo gestión)
  final Widget? overlay; // encima de la portada (p. ej. botones del modo gestión)
  final bool stacked; // agrupación: se dibuja como un montón de libros
  final double? downloadProgress; // no nulo mientras se descarga
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const CoverCard({
    super.key,
    required this.imageUrl,
    required this.headers,
    required this.title,
    required this.onTap,
    this.onLongPress,
    this.subtitle,
    this.badge,
    this.tag,
    this.tagColor,
    this.progress = 0,
    this.read = false,
    this.favorite = false,
    this.complete = false,
    this.placeholder,
    this.selected = false,
    this.selectionActive = false,
    this.sourceColor,
    this.kindIcon,
    this.image,
    this.downloaded = false,
    this.stacked = false,
    this.overlay,
    this.pills = const [],
    this.actions,
    this.gone = false,
    this.reviewed = false,
    this.downloadProgress,
  });

  double get _top => reviewed && !gone ? 30 : 8;

  Widget _cover() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Kofu.radius),
        border: Border.all(
          color: selected ? Kofu.accent : Colors.white.withValues(alpha: 0.06),
          width: selected ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (selected ? Kofu.accent : Colors.black).withValues(alpha: selected ? 0.35 : 0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Kofu.radius - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Kofu.surfaceHigh),
            placeholder ?? (image != null ? KomgaImage.provider(image!) : KomgaImage(url: imageUrl, headers: headers)),
            if (read) ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
            // Degradado inferior para que se lean las insignias.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x99000000)],
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                top: _top,
                right: 8,
                child: _Pill(text: badge!),
              ),
            if (complete && !selectionActive && pills.isEmpty)
              Positioned(top: _top, left: 8, child: const CompleteBadge()),
            if (pills.isNotEmpty && !selectionActive)
              Positioned(
                top: _top,
                left: 8,
                right: badge != null ? 56 : 8,
                child: Wrap(spacing: 4, runSpacing: 4, children: [if (complete) const CompleteBadge(), ...pills]),
              ),
            if (tag != null && !complete && !selectionActive && pills.isEmpty)
              Positioned(
                top: _top,
                left: 8,
                child: _TagPill(text: tag!, color: tagColor ?? Kofu.accent2),
              ),
            Positioned(
              left: 8,
              bottom: progress > 0 && progress < 1 ? 12 : 8,
              child: Row(
                children: [
                  if (sourceColor != null) _Dot(color: sourceColor!),
                  if (kindIcon != null) ...[const SizedBox(width: 6), Icon(kindIcon, size: 14, color: Colors.white70)],
                  if (downloadProgress != null) ...[
                    const SizedBox(width: 6),
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        value: downloadProgress == 0 ? null : downloadProgress,
                        strokeWidth: 2.5,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ] else if (downloaded) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.download_done_rounded, size: 16, color: Kofu.read),
                  ],
                ],
              ),
            ),
            if (favorite)
              const Positioned(right: 8, bottom: 8, child: Icon(Icons.favorite_rounded, size: 18, color: Kofu.accent)),
            if (read) const Center(child: Icon(Icons.check_circle_rounded, color: Kofu.read, size: 32)),
            if (progress > 0 && progress < 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.black45,
                  color: Kofu.accent,
                ),
              ),
            if (selectionActive)
              Positioned(
                top: _top,
                left: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Kofu.accent : Colors.black45,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: selected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                ),
              ),
            if (reviewed && !gone) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Kofu.radius - 1),
                    border: Border.all(color: Kofu.reviewed, width: 2.5),
                  ),
                ),
              ),
              const Positioned(top: 0, left: 0, right: 0, child: _ReviewedStrip()),
            ],
            if (gone) const Positioned.fill(child: _GoneMark()),
            if (overlay != null) Positioned.fill(child: overlay!),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // En la rejilla por filas del PC la tarjeta crece con el título: se ve entero.
    final full = CoverGridScope.fullTitle(context);
    final cover = stacked ? _Stack(child: _cover()) : _cover();
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: selected ? 0.93 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (full) AspectRatio(aspectRatio: coverAspectRatio, child: cover) else Expanded(child: cover),
              if (actions != null) Padding(padding: const EdgeInsets.only(top: 8), child: actions!),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: full ? null : 2,
                overflow: full ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: gone ? Kofu.muted : null,
                  decoration: gone ? TextDecoration.lineThrough : null,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: Kofu.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: Kofu.accentGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  final String text;
  final Color color;

  const _TagPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.8)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3),
    ),
  );
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 6)],
    ),
  );
}

/// Pastilla con el nombre y color del servidor.
class SourceChip extends StatelessWidget {
  final String label;
  final Color color;

  const SourceChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Proporción de la portada cuando la tarjeta no tiene alto fijo.
const coverAspectRatio = 0.68;

/// Indica a las [CoverCard] que están en una rejilla por filas (alto libre).
class CoverGridScope extends InheritedWidget {
  const CoverGridScope({super.key, required super.child});

  static bool fullTitle(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CoverGridScope>() != null;

  @override
  bool updateShouldNotify(CoverGridScope oldWidget) => false;
}

/// Rejilla de portadas. En el PC va por filas, para que cada tarjeta crezca con su
/// título (se lee entero) y con los botones del modo gestión; en móvil y tablet, rejilla fija.
class CoverSliverGrid extends StatelessWidget {
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  const CoverSliverGrid({super.key, required this.itemCount, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return SliverGrid.builder(gridDelegate: coverGridDelegate, itemCount: itemCount, itemBuilder: itemBuilder);
    }
    const d = coverGridDelegate;
    return SliverLayoutBuilder(
      builder: (context, c) {
        final width = c.crossAxisExtent;
        final columns = (width / (d.maxCrossAxisExtent + d.crossAxisSpacing)).ceil().clamp(1, 1000);
        final itemWidth = (width - d.crossAxisSpacing * (columns - 1)) / columns;
        final rows = (itemCount / columns).ceil();
        return SliverList.builder(
          itemCount: rows,
          itemBuilder: (context, r) => Padding(
            padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : d.mainAxisSpacing),
            child: CoverGridScope(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = r * columns; i < r * columns + columns; i++) ...[
                    if (i > r * columns) SizedBox(width: d.crossAxisSpacing),
                    SizedBox(
                      width: itemWidth,
                      child: i < itemCount ? itemBuilder(context, i) ?? const SizedBox() : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pastilla pequeña sobre la portada (nº de capítulo, idioma, traducción máquina…).
class CoverPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color? textColor;
  final IconData? icon;
  final bool solid;

  const CoverPill({super.key, required this.text, required this.color, this.textColor, this.icon, this.solid = true});

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? (solid ? Colors.black : color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: solid ? Colors.black26 : color.withValues(alpha: 0.8)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 3)],
          Text(
            text,
            style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.3, height: 1.1),
          ),
        ],
      ),
    );
  }
}

const coverGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 168,
  childAspectRatio: 0.54,
  crossAxisSpacing: 16,
  mainAxisSpacing: 20,
);

/// Insignia dorada de "edición completa".
class CompleteBadge extends StatelessWidget {
  final bool large;

  const CompleteBadge({super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 7, vertical: large ? 4 : 3),
      decoration: BoxDecoration(
        gradient: Kofu.goldGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: large ? 15 : 12, color: const Color(0xFF3A2A00)),
          const SizedBox(width: 3),
          Text(
            'COMPLETA',
            style: TextStyle(
              color: const Color(0xFF3A2A00),
              fontSize: large ? 11 : 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dos hojas desplazadas detrás de la portada: aspecto de carpeta / montón.
class _Stack extends StatelessWidget {
  final Widget child;

  const _Stack({required this.child});

  @override
  Widget build(BuildContext context) {
    Widget sheet(double alpha) => DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(Kofu.surfaceHigh, Kofu.accent, alpha),
        borderRadius: BorderRadius.circular(Kofu.radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(left: 12, right: 0, top: 0, bottom: 12, child: sheet(0.10)),
        Positioned.fill(left: 6, right: 6, top: 6, bottom: 6, child: sheet(0.22)),
        Positioned.fill(left: 0, right: 12, top: 12, bottom: 0, child: child),
      ],
    );
  }
}

/// Velo de "Borrado del servidor" sobre la portada.
class _GoneMark extends StatelessWidget {
  const _GoneMark();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 30),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.7)),
              ),
              child: const Text(
                'Borrado',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Franja superior de "Revisado" (modo gestión del PC).
class _ReviewedStrip extends StatelessWidget {
  const _ReviewedStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Kofu.reviewed, Kofu.reviewed.withValues(alpha: 0.75)]),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_rounded, size: 13, color: Colors.black),
          SizedBox(width: 4),
          Text(
            'REVISADO',
            style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}
