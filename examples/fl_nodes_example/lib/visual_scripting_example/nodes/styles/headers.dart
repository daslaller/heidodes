import 'package:fl_nodes/fl_nodes.dart';
import 'package:fl_nodes_example/visual_scripting_example/nodes/styles/theme.dart';
import 'package:flutter/material.dart';

// Namespace for static style helpers.
// ignore: avoid_classes_with_only_static_members
/// Header styles matching Vyuh Image Effects Pipeline (tinted minimal bar).
abstract final class NodeHeaderStyles {
  static FlNodeHeaderStyle _tinted(Color accent) => FlNodeHeaderStyle(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
        ),
        textStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accent.withValues(alpha: 0.9),
          letterSpacing: 0.2,
        ),
        icon: Icons.expand_more,
      );

  static FlNodeHeaderStyle value(FlNodeState state) =>
      _tinted(VyuhEditorTheme.valueAccent);

  static FlNodeHeaderStyle generator(FlNodeState state) =>
      _tinted(VyuhEditorTheme.generatorAccent);

  static FlNodeHeaderStyle logic(FlNodeState state) =>
      _tinted(VyuhEditorTheme.logicAccent);

  static FlNodeHeaderStyle math(FlNodeState state) =>
      _tinted(VyuhEditorTheme.mathAccent);

  static FlNodeHeaderStyle flow(FlNodeState state) =>
      _tinted(VyuhEditorTheme.flowAccent);

  static FlNodeHeaderStyle io(FlNodeState state) =>
      _tinted(VyuhEditorTheme.ioAccent);
}
