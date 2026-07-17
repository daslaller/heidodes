import 'package:fl_nodes_core/src/core/models/paint.dart';
import 'package:fl_nodes_core/src/core/utils/rendering/paths.dart';
import 'package:fl_nodes_core/src/styles/styles.dart';
import 'package:flutter/material.dart';

/// Shared path computation for link painters and the temp-link painter.
abstract final class LinkPathBuilder {
  static Path compute(LinkPaintModel data) => computeFromCurveType(
        data.linkStyle.curveType,
        data,
      );

  static Path computeFromCurveType(
    FlLinkCurveType curveType,
    LinkPaintModel data,
  ) =>
      switch (curveType) {
        FlLinkCurveType.straight => PathUtils.computeStraightLinkPath(
            outPortOffset: data.outPortOffset,
            inPortOffset: data.inPortOffset,
          ),
        FlLinkCurveType.bezier => PathUtils.computeBezierLinkPath(
            outPortOffset: data.outPortOffset,
            inPortOffset: data.inPortOffset,
            outPortGeometricOrientation: data.outPortGeometricOrientation,
            inPortGeometricOrientation: data.inPortGeometricOrientation,
          ),
        FlLinkCurveType.ninetyDegree => PathUtils.computeNinetyDegreesLinkPath(
            outPortOffset: data.outPortOffset,
            inPortOffset: data.inPortOffset,
            outPortGeometricOrientation: data.outPortGeometricOrientation,
            inPortGeometricOrientation: data.inPortGeometricOrientation,
          ),
      };
}
