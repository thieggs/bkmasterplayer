import 'package:flutter/material.dart';

/// Logo do BK Music Player desenhada com as cores do tema (claro, escuro, AMOLED,
/// cor da capa): nunca some no fundo. [mono] desenha só as barras, na cor
/// dada (ou na primária), para lugares pequenos.
class BkLogo extends StatelessWidget {
  const BkLogo({super.key, this.size = 40, this.mono = false, this.color});

  final double size;
  final bool mono;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BkLogoPainter(
          mono: mono,
          circle: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.7)!],
          bars: mono ? (color ?? scheme.primary) : scheme.onPrimary,
        ),
      ),
    );
  }
}

class _BkLogoPainter extends CustomPainter {
  _BkLogoPainter({required this.mono, required this.circle, required this.bars});

  final bool mono;
  final List<Color> circle;
  final Color bars;

  // Proporções da logo original (icon.png): 5 barras centradas.
  static const _centers = [0.234, 0.363, 0.5, 0.637, 0.766];
  static const _heights = [0.164, 0.305, 0.461, 0.305, 0.164];
  static const _width = 0.07;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final rect = Offset.zero & Size(d, d);
    if (!mono) {
      canvas.drawCircle(
        rect.center,
        d / 2,
        Paint()
          ..shader = RadialGradient(colors: [circle[0], circle[1]], radius: 0.7).createShader(rect),
      );
    }
    // Sem o círculo, as barras ocupam mais espaço.
    final scale = mono ? 1.35 : 1.0;
    final paint = Paint()..color = bars;
    for (var i = 0; i < _centers.length; i++) {
      final w = d * _width * scale;
      final h = d * _heights[i] * scale;
      final cx = d * (0.5 + (_centers[i] - 0.5) * scale);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, d / 2), width: w, height: h), Radius.circular(w / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BkLogoPainter old) => old.mono != mono || old.bars != bars || old.circle[0] != circle[0] || old.circle[1] != circle[1];
}
