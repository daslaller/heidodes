import 'dart:ui';

import 'package:fl_nodes_core/src/core/models/paint.dart';
import 'package:fl_nodes_core/src/painters/custom_painter.dart';
import 'package:fl_nodes_core/src/painters/link_path_builder.dart';

class TmpLinkCustomPainter extends FlCustomPainter {
  LinkPaintModel? tmpLinkData;

  TmpLinkCustomPainter(super.controller);

  @override
  void paint(Canvas canvas, Rect viewport) {
    if (tmpLinkData == null) return;

    final Path path = LinkPathBuilder.compute(tmpLinkData!);

    final Paint paint = Paint();

    if (tmpLinkData!.linkStyle.gradient != null) {
      final Shader shader = tmpLinkData!.linkStyle.gradient!.createShader(
        Rect.fromPoints(
          tmpLinkData!.outPortOffset,
          tmpLinkData!.inPortOffset,
        ),
      );

      paint
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = tmpLinkData!.linkStyle.lineWidth;
    } else {
      paint
        ..color = tmpLinkData!.linkStyle.color!
        ..style = PaintingStyle.stroke
        ..strokeWidth = tmpLinkData!.linkStyle.lineWidth;
    }

    canvas.drawPath(path, paint);
  }
}
