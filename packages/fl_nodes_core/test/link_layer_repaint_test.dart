import 'dart:ui' as ui;

import 'package:fl_nodes_core/src/core/events/events.dart';
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

/// Drain frames so the portsChanged post-frame bounce settles.
Future<void> _settleEditor(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'static link layer does not repaint while active tier ticks',
    (WidgetTester tester) async {
      final FlNodesController controller = createTestController(snapToGrid: false);
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 4);

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
      await _settleEditor(tester);

      final NodeEditorRenderBox renderBox = _findRenderBox(tester);

      controller.setLinkEffect(graph.linkIds.first, enabled: true);
      await _settleEditor(tester);

      final int staticBaseline = renderBox.staticLinksLayerPaintCount;
      final int activeBaseline = renderBox.activeLinksLayerPaintCount;
      expect(staticBaseline, greaterThan(0));
      expect(controller.activeLinkIds, contains(graph.linkIds.first));

      for (var i = 0; i < 10; i++) {
        controller.eventBus.emit(FlActiveLinksTickEvent(id: 'tick-$i'));
        await tester.pump();
      }

      expect(
        renderBox.staticLinksLayerPaintCount,
        staticBaseline,
        reason: 'static repaint-boundary layer must not re-record on ticks',
      );
      expect(
        renderBox.activeLinksLayerPaintCount,
        greaterThan(activeBaseline),
        reason: 'active layer should repaint on ticks (frames may coalesce)',
      );

      controller.dispose();
      gridShader.dispose();
    },
  );

  testWidgets(
    'static link layer does not repaint during proxy drag deltas',
    (WidgetTester tester) async {
      final FlNodesController controller = createTestController(snapToGrid: false);
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 6);

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
      await _settleEditor(tester);

      final NodeEditorRenderBox renderBox = _findRenderBox(tester);
      final String draggedId = graph.nodeIds.first;

      controller.selectNodesById({draggedId});
      await _settleEditor(tester);

      controller.beginDragSelection(Offset.zero);
      await _settleEditor(tester);

      final int staticAfterBegin = renderBox.staticLinksLayerPaintCount;
      final int activeAfterBegin = renderBox.activeLinksLayerPaintCount;

      for (var i = 0; i < 20; i++) {
        controller.dragSelection(const Offset(2, 0), isWorldDelta: true);
        await tester.pump();
      }

      expect(
        renderBox.staticLinksLayerPaintCount,
        staticAfterBegin,
        reason: 'static layer must stay composited during proxy drag',
      );
      expect(
        renderBox.activeLinksLayerPaintCount,
        greaterThan(activeAfterBegin),
        reason: 'active layer tracks drag proxies',
      );

      controller.endDragSelection(const Offset(40, 0));
      await _settleEditor(tester);

      expect(
        renderBox.staticLinksLayerPaintCount,
        greaterThan(staticAfterBegin),
        reason: 'drag-end membership restore repaints static layer',
      );

      controller.dispose();
      gridShader.dispose();
    },
  );
}
