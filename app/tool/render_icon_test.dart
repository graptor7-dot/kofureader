// Genera assets/icon/icon.png (1024x1024). Ejecutar con:
//   flutter test tool/render_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;

    // Fondo: degradado diagonal rosa → violeta con un brillo arriba.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B98), Color(0xFFFF5D8F), Color(0xFF7A5CFF)],
          stops: [0, 0.35, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(s * 0.25, s * 0.15),
      s * 0.6,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset(s * 0.25, s * 0.15), radius: s * 0.6)),
    );

    // Libro abierto: dos páginas curvas.
    final cx = s / 2;
    final top = s * 0.30;
    final bottom = s * 0.72;
    final half = s * 0.30;
    Path page(double dir) {
      final outer = cx + dir * half;
      return Path()
        ..moveTo(cx, top + s * 0.04)
        ..quadraticBezierTo(cx + dir * half * 0.45, top - s * 0.03, outer, top)
        ..lineTo(outer, bottom - s * 0.04)
        ..quadraticBezierTo(cx + dir * half * 0.45, bottom - s * 0.07, cx, bottom)
        ..close();
    }

    final shadow = Paint()
      ..color = const Color(0xFF3A1F7A).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.save();
    canvas.translate(0, s * 0.03);
    canvas.drawPath(page(-1), shadow);
    canvas.drawPath(page(1), shadow);
    canvas.restore();

    final white = Paint()..color = Colors.white;
    canvas.drawPath(page(-1), white);
    canvas.drawPath(page(1), Paint()..color = const Color(0xFFF3EEFF));

    // Líneas de texto (paneles) en la página izquierda.
    final ink = Paint()
      ..color = const Color(0xFFFF5D8F).withValues(alpha: 0.55)
      ..strokeWidth = s * 0.022
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = top + s * 0.11 + i * s * 0.075;
      canvas.drawLine(Offset(cx - half * 0.78, y), Offset(cx - half * (i.isEven ? 0.18 : 0.32), y), ink);
    }

    // Dado en la página derecha (el botón aleatorio).
    final die = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx + half * 0.5, (top + bottom) / 2), width: s * 0.17, height: s * 0.17),
      Radius.circular(s * 0.035),
    );
    canvas.drawRRect(die, Paint()..color = const Color(0xFF8C6BFF));
    final pip = Paint()..color = Colors.white;
    final d = s * 0.045;
    final c = die.center;
    for (final o in [Offset(-d, -d), Offset(d, -d), Offset.zero, Offset(-d, d), Offset(d, d)]) {
      canvas.drawCircle(c + o, s * 0.016, pip);
    }

    // Lomo.
    canvas.drawLine(
      Offset(cx, top + s * 0.04),
      Offset(cx, bottom),
      Paint()
        ..color = const Color(0xFFD9CCFF)
        ..strokeWidth = s * 0.008,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  testWidgets('render icon', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: SizedBox(width: 1024, height: 1024, child: CustomPaint(painter: _IconPainter())),
      ),
    );
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('assets/icon/icon.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
