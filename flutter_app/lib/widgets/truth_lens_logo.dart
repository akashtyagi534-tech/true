import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class TruthLensLogo extends StatefulWidget {
  final double size;
  final bool animate;

  const TruthLensLogo({
    super.key,
    this.size = 76,
    this.animate = true,
  });

  @override
  State<TruthLensLogo> createState() => _TruthLensLogoState();
}

class _TruthLensLogoState extends State<TruthLensLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _TruthLensLogoPainter(progress: _controller.value),
          ),
        );
      },
    );
  }
}

class _TruthLensLogoPainter extends CustomPainter {
  final double progress;
  _TruthLensLogoPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer ambient glow
    final glowPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0x55A855F7),
          Color(0x3322D3EE),
          Color(0x00050814),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, glowPaint);

    // Dark badge core
    final coreBg = Paint()..color = const Color(0xFF070C20);
    canvas.drawCircle(center, r * 0.86, coreBg);

    // Rotating outer radar ring
    final radarPaint = Paint()
      ..color = TruthLensColors.neonCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, size.width * 0.03)
      ..strokeCap = StrokeCap.round;

    final double startAngle = progress * math.pi * 2;
    for (int i = 0; i < 4; i++) {
      final a = startAngle + i * (math.pi / 2);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 0.84),
        a,
        math.pi * 0.28,
        false,
        radarPaint,
      );
    }

    // Counter-rotating purple ring
    final innerRingPaint = Paint()
      ..color = TruthLensColors.neonPurple
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, size.width * 0.024);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.72),
      -startAngle * 1.2,
      math.pi * 1.25,
      false,
      innerRingPaint,
    );

    // Futuristic AI Eye contour
    final eyePath = Path()
      ..moveTo(center.dx - r * 0.56, center.dy)
      ..quadraticBezierTo(
        center.dx,
        center.dy - r * 0.52,
        center.dx + r * 0.56,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx,
        center.dy + r * 0.52,
        center.dx - r * 0.56,
        center.dy,
      )
      ..close();

    final eyeStroke = Paint()
      ..shader = const LinearGradient(
        colors: [TruthLensColors.neonPurple, TruthLensColors.neonCyan],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.6))
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.2, size.width * 0.045)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(eyePath, eyeStroke);

    // Glowing Iris
    final double pulse = 1.0 + 0.08 * math.sin(progress * math.pi * 2);
    final irisPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [TruthLensColors.neonCyan, TruthLensColors.neonPurple],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.28));
    canvas.drawCircle(center, r * 0.24 * pulse, irisPaint);

    // Pupil core + highlight dot
    canvas.drawCircle(center, r * 0.11, Paint()..color = const Color(0xFF040712));
    canvas.drawCircle(
      Offset(center.dx + r * 0.08, center.dy - r * 0.08),
      r * 0.045,
      Paint()..color = Colors.white,
    );

    // Soundwave bars at bottom of badge
    final wavePaint = Paint()
      ..color = TruthLensColors.neonCyan
      ..strokeWidth = math.max(1.6, size.width * 0.025)
      ..strokeCap = StrokeCap.round;
    final double waveY = center.dy + r * 0.54;
    for (int i = -3; i <= 3; i++) {
      final double x = center.dx + i * (r * 0.11);
      final double h = r *
          (0.05 +
              0.08 *
                  (0.5 +
                      0.5 *
                          math.sin(progress * math.pi * 4 + i * 0.9)));
      canvas.drawLine(Offset(x, waveY - h), Offset(x, waveY + h), wavePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TruthLensLogoPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
