import 'package:fl_nodes/fl_nodes.dart';
import 'package:fl_nodes_example/visual_scripting_example/nodes/styles/theme.dart';
import 'package:flutter/material.dart';

// Namespace for static style helpers.
// ignore: avoid_classes_with_only_static_members
/// Port styles matching Vyuh Image Effects Pipeline.
abstract final class PortStyles {
  static const FlowingDashEffect _flowEffect = FlowingDashEffect(
    dashLength: 6,
    gapLength: 4,
    speed: 2,
  );

  static FlLinkStyle _linkStyle(FlLinkState state, Color accent) => FlLinkStyle(
        color: state.isSelected || state.isHovered
            ? VyuhEditorTheme.borderSelected
            : VyuhEditorTheme.link,
        lineWidth: state.isSelected || state.isHovered ? 2.0 : 1.5,
        drawMode: FlLineDrawMode.solid,
        curveType: FlLinkCurveType.bezier,
        effect: _flowEffect,
      );

  static FlPortStyle _port({
    required FlPortState state,
    required Color accent,
    required FlPortShape shape,
  }) =>
      FlPortStyle(
        color: state.isHovered ? accent : VyuhEditorTheme.portIdle,
        shape: shape,
        radius: state.isHovered ? 5 : 4,
        linkStyleBuilder: (linkState) => _linkStyle(linkState, accent),
      );

  static FlPortStyle dataOutput(FlPortState state) => _port(
        state: state,
        accent: VyuhEditorTheme.dataAccent,
        shape: FlPortShape.circle,
      );

  static FlPortStyle dataInput(FlPortState state) => _port(
        state: state,
        accent: VyuhEditorTheme.dataAccent,
        shape: FlPortShape.circle,
      );

  static FlPortStyle controlOutput(FlPortState state) => _port(
        state: state,
        accent: VyuhEditorTheme.controlAccent,
        shape: FlPortShape.triangle,
      );

  static FlPortStyle controlInput(FlPortState state) => _port(
        state: state,
        accent: VyuhEditorTheme.controlAccent,
        shape: FlPortShape.triangle,
      );
}
