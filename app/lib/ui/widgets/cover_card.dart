import 'package:flutter/material.dart';

import '../../theme.dart';

/// Imagen (de Komga o de un fichero descargado) con aparición suave.
class KomgaImage extends StatelessWidget {
  final ImageProvider image;
  final BoxFit fit;
  final Alignment alignment;

  /// Imagen de Komga con cabeceras de autenticación.
  KomgaImage({
    super.key,
    required String url,
    required Map<String, String> headers,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  }) : image = NetworkImage(url, headers: headers);

  const KomgaImage.provider(this.image, {super.key, this.fit = BoxFit.cover, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) {
    return Image(
      image: image,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSync) {
        if (wasSync) return child;
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
  final double progress; // 0..1
  final bool read;
  final bool favorite;
  final bool selected;
  final bool selectionActive;
  final Color? sourceColor;
  final IconData? kindIcon;
  final ImageProvider? image; // sustituye a imageUrl (p. ej. portada descargada)
  final bool downloaded;
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
    this.progress = 0,
    this.read = false,
    this.favorite = false,
    this.selected = false,
    this.selectionActive = false,
    this.sourceColor,
    this.kindIcon,
    this.image,
    this.downloaded = false,
    this.downloadProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Expanded(
                child: AnimatedContainer(
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
                        image != null ? KomgaImage.provider(image!) : KomgaImage(url: imageUrl, headers: headers),
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
                        if (badge != null) Positioned(top: 8, right: 8, child: _Pill(text: badge!)),
                        Positioned(
                          left: 8,
                          bottom: progress > 0 && progress < 1 ? 12 : 8,
                          child: Row(
                            children: [
                              if (sourceColor != null) _Dot(color: sourceColor!),
                              if (kindIcon != null) ...[
                                const SizedBox(width: 6),
                                Icon(kindIcon, size: 14, color: Colors.white70),
                              ],
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
                          const Positioned(
                            right: 8,
                            bottom: 8,
                            child: Icon(Icons.favorite_rounded, size: 18, color: Kofu.accent),
                          ),
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
                            top: 8,
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
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
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

const coverGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 168,
  childAspectRatio: 0.54,
  crossAxisSpacing: 16,
  mainAxisSpacing: 20,
);
