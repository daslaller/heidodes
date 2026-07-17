import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resyncLinkEffects activates links whose port style has an effect', () {
    final NoOpLinkEffect effect = NoOpLinkEffect();
    final FlNodesController controller = FlNodesController(
      appVersion: '0.0.0-test',
      config: const FlNodesConfig(enableSnapToGrid: false),
    );

    controller.registerNodePrototype(
      FlNodePrototype(
        idName: 'effect.node',
        displayName: (_) => 'Effect',
        description: (_) => '',
        portPrototypes: [
          FlDataOutputPortPrototype<dynamic>(
            idName: 'out',
            displayName: (_) => 'Out',
            geometricOrientation: FlPortGeometricOrientation.right,
            linkPrototype: FlLinkPrototype(label: (_) => ''),
            styleBuilder: (_) => FlPortStyle(
              shape: FlPortShape.circle,
              color: const Color(0xFF60A5FA),
              radius: 4,
              linkStyleBuilder: (_) => FlLinkStyle(
                color: const Color(0xFF60A5FA),
                lineWidth: 1.75,
                drawMode: FlLineDrawMode.solid,
                curveType: FlLinkCurveType.bezier,
                effect: effect,
              ),
            ),
          ),
          FlDataInputPortPrototype<dynamic>(
            idName: 'in',
            displayName: (_) => 'In',
            geometricOrientation: FlPortGeometricOrientation.left,
            styleBuilder: (_) => const FlPortStyle.basic(),
          ),
        ],
      ),
    );

    final FlNodeDataModel a = controller.addNode(
      'effect.node',
      offset: Offset.zero,
    );
    final FlNodeDataModel b = controller.addNode(
      'effect.node',
      offset: const Offset(200, 0),
    );
    a
      ..builtStyle = a.prototype.styleBuilder(a.state)
      ..builtHeaderStyle = a.prototype.headerStyleBuilder(a.state);
    b
      ..builtStyle = b.prototype.styleBuilder(b.state)
      ..builtHeaderStyle = b.prototype.headerStyleBuilder(b.state);
    a.ports['out']!.offset = const Offset(100, 40);
    b.ports['in']!.offset = const Offset(0, 40);

    final FlLinkDataModel? link = controller.addLink(a.id, 'out', b.id, 'in');
    expect(link, isNotNull);
    expect(controller.activeLinkIds, contains(link!.id));

    // Simulate project-load mid-state: membership cleared, links retained.
    controller.clear();
    expect(controller.activeLinkIds, isEmpty);
    expect(controller.links.containsKey(link.id), isTrue);

    controller.resyncLinkEffects();
    expect(
      controller.activeLinkIds,
      contains(link.id),
      reason: 'loaded links with style.effect must rejoin the active tier',
    );

    controller.dispose();
  });
}
