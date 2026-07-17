import 'package:fl_nodes/fl_nodes.dart';
import 'package:fl_nodes_example/visual_scripting_example/nodes/styles/theme.dart';
import 'package:flutter/material.dart';

// Namespace for static style helpers.
// ignore: avoid_classes_with_only_static_members
/// Node chrome matching Vyuh Image Effects Pipeline.
abstract final class NodeStyles {
  static FlNodeStyle standard(FlNodeState state) {
    final Color borderColor = state.isSelected
        ? VyuhEditorTheme.borderSelected
        : state.isHovered
            ? VyuhEditorTheme.borderHover
            : VyuhEditorTheme.border;

    final Color background = state.isSelected
        ? VyuhEditorTheme.nodeBgSelected
        : state.isHovered
            ? VyuhEditorTheme.nodeBgHover
            : VyuhEditorTheme.nodeBg;

    return FlNodeStyle(
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.fromBorderSide(
          BorderSide(color: borderColor),
        ),
      ),
    );
  }
}
