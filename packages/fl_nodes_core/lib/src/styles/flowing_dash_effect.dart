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
    final PathMetrics metrics = path.computeMetrics();
    if (metrics.isEmpty) return;

    final double patternLength = dashLength + gapLength;
    if (patternLength <= 0) return;

    // [animationValue] is continuous seconds (not a 0..1 loop) so phase
    // never jumps when the ticker repeats.
    final double phase = (animationValue * speed * patternLength) % patternLength;

    final Paint effectPaint = Paint()
      ..color = color ?? basePaint.color
      ..strokeWidth = strokeWidth ?? basePaint.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Re-compute metrics: PathMetrics iteration is single-pass.
    for (final PathMetric metric in path.computeMetrics()) {
      if (metric.length <= 0) continue;

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
