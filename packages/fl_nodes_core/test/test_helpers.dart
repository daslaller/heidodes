import 'package:fl_nodes_core/fl_nodes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

export 'package:fl_nodes_core/fl_nodes_core.dart';

/// Minimal no-op effect for active-tier tests.
class NoOpLinkEffect implements FlLinkEffect {
  int paintCount = 0;

  @override
  void paint(
    Canvas canvas,
    Path path,
    Paint basePaint,
    double animationValue,
  ) {
    paintCount++;
    canvas.drawPath(path, basePaint);
  }
}

class TestTickerProvider extends TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

void registerTestNodePrototype(FlNodesController controller) {
  controller.registerNodePrototype(
    FlNodePrototype(
      idName: 'test.node',
      displayName: (_) => 'Test',
      description: (_) => 'Test node',
      portPrototypes: [
        FlDataOutputPortPrototype<dynamic>(
          idName: 'out',
          displayName: (_) => 'Out',
          geometricOrientation: FlPortGeometricOrientation.right,
          linkPrototype: FlLinkPrototype(label: (_) => ''),
        ),
        FlDataInputPortPrototype<dynamic>(
          idName: 'in',
          displayName: (_) => 'In',
          geometricOrientation: FlPortGeometricOrientation.left,
        ),
      ],
    ),
  );
}

FlNodesController createTestController({bool snapToGrid = false}) {
  final FlNodesController controller = FlNodesController(
    appVersion: '0.0.0-test',
    config: FlNodesConfig(enableSnapToGrid: snapToGrid),
  );
  registerTestNodePrototype(controller);
  return controller;
}

/// Builds a small chain of nodes with links between them.
({List<String> nodeIds, List<String> linkIds}) buildTestGraph(
  FlNodesController controller, {
  int nodeCount = 3,
}) {
  final List<String> nodeIds = [];
  final List<String> linkIds = [];

  for (var i = 0; i < nodeCount; i++) {
    final FlNodeDataModel node = controller.addNode(
      'test.node',
      offset: Offset(i * 200.0, 0),
    );
    // RenderBox.insert reads builtStyle; normally FlBaseNodeWidget sets this.
    node.builtStyle = node.prototype.styleBuilder(node.state);
    node.builtHeaderStyle = node.prototype.headerStyleBuilder(node.state);
    nodeIds.add(node.id);
    // Give ports non-zero offsets so link paths are non-degenerate.
    node.ports['out']!.offset = const Offset(100, 40);
    node.ports['in']!.offset = const Offset(0, 40);
  }

  for (var i = 0; i < nodeCount - 1; i++) {
    final FlLinkDataModel? link = controller.addLink(
      nodeIds[i],
      'out',
      nodeIds[i + 1],
      'in',
    );
    if (link != null) linkIds.add(link.id);
  }

  return (nodeIds: nodeIds, linkIds: linkIds);
}
