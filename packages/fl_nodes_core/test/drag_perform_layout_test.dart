import 'dart:ui' as ui;

import 'package:fl_nodes_core/src/widgets/node_editor_render_object.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

NodeEditorRenderBox _findRenderBox(WidgetTester tester) {
  final Element element = tester.element(
    find.byType(NodeEditorRenderObjectWidget),
  );
  return element.renderObject! as NodeEditorRenderBox;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'proxy drag does not call performLayout per pointer delta',
    (WidgetTester tester) async {
      final FlNodesController controller = createTestController(snapToGrid: false);
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 20);

      final ui.FragmentProgram program = await ui.FragmentProgram.fromAsset(
        'lib/shaders/grid.frag',
      );
      final ui.FragmentShader gridShader = program.fragmentShader();

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: NodeEditorRenderObjectWidget(
              controller: controller,
              gridShader: gridShader,
              nodeBuilder: (node, _) => SizedBox(
                key: node.key,
                width: 120,
                height: 80,
                child: const ColoredBox(color: Color(0xFF455A64)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final NodeEditorRenderBox renderBox = _findRenderBox(tester);
      final String draggedId = graph.nodeIds.first;
      final Offset startOffset = controller.nodes[draggedId]!.offset;

      controller.selectNodesById({draggedId});
      await tester.pump();
      await tester.pump();

      // Selection layout settled — baseline for the proxy drag window.
      final int layoutBaseline = renderBox.performLayoutCount;

      controller.beginDragSelection(Offset.zero);
      await tester.pump();
      await tester.pump();

      expect(
        renderBox.performLayoutCount - layoutBaseline,
        0,
        reason: 'beginDragSelection is paint-only',
      );

      for (var i = 0; i < 30; i++) {
        final int before = renderBox.performLayoutCount;
        controller.dragSelection(const Offset(3, 0), isWorldDelta: true);
        await tester.pump();
        expect(
          renderBox.performLayoutCount - before,
          0,
          reason: 'delta $i must not call performLayout',
        );
      }

      final int layoutAfterDeltas = renderBox.performLayoutCount;
      expect(layoutAfterDeltas - layoutBaseline, 0);

      controller.endDragSelection(const Offset(90, 0));
      await tester.pump();
      await tester.pump();

      expect(
        renderBox.performLayoutCount - layoutAfterDeltas,
        inInclusiveRange(1, 3),
        reason: 'drag-end commit should trigger a bounded layout pass',
      );

      expect(controller.isDraggingSelection, isFalse);
      expect(
        controller.nodes[draggedId]!.offset,
        startOffset + const Offset(90, 0),
      );

      controller.dispose();
      gridShader.dispose();
    },
  );
}
