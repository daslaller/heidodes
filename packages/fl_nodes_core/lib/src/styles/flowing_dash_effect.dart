import 'dart:ui';

import 'link_effect.dart';

/// Dashed stroke that marches along the path (Vyuh / React Flow style).
class FlowingDashEffect implements FlLinkEffect {
  const FlowingDashEffect({
    this.dashLength = 6.0,
    this.gapLength = 4.0,
    this.speed = 2.0,
    this.strokeWidth,
    this.color,
  });

  final double dashLength;
  final double gapLength;
  final double speed;
  final double? strokeWidth;
  final Color? color;

  @override
  void paint(
    Canvas canvas,
    Path path,
    Paint basePaint,
    double animationValue,
  ) {
    final pathMetrics = path.computeMetrics();
    if (pathMetrics.isEmpty) return;

    final double totalLength = pathMetrics.fold<double>(
      0,
      (sum, metric) => sum + metric.length,
    );
    if (totalLength <= 0) return;

    final double patternLength = dashLength + gapLength;
    final double phase = (animationValue * speed * patternLength) % patternLength;

    final Paint effectPaint = Paint()
      ..color = color ?? basePaint.color
      ..strokeWidth = strokeWidth ?? basePaint.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = basePaint.strokeCap
      ..strokeJoin = basePaint.strokeJoin
      ..isAntiAlias = true;

    for (final metric in path.computeMetrics()) {
      var distance = -phase;
      while (distance < metric.length) {
        final double start = distance.clamp(0.0, metric.length);
        final double end = (distance + dashLength).clamp(0.0, metric.length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), effectPaint);
        }
        distance += patternLength;
      }
    }
  }
}
