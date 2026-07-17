import 'package:fl_nodes_core/src/core/controller/core.dart';
import 'package:fl_nodes_core/src/core/models/data.dart';
import 'package:fl_nodes_core/src/core/models/paint.dart';
import 'package:fl_nodes_core/src/painters/custom_painter.dart';
import 'package:fl_nodes_core/src/painters/link_path_builder.dart';
import 'package:fl_nodes_core/src/styles/styles.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared hit-test path cache for static + active link painters.
class LinksHitTestData {
  final Map<String, (Rect, Path)> data = {};

  void clear() => data.clear();

  void removeIds(Iterable<String> ids) {
    for (final id in ids) {
      data.remove(id);
    }
  }

  void put(String linkId, Path path) {
    data[linkId] = (path.getBounds(), path);
  }

  Offset? getLinkLabelCenter(String linkId) => data[linkId]?.$1.center;
}

LinkPaintModel? buildLinkPaintModel({
  required FlNodesController controller,
  required FlLinkDataModel link,
  required Rect viewport,
  required bool shouldDrawLabels,
}) {
  final FlNodeDataModel? node1 = controller.getNodeById(link.ports.$1.nodeId);
  final FlNodeDataModel? node2 = controller.getNodeById(link.ports.$2.nodeId);
  if (node1 == null || node2 == null) return null;

  final FlPortDataModel? port1 = node1.ports[link.ports.$1.portId];
  final FlPortDataModel? port2 = node2.ports[link.ports.$2.portId];
  if (port1 == null || port2 == null) return null;

  final Offset outPortOffset = controller.nodePaintOffset(link.ports.$1.nodeId) + port1.offset;
  final Offset inPortOffset = controller.nodePaintOffset(link.ports.$2.nodeId) + port2.offset;

  final Rect pathBounds = Rect.fromPoints(outPortOffset, inPortOffset);
  if (!viewport.overlaps(pathBounds)) return null;

  final FlLinkStyle linkStyle = port1.style.linkStyleBuilder(link.state);

  String? labelText;
  Rect? fromNodeBounds;
  Rect? toNodeBounds;

  if (shouldDrawLabels) {
    final BuildContext? context = controller.editorKey.currentContext;
    if (context != null) {
      labelText = port1.prototype.linkPrototype.label(context);

      if (labelText.isNotEmpty) {
        fromNodeBounds = node1.cachedRenderboxRect;
        toNodeBounds = node2.cachedRenderboxRect;
      }
    }
  }

  return LinkPaintModel(
    linkId: link.id,
    outPortOffset: outPortOffset,
    inPortOffset: inPortOffset,
    outPortGeometricOrientation: port1.prototype.geometricOrientation,
    inPortGeometricOrientation: port2.prototype.geometricOrientation,
    linkStyle: linkStyle,
    labelText: labelText,
    fromNodeBounds: fromNodeBounds,
    toNodeBounds: toNodeBounds,
  );
}

/// Static (batched) links — excludes [FlNodesController.activeLinkIds].
class StaticLinksPainter extends FlCustomPainter {
  final List<(Path, Paint)> _unbatchableLinks = [];
  final Map<FlLinkStyle, (Path, Paint)> _solidColorLinkBatches = {};
  final LinksHitTestData hitTestData;
  final Map<String, TextPainter> _labelTextPainters = {};

  @visibleForTesting
  int staticLinkRecomputeCount = 0;

  StaticLinksPainter(super.controller, {required this.hitTestData});

  @override
  void paint(
    Canvas canvas,
    Rect viewport, {
    bool transformChanged = false,
    bool portsChanged = false,
  }) {
    final bool shouldDrawLabels = controller.lodLevel >= 3;

    // Skip nodesDataDirty during proxy drag — active tier owns those links.
    final bool nodesMovedOutsideDrag = controller.nodesDataDirty && !controller.isDraggingSelection;

    if (controller.linksDataDirty || nodesMovedOutsideDrag || transformChanged || portsChanged) {
      staticLinkRecomputeCount++;

      final List<LinkPaintModel> linkDrawData = [];

      _unbatchableLinks.clear();
      _solidColorLinkBatches.clear();

      final Set<String> activeIds = controller.activeLinkIds;
      final List<String> staticIdsToClear =
          hitTestData.data.keys.where((id) => !activeIds.contains(id)).toList();
      hitTestData.removeIds(staticIdsToClear);

      if (controller.linksDataDirty) {
        _labelTextPainters.clear();
      }

      for (final FlLinkDataModel link in controller.links.values) {
        if (activeIds.contains(link.id)) continue;

        final LinkPaintModel? data = buildLinkPaintModel(
          controller: controller,
          link: link,
          viewport: viewport,
          shouldDrawLabels: shouldDrawLabels,
        );
        if (data == null) continue;
        linkDrawData.add(data);
      }

      for (final data in linkDrawData) {
        final Path path = LinkPathBuilder.compute(data);
        hitTestData.put(data.linkId, path);

        if (data.linkStyle.gradient != null) {
          final Shader shader = data.linkStyle.gradient!.createShader(
            Rect.fromPoints(data.outPortOffset, data.inPortOffset),
          );

          final Paint paint = Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = data.linkStyle.lineWidth;

          _unbatchableLinks.add((path, paint));
        } else {
          final FlLinkStyle style = data.linkStyle;
          _solidColorLinkBatches.putIfAbsent(
            style,
            () => (
              Path(),
              Paint()
                ..color = style.color!
                ..style = PaintingStyle.stroke
                ..strokeWidth = style.lineWidth
            ),
          );

          _solidColorLinkBatches[style]!.$1.addPath(path, Offset.zero);
        }

        if (shouldDrawLabels && data.labelText != null && data.labelText!.isNotEmpty) {
          _cacheTextPainter(data.linkId, data.labelText!);
        }
      }
    }

    canvas.saveLayer(viewport, Paint());

    for (final MapEntry<FlLinkStyle, (Path, Paint)> entry in _solidColorLinkBatches.entries) {
      final (Path path, Paint paint) = entry.value;
      canvas.drawPath(path, paint);
    }

    for (final (path, paint) in _unbatchableLinks) {
      canvas.drawPath(path, paint);
    }

    if (shouldDrawLabels) {
      _drawLinkLabels(canvas);
    }

    canvas.restore();
  }

  void _cacheTextPainter(String linkId, String labelText) {
    if (_labelTextPainters.containsKey(linkId)) return;

    final textSpan = TextSpan(
      text: labelText,
      style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    _labelTextPainters[linkId] = textPainter;
  }

  void _drawLinkLabels(Canvas canvas) {
    const margin = 8.0;
    const padding = 4.0;
    final clearPaint = Paint()..blendMode = BlendMode.clear;

    for (final MapEntry<String, (Rect, Path)> entry in hitTestData.data.entries) {
      final String id = entry.key;
      if (controller.activeLinkIds.contains(id)) continue;

      final Rect pathData = entry.value.$1;
      final TextPainter? textPainter = _labelTextPainters[id];
      if (textPainter == null) continue;

      final FlLinkDataModel? controllerLink = controller.links[id];
      if (controllerLink == null) continue;

      final FlNodeDataModel? fromNode = controller.getNodeById(controllerLink.ports.$1.nodeId);
      final FlNodeDataModel? toNode = controller.getNodeById(controllerLink.ports.$2.nodeId);
      if (fromNode == null || toNode == null) continue;

      final Rect fromNodeBounds = fromNode.cachedRenderboxRect;
      final Rect toNodeBounds = toNode.cachedRenderboxRect;
      final Offset center = pathData.center;

      final textRect = Rect.fromCenter(
        center: center,
        width: textPainter.width + margin,
        height: textPainter.height + margin,
      );

      final bool overlapsNode = fromNodeBounds.inflate(margin).overlaps(textRect) ||
          toNodeBounds.inflate(margin).overlaps(textRect);

      if (overlapsNode) continue;

      final offset = Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      );

      final labelRect = Rect.fromLTWH(
        offset.dx - padding,
        offset.dy - padding,
        textPainter.width + padding * 2,
        textPainter.height + padding * 2,
      );

      canvas.drawRect(labelRect, clearPaint);
      textPainter.paint(canvas, offset);
    }
  }
}

/// Active links (effects + drag-tracked) — recomputed independently of the static tier.
class ActiveLinksPainter extends FlCustomPainter {
  final LinksHitTestData hitTestData;
  final List<(Path, Paint, FlLinkStyle)> _drawnLinks = [];

  ActiveLinksPainter(super.controller, {required this.hitTestData});

  @override
  void paint(
    Canvas canvas,
    Rect viewport, {
    bool transformChanged = false,
    bool portsChanged = false,
    bool proxyChanged = false,
  }) {
    final Set<String> activeIds = controller.activeLinkIds;
    if (activeIds.isEmpty) {
      _drawnLinks.clear();
      return;
    }

    final bool shouldDrawLabels = controller.lodLevel >= 3;

    // Active tier always rebuilds its small membership set each paint.
    _drawnLinks.clear();
    hitTestData.removeIds(activeIds);

    for (final String linkId in activeIds) {
      final FlLinkDataModel? link = controller.links[linkId];
      if (link == null) continue;

      final LinkPaintModel? data = buildLinkPaintModel(
        controller: controller,
        link: link,
        viewport: viewport,
        shouldDrawLabels: shouldDrawLabels,
      );
      if (data == null) continue;

      final Path path = LinkPathBuilder.compute(data);
      hitTestData.put(data.linkId, path);

      final Paint paint;
      if (data.linkStyle.gradient != null) {
        final Shader shader = data.linkStyle.gradient!.createShader(
          Rect.fromPoints(data.outPortOffset, data.inPortOffset),
        );
        paint = Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = data.linkStyle.lineWidth;
      } else {
        paint = Paint()
          ..color = data.linkStyle.color ?? const Color(0xFF42A5F5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = data.linkStyle.lineWidth;
      }

      _drawnLinks.add((path, paint, data.linkStyle));
    }

    final double animationValue = controller.activeLinksAnimationValue;

    for (final (path, paint, style) in _drawnLinks) {
      final FlLinkEffect? effect = style.effect;
      if (effect != null) {
        // Faint underlay keeps the path readable; dashes provide the stripe.
        final Color baseColor = style.color ?? const Color(0xFF42A5F5);
        canvas.drawPath(
          path,
          Paint()
            ..color = baseColor.withValues(alpha: 0.22)
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.lineWidth,
        );
        effect.paint(canvas, path, paint, animationValue);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }
}

/// Backward-compatible alias during migration.
typedef LinksCustomPainter = StaticLinksPainter;
