import 'package:flutter/material.dart';

import '../theme.dart';

/// The Lanway road/path mark, drawn so the app needs no image asset.
class LanwayLogo extends StatelessWidget {
  final double size;
  const LanwayLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s),
      Radius.circular(s * 0.25),
    );
    canvas.drawRRect(rrect, Paint()..color = LanwayColors.navy);

    final road = Paint()
      ..shader = const LinearGradient(
        colors: [LanwayColors.primary, LanwayColors.accent],
      ).createShader(Rect.fromLTWH(0, 0, s, s))
      ..strokeWidth = s * 0.067
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(s * 0.21, s * 0.83)
      ..lineTo(s * 0.44, s * 0.25)
      ..lineTo(s * 0.56, s * 0.25)
      ..lineTo(s * 0.79, s * 0.83);
    canvas.drawPath(path, road);

    final dash = Paint()
      ..color = LanwayColors.accent
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.5, s * 0.75), Offset(s * 0.5, s * 0.69), dash);
    canvas.drawLine(Offset(s * 0.5, s * 0.58), Offset(s * 0.5, s * 0.52), dash);
    canvas.drawLine(Offset(s * 0.5, s * 0.42), Offset(s * 0.5, s * 0.38), dash);

    canvas.drawCircle(Offset(s * 0.5, s * 0.23), s * 0.054, Paint()..color = LanwayColors.mint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Brand wordmark "Lanway" with the accent on "way".
class LanwayWordmark extends StatelessWidget {
  final double fontSize;
  const LanwayWordmark({super.key, this.fontSize = 20});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: const [
          TextSpan(text: 'Lan', style: TextStyle(color: Colors.white)),
          TextSpan(text: 'way', style: TextStyle(color: LanwayColors.accent)),
        ],
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      ),
    );
  }
}
