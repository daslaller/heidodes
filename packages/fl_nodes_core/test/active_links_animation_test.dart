import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'activeLinksAnimationValue advances continuously across repeat cycles',
    (WidgetTester tester) async {
      final FlNodesController controller = createTestController();
      final ({List<String> nodeIds, List<String> linkIds}) graph =
          buildTestGraph(controller, nodeCount: 2);

      controller.setTickerProvider(tester);
      controller.setLinkEffect(graph.linkIds.first, enabled: true);

      await tester.pump(const Duration(milliseconds: 100));
      final double t1 = controller.activeLinksAnimationValue;
      await tester.pump(const Duration(milliseconds: 1200));
      final double t2 = controller.activeLinksAnimationValue;
      await tester.pump(const Duration(milliseconds: 1200));
      final double t3 = controller.activeLinksAnimationValue;

      expect(t1, greaterThanOrEqualTo(0));
      expect(t2, greaterThan(t1));
      expect(t3, greaterThan(t2));
      // Must not reset to ~0 after each 1s AnimationController.repeat cycle.
      expect(t3, greaterThan(1.5));

      controller.dispose();
    },
  );
}
