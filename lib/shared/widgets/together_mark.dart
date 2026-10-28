import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Original static vector artwork. No image downloads, motion, or GPU filters.
class TogetherMark extends StatelessWidget {
  const TogetherMark({this.size = 220, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter()),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 240);
    for (var i = 0; i < 2; i++) {
      canvas.save();
      canvas.translate(i == 0 ? 93 : 147, 120);
      canvas.rotate(i == 0 ? -math.pi / 5 : math.pi / 5);
      final rect = Rect.fromCenter(center: Offset.zero, width: 80, height: 148);
      final path = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(40)));
      final bounds = rect.inflate(16);
      canvas.drawPath(
        path.shift(const Offset(0, 8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 25
          ..color = const Color(0x22893E68),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 25
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: i == 0
                ? const [
                    Color(0xFFFFE3D5),
                    Color(0xFFF19AAF),
                    Color(0xFFA95580),
                  ]
                : const [
                    Color(0xFFEAE0FF),
                    Color(0xFFBA9CE9),
                    Color(0xFF76559E),
                  ],
          ).createShader(bounds),
      );
      canvas.drawArc(
        rect,
        math.pi * 1.04,
        math.pi * 0.8,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
          ).createShader(bounds),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
