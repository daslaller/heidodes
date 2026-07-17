import 'dart:ui';

import 'package:fl_nodes_core/src/core/events/events.dart';
import 'package:fl_nodes_core/src/painters/links.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Drag proxy path', () {
    test('live deltas do not commit model or dirty data; end commits once', () async {
      final FlNodesController controller = createTestController(snapToGrid: false);
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 50);

      for (var i = 0; i < 150; i++) {
        controller.addNode('test.node', offset: Offset(i * 10.0, 400));
      }

      final String draggedId = graph.nodeIds.first;
      final Offset startOffset = controller.nodes[draggedId]!.offset;

      controller
        ..selectNodesById({draggedId})
        ..linksDataDirty = false
        ..nodesDataDirty = false;

      final List<NodeEditorEvent> events = [];
      final sub = controller.eventBus.events.listen(events.add);

      controller.beginDragSelection(Offset.zero);
      expect(controller.isDraggingSelection, isTrue);
      expect(controller.activeLinkIds, isNotEmpty);
      expect(controller.activeLinkIds.contains(graph.linkIds.first), isTrue);

      expect(controller.linksDataDirty, isTrue);
      controller
        ..linksDataDirty = false
        ..nodesDataDirty = false;

      for (var i = 0; i < 30; i++) {
        controller.dragSelection(const Offset(1, 0), isWorldDelta: true);
      }

      expect(controller.nodesDataDirty, isFalse);
      expect(controller.linksDataDirty, isFalse);
      expect(
        controller.nodes[draggedId]!.offset,
        startOffset,
        reason: 'committed offset must stay frozen during proxy drag',
      );
      expect(
        controller.dragProxyOffsets[draggedId],
        startOffset + const Offset(30, 0),
      );

      controller.endDragSelection(const Offset(30, 0));
      await _flushMicrotasks();

      expect(controller.isDraggingSelection, isFalse);
      expect(controller.dragProxyOffsets, isEmpty);
      expect(
        controller.nodes[draggedId]!.offset,
        startOffset + const Offset(30, 0),
      );
      expect(controller.nodesDataDirty, isTrue);
      expect(controller.linksDataDirty, isTrue);

      final List<FlDragSelectionEvent> liveDragEvents =
          events.whereType<FlDragSelectionEvent>().toList();
      expect(liveDragEvents.length, 30);
      for (final FlDragSelectionEvent event in liveDragEvents) {
        expect(event, isA<FlDragProxyEventCat>());
        expect(event, isA<FlPaintEventCat>());
        expect(event, isNot(isA<FlLayoutEventCat>()));
        expect(event.isUndoable, isFalse);
      }

      final List<FlDragSelectionCommitEvent> commits =
          events.whereType<FlDragSelectionCommitEvent>().toList();
      expect(commits.length, 1);
      expect(commits.single.delta, const Offset(30, 0));
      expect(commits.single, isA<FlLayoutEventCat>());
      expect(commits.single.isUndoable, isTrue);

      final List<FlDragSelectionEndEvent> ends =
          events.whereType<FlDragSelectionEndEvent>().toList();
      expect(ends.length, 1);

      expect(controller.activeLinkIds, isEmpty);

      await sub.cancel();
      controller.dispose();
    });

    test('static painter does not recompute during proxy drag deltas', () {
      final FlNodesController controller = createTestController(snapToGrid: false);
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 20);

      final LinksHitTestData hitTestData = LinksHitTestData();
      final StaticLinksPainter staticPainter = StaticLinksPainter(
        controller,
        hitTestData: hitTestData,
      );
      final ActiveLinksPainter activePainter = ActiveLinksPainter(
        controller,
        hitTestData: hitTestData,
      );

      final PictureRecorder recorder = PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      const Rect viewport = Rect.fromLTWH(-2000, -2000, 8000, 8000);

      controller.linksDataDirty = true;
      staticPainter.paint(canvas, viewport);
      activePainter.paint(canvas, viewport);
      controller.linksDataDirty = false;

      final String draggedId = graph.nodeIds.first;
      controller
        ..selectNodesById({draggedId})
        ..beginDragSelection(Offset.zero);

      staticPainter.paint(canvas, viewport);
      activePainter.paint(canvas, viewport, proxyChanged: true);
      controller
        ..linksDataDirty = false
        ..nodesDataDirty = false;

      final int afterBegin = staticPainter.staticLinkRecomputeCount;

      for (var i = 0; i < 30; i++) {
        controller.dragSelection(const Offset(2, 0), isWorldDelta: true);
        activePainter.paint(canvas, viewport, proxyChanged: true);
        staticPainter.paint(canvas, viewport);
      }

      expect(
        staticPainter.staticLinkRecomputeCount,
        afterBegin,
        reason: 'static links must not recompute during proxy deltas',
      );

      controller.endDragSelection(const Offset(60, 0));
      staticPainter.paint(canvas, viewport);
      activePainter.paint(canvas, viewport);

      expect(
        staticPainter.staticLinkRecomputeCount,
        afterBegin + 1,
        reason: 'static tier recomputes once on drag-end commit',
      );

      controller.dispose();
    });

    test('undo uses commit event total delta', () async {
      final FlNodesController controller = createTestController(snapToGrid: false);
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 2);
      final String draggedId = graph.nodeIds.first;
      final Offset startOffset = controller.nodes[draggedId]!.offset;

      controller
        ..selectNodesById({draggedId})
        ..beginDragSelection(Offset.zero)
        ..dragSelection(const Offset(10, 5), isWorldDelta: true)
        ..dragSelection(const Offset(10, 5), isWorldDelta: true)
        ..endDragSelection(const Offset(20, 10))
        ..clearSelection();

      await _flushMicrotasks();

      expect(
        controller.nodes[draggedId]!.offset,
        startOffset + const Offset(20, 10),
      );

      controller.history.undo();
      await _flushMicrotasks();

      expect(controller.nodes[draggedId]!.offset, startOffset);

      controller.dispose();
    });
  });
}
