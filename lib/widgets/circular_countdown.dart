import 'dart:math' as math;

import 'package:flutter/material.dart';

class CircularCountdown extends StatelessWidget {
  const CircularCountdown({
    super.key,
    required this.progress,
    required this.seconds,
    required this.label,
    required this.gradient,
  });

  final double progress;
  final int seconds;
  final String label;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0.0, 1.0);

    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _CountdownPainter(
          progress: safeProgress,
          gradient: gradient,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(seconds),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _CountdownPainter extends CustomPainter {
  _CountdownPainter({required this.progress, required this.gradient});

  final double progress;
  final List<Color> gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.44;

    final basePaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);

    final arcPaint = Paint()
      ..shader = SweepGradient(
        colors: gradient,
        startAngle: -math.pi / 2,
        endAngle: math.pi * 3 / 2,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.gradient != gradient;
  }
}
