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

  group('StaticLinksPainter / ActiveLinksPainter split', () {
    test('static recompute stays flat while only active tier paints', () {
      final FlNodesController controller = createTestController();
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 3);
      expect(graph.linkIds.length, 2);

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
      const Rect viewport = Rect.fromLTWH(-500, -500, 2000, 2000);

      controller
        ..linksDataDirty = true
        ..nodesDataDirty = true;
      staticPainter.paint(canvas, viewport);
      activePainter.paint(canvas, viewport);
      controller
        ..linksDataDirty = false
        ..nodesDataDirty = false;

      final int afterInitial = staticPainter.staticLinkRecomputeCount;
      expect(afterInitial, 1);

      controller.setLinkEffect(graph.linkIds.first, enabled: true);
      expect(controller.activeLinkIds.contains(graph.linkIds.first), isTrue);

      staticPainter.paint(canvas, viewport);
      activePainter.paint(canvas, viewport);
      controller
        ..linksDataDirty = false
        ..nodesDataDirty = false;

      final int afterMembership = staticPainter.staticLinkRecomputeCount;
      expect(afterMembership, afterInitial + 1);

      for (var i = 0; i < 10; i++) {
        activePainter.paint(canvas, viewport);
        expect(controller.linksDataDirty, isFalse);
        expect(controller.nodesDataDirty, isFalse);
        staticPainter.paint(canvas, viewport);
      }

      expect(
        staticPainter.staticLinkRecomputeCount,
        afterMembership,
        reason: 'static tier must not recompute on active-only paints',
      );

      controller.dispose();
    });

    test('active ticker never sets linksDataDirty', () async {
      final FlNodesController controller = createTestController();
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 2);

      var tickCount = 0;
      final sub = controller.eventBus.events.listen((event) {
        if (event is FlActiveLinksTickEvent) {
          tickCount++;
          expect(controller.linksDataDirty, isFalse);
        }
      });

      controller.setTickerProvider(TestTickerProvider());
      controller
        ..setLinkEffect(graph.linkIds.first, enabled: true)
        ..linksDataDirty = false;

      expect(controller.activeLinkIds, isNotEmpty);

      for (var i = 0; i < 10; i++) {
        controller.eventBus.emit(FlActiveLinksTickEvent(id: 'tick-$i'));
      }
      await _flushMicrotasks();

      expect(tickCount, 10);
      expect(controller.linksDataDirty, isFalse);

      controller
        ..setLinkEffect(graph.linkIds.first, enabled: false)
        ..linksDataDirty = false;
      expect(controller.activeLinkIds, isEmpty);

      await sub.cancel();
      controller.dispose();
    });
  });
}
